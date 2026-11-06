package dev.chappy.chappy_player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.MessageDigest

/**
 * Scoped Android Storage Access Framework document picker.
 * Explicit user choice for each file; no broad storage permission or paths
 * exposed to a mini-app. The initial transport is bounded UTF-8 text only.
 */
class NativeMiniAppDocuments(private val activity: Activity) {
    companion object {
        const val PICK_REQUEST = 0x64C7
        const val SAVE_REQUEST = 0x64C8
        const val MAX_TEXT_BYTES = 64 * 1024
    }

    private enum class Mode { PICK, SAVE }
    private data class Pending(
        val mode: Mode,
        val callback: MethodChannel.Result,
        val payload: ByteArray? = null,
    )
    private var pending: Pending? = null
    private var copying = false
    private var closed = false

    fun pickText(callback: MethodChannel.Result) {
        if (!ready(callback)) return
        pending = Pending(Mode.PICK, callback)
        try {
            val request = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                    "text/plain", "text/csv", "text/markdown",
                    "application/json", "application/octet-stream"))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(request, PICK_REQUEST)
        } catch (error: Exception) {
            pending = null
            callback.error("DOCUMENT_PICKER_FAILED", error.message, null)
        }
    }

    fun saveText(name: String, text: String, callback: MethodChannel.Result) {
        if (!ready(callback)) return
        val content = text.toByteArray(Charsets.UTF_8)
        if (!validName(name) || content.size > MAX_TEXT_BYTES) {
            callback.error("DOCUMENT_INVALID", "Unsafe name or text exceeds 64KiB", null)
            return
        }
        pending = Pending(Mode.SAVE, callback, content)
        val mime = when {
            name.endsWith(".json", true) -> "application/json"
            name.endsWith(".csv", true) -> "text/csv"
            name.endsWith(".md", true) -> "text/markdown"
            else -> "text/plain"
        }
        try {
            val request = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_TITLE, name)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(request, SAVE_REQUEST)
        } catch (error: Exception) {
            pending = null
            callback.error("DOCUMENT_SAVER_FAILED", error.message, null)
        }
    }

    private fun ready(callback: MethodChannel.Result): Boolean {
        if (closed || pending != null || copying) {
            callback.error("DOCUMENT_BUSY", "A document picker is already active", null)
            return false
        }
        return true
    }

    private fun validName(name: String): Boolean {
        if (name.isBlank() || name.length > 100 ||
            name.any { it == '/' || it == '\\' || it.code < 32 }) {
            return false
        }
        return listOf(".txt", ".json", ".csv", ".md")
            .any { name.endsWith(it, ignoreCase = true) }
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST && requestCode != SAVE_REQUEST) return false
        val state = pending ?: return true
        if (copying || (requestCode == PICK_REQUEST && state.mode != Mode.PICK) ||
            (requestCode == SAVE_REQUEST && state.mode != Mode.SAVE)) return true

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            pending = null
            state.callback.success(mapOf("status" to "cancelled"))
            return true
        }
        copying = true
        Thread {
            try {
                val result = when (state.mode) {
                    Mode.PICK -> readSelectedText(uri)
                    Mode.SAVE -> writeSelectedText(uri, state.payload
                        ?: throw IOException("No source text"))
                }
                activity.runOnUiThread {
                    pending = null
                    copying = false
                    if (!closed) state.callback.success(result)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    pending = null
                    copying = false
                    if (!closed) state.callback.error(
                        "DOCUMENT_IO_FAILED",
                        "Selected document could not be verified: " + error.message, null)
                }
            }
        }.start()
        return true
    }

    private fun readSelectedText(uri: Uri): Map<String, Any> {
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Selected file cannot be opened")
        val bytes = ByteArrayOutputStream()
        input.use { source ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = source.read(buffer)
                if (count < 0) break
                if (bytes.size() + count > MAX_TEXT_BYTES) {
                    throw IOException("Selected text exceeds the 64KiB safety limit")
                }
                bytes.write(buffer, 0, count)
            }
        }
        val raw = bytes.toByteArray()
        val text = raw.toString(Charsets.UTF_8)
        if (!raw.contentEquals(text.toByteArray(Charsets.UTF_8))) {
            throw IOException("File is not valid UTF-8 text")
        }
        val filename = try {
            activity.contentResolver.query(uri,
                arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
        return mapOf(
            "status" to "selected",
            "fileName" to (filename?.takeIf { validName(it) } ?: "document.txt"),
            "text" to text,
            "sizeBytes" to raw.size,
        )
    }

    private fun writeSelectedText(uri: Uri, original: ByteArray): Map<String, Any> {
        if (original.size > MAX_TEXT_BYTES) {
            throw IOException("Text exceeds safety limit")
        }
        val output = activity.contentResolver.openOutputStream(uri, "wt")
            ?: throw IOException("Selected destination cannot be opened")
        output.use { stream ->
            stream.write(original)
            stream.flush()
        }
        // Some document providers accept writes but save empty or partial files.
        // Hash what was actually written before reporting success.
        val readback = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Document provider could not verify saved bytes")
        val digest = MessageDigest.getInstance("SHA-256")
        var count = 0
        readback.use { stream ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                count += read
                if (count > original.size) {
                    throw IOException("Saved document is unexpectedly large")
                }
                digest.update(buffer, 0, read)
            }
        }
        val expected = MessageDigest.getInstance("SHA-256").digest(original)
        if (count != original.size || !digest.digest().contentEquals(expected)) {
            throw IOException("Saved document differs from the original")
        }
        return mapOf("status" to "saved", "sizeBytes" to count)
    }

    fun onDestroy() {
        closed = true
        pending = null
    }
}
