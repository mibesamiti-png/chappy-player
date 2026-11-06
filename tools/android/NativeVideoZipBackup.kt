package dev.chappy.chappy_player

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject

/**
 * Only completed private MP4s owned by one .chappy app, chosen by the host.
 * Creates a user-selected ZIP, without exposing paths or bytes to JavaScript.
 * This is export-only. Never deletes original recordings.
 */
class NativeVideoZipBackup(private val activity: Activity) {
    companion object { const val REQUEST_CODE = 0x64C9 }
    private data class Source(val file: File, val expectedBytes: Long)
    private data class Pending(val owner: String, val sources: List<Source>,
                               val callback: MethodChannel.Result)
    private var pending: Pending? = null
    private var writing = false
    private var closed = false

    fun begin(owner: String, files: List<File>, result: MethodChannel.Result) {
        if (closed || pending != null || writing) {
            result.error("BACKUP_BUSY", "Another backup is active", null)
            return
        }
        if (files.isEmpty() || files.size > 100 ||
            !Regex("^[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+$").matches(owner) ||
            files.map { it.name }.distinct().size != files.size) {
            result.error("BACKUP_INVALID", "Invalid owner or video list", null)
            return
        }
        var total = 0L
        val sources = mutableListOf<Source>()
        for (file in files) {
            val size = file.length()
            if (!file.isFile || !Regex("^Chappy_[0-9_]+\\.mp4$").matches(file.name) ||
                size <= 0 || size > 1024L * 1024 * 1024) {
                result.error("BACKUP_INVALID", "Invalid private MP4", null)
                return
            }
            total += size
            if (total > 4L * 1024 * 1024 * 1024) {
                result.error("BACKUP_TOO_LARGE", "Backup exceeds 4GiB", null)
                return
            }
            sources.add(Source(file.canonicalFile, size))
        }
        val state = Pending(owner, sources, result)
        pending = state
        val message = sources.size.toString() + "本、約" +
            ((total + 1048575) / 1048576).toString() +
            "MiBの動画を保存します。元動画は消しません。ZIPは暗号化されないため、保存先に注意してください。続けますか？"
        AlertDialog.Builder(activity)
            .setTitle("非公開動画をまとめてZIP保存")
            .setMessage(message)
            .setNegativeButton("キャンセル") { _, _ ->
                if (pending === state) {
                    pending = null
                    result.success(mapOf("status" to "cancelled"))
                }
            }
            .setPositiveButton("保存先を選ぶ") { _, _ ->
                if (pending !== state || closed) return@setPositiveButton
                val time = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }.format(Date())
                try {
                    val picker = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        putExtra(Intent.EXTRA_TITLE, "ChappyVideos_" + time + ".zip")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(picker, REQUEST_CODE)
                } catch (error: Exception) {
                    pending = null
                    result.error("BACKUP_PICKER_FAILED", error.message, null)
                }
            }.setCancelable(false).show()
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val state = pending ?: return true
        if (writing) return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            pending = null
            state.callback.success(mapOf("status" to "cancelled"))
            return true
        }
        writing = true
        Thread {
            try {
                val response = exportAndVerify(state, uri)
                activity.runOnUiThread {
                    pending = null
                    writing = false
                    if (!closed) state.callback.success(response)
                }
            } catch (error: Exception) {
                // ACTION_CREATE_DOCUMENT creates a new file; best-effort removal
                // prevents accidental reliance on a truncated archive.
                try { activity.contentResolver.delete(uri, null, null) }
                catch (_: Exception) { }
                activity.runOnUiThread {
                    pending = null
                    writing = false
                    if (!closed) state.callback.error("BACKUP_FAILED",
                        "ZIP could not be verified; a partial file may remain: " +
                            error.message, null)
                }
            }
        }.start()
        return true
    }

    private fun exportAndVerify(state: Pending, uri: Uri): Map<String, Any> {
        val output = activity.contentResolver.openOutputStream(uri, "w")
            ?: throw IOException("Selected destination not writable")
        val zipDigest = MessageDigest.getInstance("SHA-256")
        val descriptions = JSONArray()
        val zipStream = ZipOutputStream(DigestOutputStream(output, zipDigest))
        zipStream.use { zip ->
            zip.setLevel(Deflater.NO_COMPRESSION) // MP4 is already compressed.
            for (source in state.sources) {
                if (source.file.length() != source.expectedBytes) {
                    throw IOException("Video changed before backup")
                }
                val name = source.file.name
                zip.putNextEntry(ZipEntry("videos/" + name))
                val hash = MessageDigest.getInstance("SHA-256")
                var total = 0L
                source.file.inputStream().use { input ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > source.expectedBytes) {
                            throw IOException("Video grew during backup")
                        }
                        zip.write(buffer, 0, count)
                        hash.update(buffer, 0, count)
                    }
                }
                if (total != source.expectedBytes ||
                    source.file.length() != source.expectedBytes) {
                    throw IOException("Video size changed during backup")
                }
                zip.closeEntry()
                descriptions.put(JSONObject().apply {
                    put("name", name)
                    put("sizeBytes", total)
                    put("sha256", hex(hash.digest()))
                })
            }
            val manifest = JSONObject().apply {
                put("schemaVersion", 1)
                put("type", "chappy-private-video-backup")
                put("ownerId", state.owner)
                put("createdMs", System.currentTimeMillis())
                put("fileCount", state.sources.size)
                put("files", descriptions)
            }.toString(2).toByteArray(Charsets.UTF_8)
            zip.putNextEntry(ZipEntry("manifest.json"))
            zip.write(manifest)
            zip.closeEntry()
        }
        val hashBefore = zipDigest.digest()
        val hashAfter = MessageDigest.getInstance("SHA-256")
        val read = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Backup cannot be verified after save")
        var bytes = 0L
        read.use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                bytes += count
                if (bytes > 4L * 1024 * 1024 * 1024 + 16L * 1024 * 1024) {
                    throw IOException("ZIP output is unexpectedly large")
                }
                hashAfter.update(buffer, 0, count)
            }
        }
        if (bytes <= 0 || !hashBefore.contentEquals(hashAfter.digest())) {
            throw IOException("Saved ZIP SHA-256 mismatch")
        }
        return mapOf("status" to "saved", "files" to state.sources.size,
            "sizeBytes" to bytes, "sha256" to hex(hashBefore))
    }

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun onDestroy() {
        closed = true
        pending = null
    }
}
