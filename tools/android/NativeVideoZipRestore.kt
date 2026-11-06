package dev.chappy.chappy_player

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipInputStream
import org.json.JSONObject

/**
 * Import only verified, owner-matching Chappy private-video ZIP backups.
 * All video bytes are first checked and staged into app-private temporary files.
 * Nothing becomes a visible MP4 until validation and a second user confirmation.
 * Never overwrite existing files, follow ZIP paths, or run outside user consent.
 */
class NativeVideoZipRestore(private val activity: Activity) {
    companion object {
        const val REQUEST_CODE = 0x64CA
        private const val MAX_FILES = 100
        private const val MAX_ENTRY_BYTES = 1024L * 1024 * 1024
        private const val MAX_TOTAL_BYTES = 4L * 1024 * 1024 * 1024
        private const val MAX_MANIFEST_BYTES = 256 * 1024
    }

    private data class Staged(
        val name: String, val file: File, val size: Long, val hash: String,
    )
    private data class Preview(
        val staging: File,
        val newFiles: List<Staged>,
        val duplicateCount: Int,
        val total: Int,
        val totalBytes: Long,
    )
    private data class Pending(
        val owner: String,
        val target: File,
        val callback: MethodChannel.Result,
        val unlockRecorder: () -> Unit,
        var staging: File? = null,
    )
    private var pending: Pending? = null
    private var running = false
    private var closed = false

    /** Recorder's restore lock is already acquired by the caller. */
    fun begin(
        owner: String, target: File, callback: MethodChannel.Result,
        unlockRecorder: () -> Unit,
    ) {
        if (closed || pending != null || running) {
            unlockRecorder()
            callback.error("VIDEO_RESTORE_BUSY", "Another restore is active", null)
            return
        }
        if (!Regex("^[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+$").matches(owner) ||
            !target.isDirectory || target.canonicalFile != target) {
            unlockRecorder()
            callback.error("VIDEO_RESTORE_INVALID", "Invalid owner or directory", null)
            return
        }
        val state = Pending(owner, target, callback, unlockRecorder)
        pending = state
        try {
            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(picker, REQUEST_CODE)
        } catch (error: Exception) {
            finish(state, "VIDEO_RESTORE_PICKER_FAILED", error.message)
        }
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val state = pending ?: return true
        if (running) return true
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null ||
            uri.scheme != "content") {
            finish(state, response = mapOf("status" to "cancelled"))
            return true
        }
        running = true
        Thread {
            try {
                val preview = validateAndStage(state, uri)
                activity.runOnUiThread {
                    if (closed || pending !== state) {
                        cleanup(state)
                        return@runOnUiThread
                    }
                    running = false
                    val count = preview.newFiles.size
                    val duplicates = preview.duplicateCount
                    val message = "ZIP内" + preview.total + "本（約" +
                        ((preview.totalBytes + 1048575) / 1048576) +
                        "MiB）を検証しました。新規" + count + "本、" +
                        "既存と一致する" + duplicates +
                        "本をスキップします。元の動画は上書きしません。復元しますか？"
                    AlertDialog.Builder(activity)
                        .setTitle("検証済みZIPを復元")
                        .setMessage(message)
                        .setNegativeButton("キャンセル") { _, _ ->
                            finish(state, response = mapOf("status" to "cancelled"))
                        }
                        .setPositiveButton("復元する") { _, _ ->
                            if (pending !== state || closed) return@setPositiveButton
                            running = true
                            Thread {
                                try {
                                    val restored = commitNewFiles(state, preview)
                                    activity.runOnUiThread {
                                        finish(state, response = mapOf(
                                            "status" to "restored",
                                            "restored" to restored,
                                            "skipped" to duplicates,
                                            "total" to preview.total,
                                        ))
                                    }
                                } catch (error: Exception) {
                                    activity.runOnUiThread {
                                        finish(state, "VIDEO_RESTORE_FAILED", error.message)
                                    }
                                }
                            }.start()
                        }.setCancelable(false).show()
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    finish(state, "VIDEO_RESTORE_INVALID_ZIP", error.message)
                }
            }
        }.start()
        return true
    }

    private fun validateAndStage(state: Pending, uri: Uri): Preview {
        val stage = File(state.target, ".chappy-restore-" + UUID.randomUUID())
        if (!stage.mkdir() || stage.canonicalFile.parentFile != state.target) {
            throw IOException("Cannot create private restore staging directory")
        }
        state.staging = stage
        val discovered = linkedMapOf<String, Staged>()
        var manifestBytes: ByteArray? = null
        var uncompressed = 0L
        var entries = 0
        val selected = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Selected ZIP could not be opened")
        ZipInputStream(selected.buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                entries++
                if (entries > MAX_FILES + 1 || entry.isDirectory) {
                    throw IOException("ZIP contains excessive or directory entries")
                }
                if (entry.name == "manifest.json") {
                    if (manifestBytes != null) throw IOException("Duplicate manifest")
                    val manifest = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val n = zip.read(buffer)
                        if (n < 0) break
                        if (manifest.size() + n > MAX_MANIFEST_BYTES) {
                            throw IOException("Manifest exceeds 256 KiB")
                        }
                        manifest.write(buffer, 0, n)
                    }
                    manifestBytes = manifest.toByteArray()
                } else {
                    val name = entry.name.removePrefix("videos/")
                    if (entry.name != "videos/" + name ||
                        !Regex("^Chappy_[0-9_]+\\.mp4$").matches(name) ||
                        discovered.containsKey(name)) {
                        throw IOException("Unexpected ZIP entry or duplicate name")
                    }
                    val dest = File(stage, name)
                    if (dest.canonicalFile.parentFile != stage || dest.exists()) {
                        throw IOException("Invalid ZIP entry path")
                    }
                    var bytes = 0L
                    val digest = MessageDigest.getInstance("SHA-256")
                    FileOutputStream(dest).use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val n = zip.read(buffer)
                            if (n < 0) break
                            bytes += n
                            uncompressed += n
                            if (bytes > MAX_ENTRY_BYTES || uncompressed > MAX_TOTAL_BYTES) {
                                throw IOException("ZIP video exceeds restore size limits")
                            }
                            output.write(buffer, 0, n)
                            digest.update(buffer, 0, n)
                        }
                        output.fd.sync()
                    }
                    if (bytes <= 0) throw IOException("Empty video in ZIP")
                    discovered[name] = Staged(name, dest, bytes, hex(digest.digest()))
                }
                zip.closeEntry()
            }
        }
        if (entries < 2 || discovered.isEmpty()) {
            throw IOException("No complete video backup content")
        }
        val bytes = manifestBytes ?: throw IOException("Missing manifest")
        // Only a small JSON manifest reaches memory, not any video bytes.
        val text = bytes.toString(Charsets.UTF_8)
        if (!bytes.contentEquals(text.toByteArray(Charsets.UTF_8))) {
            throw IOException("Invalid UTF-8 manifest")
        }
        val manifest = JSONObject(text)
        if (manifest.getInt("schemaVersion") != 1 ||
            manifest.getString("type") != "chappy-private-video-backup" ||
            manifest.getString("ownerId") != state.owner ||
            manifest.getInt("fileCount") != discovered.size) {
            throw IOException("Unsupported backup or wrong mini-app owner")
        }
        val files = manifest.getJSONArray("files")
        if (files.length() != discovered.size) throw IOException("Wrong file count")
        val checkedNames = mutableSetOf<String>()
        for (i in 0 until files.length()) {
            val item = files.getJSONObject(i)
            val name = item.getString("name")
            val staged = discovered[name] ?: throw IOException("Unknown video in manifest")
            if (!checkedNames.add(name) ||
                item.getLong("sizeBytes") != staged.size ||
                item.getString("sha256") != staged.hash) {
                throw IOException("Video content SHA-256 or size mismatch")
            }
        }
        val newFiles = mutableListOf<Staged>()
        var skipped = 0
        for (video in discovered.values) {
            val existing = File(state.target, video.name)
            if (existing.canonicalFile.parentFile != state.target ||
                existing.canonicalFile != existing.absoluteFile) {
                throw IOException("Unsafe destination path")
            }
            if (existing.exists()) {
                if (!existing.isFile || existing.length() != video.size ||
                    hashFile(existing, video.size) != video.hash) {
                    throw IOException("A different recording already exists with the same name")
                }
                skipped++
            } else {
                newFiles.add(video)
            }
        }
        return Preview(stage, newFiles, skipped, discovered.size, uncompressed)
    }

    private fun commitNewFiles(state: Pending, preview: Preview): Int {
        val written = mutableListOf<File>()
        try {
            for (video in preview.newFiles) {
                val destination = File(state.target, video.name)
                if (destination.exists() ||
                    destination.canonicalFile.parentFile != state.target ||
                    destination.canonicalFile != destination.absoluteFile ||
                    video.file.length() != video.size ||
                    hashFile(video.file, video.size) != video.hash) {
                    throw IOException("Video changed before restore; nothing was overwritten")
                }
                if (!video.file.renameTo(destination)) {
                    throw IOException("Could not commit restored video")
                }
                written.add(destination)
            }
            return written.size
        } catch (error: Exception) {
            // Roll back only files created in this attempt; never delete an old
            // video, including any previously identical/skipped file.
            for (file in written) file.delete()
            throw error
        }
    }

    private fun hashFile(file: File, maxBytes: Long): String {
        val hash = MessageDigest.getInstance("SHA-256")
        var count = 0L
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                count += n
                if (count > maxBytes) throw IOException("Unexpected video size")
                hash.update(buffer, 0, n)
            }
        }
        if (count != maxBytes) throw IOException("Video size changed")
        return hex(hash.digest())
    }

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun cleanup(state: Pending) {
        state.staging?.deleteRecursively()
        state.staging = null
    }

    private fun finish(
        state: Pending, code: String? = null, error: String? = null,
        response: Map<String, Any>? = null,
    ) {
        if (pending !== state) return
        pending = null
        running = false
        cleanup(state)
        state.unlockRecorder()
        if (!closed) {
            if (code != null) state.callback.error(code, error, null)
            else state.callback.success(response ?: mapOf("status" to "cancelled"))
        }
    }

    fun onDestroy() {
        closed = true
        pending?.let { state ->
            cleanup(state)
            state.unlockRecorder()
        }
        pending = null
    }
}
