package dev.chappy.chappy_player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest

/**
 * Never provides the private video path to HTML.
 * A foreground user chooses the target with Android ACTION_CREATE_DOCUMENT.
 * The source is already owner-validated by NativeVideoRecorder.
 */
class NativeVideoExport(private val activity: Activity) {
    companion object { const val REQUEST_CODE = 0x64C6 }
    private data class Pending(val file: File, val callback: MethodChannel.Result)
    private var pending: Pending? = null
    private var copying = false
    private var closed = false

    fun begin(file: File, callback: MethodChannel.Result) {
        if (closed || pending != null || copying) {
            callback.error("VIDEO_EXPORT_BUSY", "An export is already running", null)
            return
        }
        if (!file.isFile || file.length() <= 0 ||
            file.length() > 1024L * 1024 * 1024) {
            callback.error("VIDEO_EXPORT_INVALID", "Source video not available", null)
            return
        }
        pending = Pending(file, callback)
        try {
            val picker = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "video/mp4"
                putExtra(Intent.EXTRA_TITLE, file.name)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(picker, REQUEST_CODE)
        } catch (error: Exception) {
            pending = null
            callback.error("VIDEO_EXPORT_PICKER_FAILED", error.message, null)
        }
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val state = pending ?: return true
        if (copying) return true
        val dest: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || dest == null ||
            dest.scheme != "content") {
            pending = null
            state.callback.success(mapOf("status" to "cancelled"))
            return true
        }
        copying = true
        Thread {
            try {
                val expected = state.file.length()
                if (expected <= 0 || expected > 1024L * 1024 * 1024) {
                    throw IOException("Video size changed while exporting")
                }
                val originalHash = MessageDigest.getInstance("SHA-256")
                var written = 0L
                val stream = activity.contentResolver.openOutputStream(dest, "w")
                    ?: throw IOException("Selected destination is not writable")
                stream.use { output ->
                    state.file.inputStream().use { input ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            written += count
                            if (written > expected) {
                                throw IOException("Video size changed while exporting")
                            }
                            output.write(buffer, 0, count)
                            originalHash.update(buffer, 0, count)
                        }
                    }
                    output.flush()
                }
                if (written != expected) {
                    throw IOException("Video source was truncated")
                }
                // Do not claim success until readback agrees with the source.
                val readHash = MessageDigest.getInstance("SHA-256")
                var readBytes = 0L
                val stream = activity.contentResolver.openInputStream(dest)
                    ?: throw IOException("The selected destination cannot be verified")
                stream.use { input ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        readBytes += count
                        if (readBytes > written) {
                            throw IOException("Exported file is too large")
                        }
                        readHash.update(buffer, 0, count)
                    }
                }
                if (written != readBytes ||
                    !originalHash.digest().contentEquals(readHash.digest())) {
                    throw IOException("Exported video bytes failed verification")
                }
                activity.runOnUiThread {
                    pending = null
                    copying = false
                    if (!closed) state.callback.success(
                        mapOf("status" to "saved", "sizeBytes" to readBytes))
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    pending = null
                    copying = false
                    if (!closed) state.callback.error("VIDEO_EXPORT_FAILED",
                        "Export could not be verified: " + error.message, null)
                }
            }
        }.start()
        return true
    }

    fun onDestroy() {
        closed = true
        pending = null
    }
}
