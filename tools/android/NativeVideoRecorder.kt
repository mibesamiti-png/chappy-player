package dev.chappy.chappy_player

import android.app.Activity
import android.app.Dialog
import android.content.ContentValues
import android.content.pm.PackageManager
import android.Manifest
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import android.widget.MediaController
import android.widget.VideoView
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.os.StatFs
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Phase 1: user-consented, foreground-only CameraX video capture.
 *
 * No camera/microphone service is registered, and onPause stops recording.
 * By default videos remain in app-internal private storage (not MediaStore).
 * The only exposed file identifiers are app-scoped file names, never paths.
 * Public MediaStore output is explicitly opt-in for each recording.
 */
class NativeVideoRecorder(private val activity: Activity) : LifecycleOwner {
    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry
    private var state = "idle"
    private var owner: String? = null
    private var storage = "private"
    private var recording: Recording? = null
    private var provider: ProcessCameraProvider? = null
    private var pendingFile: File? = null
    private var completeFile: File? = null
    private var elapsedMs = 0L
    private var bytes = 0L
    private var lastFileName: String? = null
    private var lastError: String? = null
    private var token = 0
    private var dimmed = false
    private var originalBrightness: Float? = null
    private var originalKeepOn = false
    private val ownerPattern = Regex("^[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+$")

    fun onCreate() { registry.currentState = Lifecycle.State.CREATED }
    fun onResume() { registry.currentState = Lifecycle.State.RESUMED }
    fun onPause() {
        stop()
        setDark(false)
        registry.currentState = Lifecycle.State.CREATED
    }
    fun onDestroy() {
        stop()
        setDark(false)
        registry.currentState = Lifecycle.State.DESTROYED
    }

    private fun privateDirectory(appId: String): File {
        if (!ownerPattern.matches(appId) || appId.length > 100) {
            throw IllegalArgumentException("INVALID_VIDEO_OWNER")
        }
        val dir = File(activity.filesDir, "chappy_private_videos/$appId")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("VIDEO_DIRECTORY_UNAVAILABLE")
        }
        return dir
    }

    fun start(
        appId: String, lens: String, quality: String, audio: Boolean,
        visibility: String, result: MethodChannel.Result
    ) {
        if (registry.currentState != Lifecycle.State.RESUMED ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
                PackageManager.PERMISSION_GRANTED) {
            result.error("VIDEO_NOT_ALLOWED", "Foreground camera permission required", null)
            return
        }
        if (audio && ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) {
            result.error("VIDEO_AUDIO_NOT_ALLOWED", "Microphone permission required", null)
            return
        }
        if (state != "idle" || recording != null) {
            result.error("VIDEO_BUSY", "A recording is already running or finalizing", null)
            return
        }
        if (lens !in listOf("back", "front") ||
            quality !in listOf("720", "1080") ||
            visibility !in listOf("private", "gallery")) {
            result.error("VIDEO_SETTINGS", "Unsupported recording options", null)
            return
        }
        if (visibility == "gallery" && Build.VERSION.SDK_INT < 29) {
            result.error("VIDEO_GALLERY_REQUIRES_ANDROID_10",
                "Shared storage requires Android 10 or newer", null)
            return
        }
        try {
            privateDirectory(appId) // validates every owner, even shared output
            val name = "Chappy_" +
                SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date()) + ".mp4"
            val file = if (visibility == "private") File(privateDirectory(appId), name) else null
            val temp = if (file != null) File(file.parentFile, "$name.pending") else null
            if (temp != null && temp.exists()) throw IllegalStateException("VIDEO_FILENAME_EXISTS")
            token += 1
            val requestToken = token
            state = "initializing"
            owner = appId
            storage = visibility
            bytes = 0L
            elapsedMs = 0L
            lastError = null
            lastFileName = null
            pendingFile = temp
            completeFile = file
            val future = ProcessCameraProvider.getInstance(activity)
            future.addListener({
                if (requestToken != token || state != "initializing" ||
                    registry.currentState != Lifecycle.State.RESUMED) {
                    if (requestToken == token && state == "initializing") {
                        state = "idle"
                    }
                    temp?.delete()
                    result.error("VIDEO_CANCELLED", "Camera request was cancelled", null)
                    return@addListener
                }
                try {
                    val camera = future.get()
                    provider = camera
                    val desired = if (quality == "1080") Quality.FHD else Quality.HD
                    val recorder = Recorder.Builder()
                        .setQualitySelector(QualitySelector.from(
                            desired, FallbackStrategy.lowerQualityOrHigherThan(desired)))
                        .build()
                    val capture = VideoCapture.withOutput(recorder)
                    camera.unbindAll()
                    camera.bindToLifecycle(this,
                        if (lens == "front") CameraSelector.DEFAULT_FRONT_CAMERA
                        else CameraSelector.DEFAULT_BACK_CAMERA,
                        capture)
                    val prepared = if (visibility == "private") {
                        val destination = temp ?: throw IllegalStateException("VIDEO_PATH_MISSING")
                        capture.output.prepareRecording(activity,
                            FileOutputOptions.Builder(destination).setFileSizeLimit(1024L * 1024 * 1024).build())
                    } else {
                        val values = ContentValues().apply {
                            put(MediaStore.Video.Media.DISPLAY_NAME, name)
                            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                            if (Build.VERSION.SDK_INT >= 29) {
                                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/ChappyPlayer")
                                put(MediaStore.Video.Media.IS_PENDING, 1)
                            }
                        }
                        capture.output.prepareRecording(activity,
                            MediaStoreOutputOptions.Builder(activity.contentResolver,
                                MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
                                .setContentValues(values)
                                .setFileSizeLimit(1024L * 1024 * 1024).build())
                    }
                    val session = if (audio) prepared.withAudioEnabled() else prepared
                    recording = session.start(ContextCompat.getMainExecutor(activity)) { event ->
                        when (event) {
                            is VideoRecordEvent.Start -> {
                                if (state == "starting" || state == "initializing") {
                                    state = "recording"
                                }
                            }
                            is VideoRecordEvent.Status -> {
                                elapsedMs = event.recordingStats.recordedDurationNanos / 1000000L
                                bytes = event.recordingStats.numBytesRecorded
                            }
                            is VideoRecordEvent.Finalize -> finalizeRecording(event, requestToken)
                        }
                    }
                    state = "starting"
                    result.success(mapOf("state" to state, "storage" to storage,
                        "audio" to audio, "quality" to quality, "lens" to lens))
                } catch (error: Exception) {
                    temp?.delete()
                    recording?.close()
                    recording = null
                    provider?.unbindAll()
                    provider = null
                    state = "idle"
                    lastError = error.javaClass.simpleName
                    result.error("VIDEO_START_FAILED", "CameraX could not start: ${error.message}", null)
                }
            }, ContextCompat.getMainExecutor(activity))
        } catch (error: Exception) {
            pendingFile?.delete()
            pendingFile = null
            completeFile = null
            state = "idle"
            result.error("VIDEO_SETUP_FAILED", error.message ?: "Video setup failed", null)
        }
    }

    private fun finalizeRecording(event: VideoRecordEvent.Finalize, sessionToken: Int) {
        if (sessionToken != token) return
        // Keep the user-requested dark screen active until they explicitly exit.
        // The host shows green once finalization reaches idle.
        recording?.close()
        recording = null
        provider?.unbindAll()
        provider = null
        elapsedMs = event.recordingStats.recordedDurationNanos / 1000000L
        bytes = event.recordingStats.numBytesRecorded
        // The recorder may still produce a valid, finalized MP4 when it
        // reaches our explicit 1 GiB limit; preserve it rather than deleting
        // the user's long recording.
        val usableLimitReached =
            event.error == VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED
        if (event.hasError() && !usableLimitReached) {
            lastError = "CAMERAX_FINALIZE_${event.error}"
            pendingFile?.delete()
            if (storage == "gallery") {
                val output = event.outputResults.outputUri
                if (output != android.net.Uri.EMPTY) {
                    try { activity.contentResolver.delete(output, null, null) } catch (_: Exception) {}
                }
            }
            lastFileName = null
        } else if (storage == "private") {
            val source = pendingFile
            val target = completeFile
            if (source != null && target != null && source.isFile && source.length() > 0 &&
                source.renameTo(target)) {
                lastFileName = target.name
            } else {
                lastError = "VIDEO_SAVE_FAILED"
                source?.delete()
            }
        } else {
            val output = event.outputResults.outputUri
            try {
                if (Build.VERSION.SDK_INT >= 29 && output != android.net.Uri.EMPTY) {
                    activity.contentResolver.update(output,
                        ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
                }
                lastFileName = "ギャラリーに保存済み"
            } catch (_: Exception) {
                lastError = "VIDEO_GALLERY_FINALIZE_FAILED"
            }
        }
        pendingFile = null
        completeFile = null
        owner = null
        state = "idle"
    }

    fun stop(): Map<String, Any> {
        if (state == "initializing") {
            token += 1
            state = "idle"
            pendingFile?.delete()
            pendingFile = null
            completeFile = null
        } else if (state == "recording" || state == "starting") {
            state = "stopping"
            recording?.stop()
        }
        // Stopping via volume-down keeps the black overlay/brightness active.
        // onPause/onDestroy or the explicit restore gesture still clears it.
        return status()
    }

    fun status(): Map<String, Any> = mapOf(
        "state" to state, "storage" to storage, "elapsedMs" to elapsedMs,
        "bytes" to bytes, "fileName" to (lastFileName ?: ""),
        "error" to (lastError ?: "")
    )

    fun isRecording(): Boolean = state == "starting" || state == "recording"

    fun isDark(): Boolean = dimmed

    fun setDark(enabled: Boolean): Boolean {
        if (enabled && registry.currentState != Lifecycle.State.RESUMED) return false
        if (enabled == dimmed) return dimmed
        val window = activity.window
        val attrs = window.attributes
        if (enabled) {
            originalBrightness = attrs.screenBrightness
            originalKeepOn = (window.attributes.flags and
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
            attrs.screenBrightness = 0.01f
            window.attributes = attrs
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            attrs.screenBrightness = originalBrightness ?: -1.0f
            window.attributes = attrs
            if (!originalKeepOn) window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            originalBrightness = null
        }
        dimmed = enabled
        return dimmed
    }

    /** Storage used by private MP4 files. Does not expose filesystem paths. */
    fun storageInfo(appId: String): Map<String, Long> {
        val directory = privateDirectory(appId)
        val stats = StatFs(directory.absolutePath)
        return mapOf(
            "totalBytes" to stats.totalBytes,
            "availableBytes" to stats.availableBytes
        )
    }

    /** User-initiated swipe brightness while the visible app is in dark mode.
     * 1.0 means maximum brightness; 0.01 is the lowest supported in-app value.
     * This is per-window only; original brightness is restored when leaving.
     */
    fun setDarkBrightness(brightness: Float): Boolean {
        if (!dimmed || registry.currentState != Lifecycle.State.RESUMED ||
            brightness.isNaN() || brightness !in 0.01f..1.0f) {
            return false
        }
        val attrs = activity.window.attributes
        attrs.screenBrightness = brightness
        activity.window.attributes = attrs
        return true
    }

    fun listPrivate(appId: String): List<Map<String, Any>> =
        privateDirectory(appId).listFiles()
            ?.filter { it.isFile && Regex("^Chappy_[0-9_]+\\.mp4$").matches(it.name) }
            ?.sortedByDescending { it.lastModified() }
            ?.take(100)
            ?.map { mapOf("id" to it.name, "bytes" to it.length(),
                "createdMs" to it.lastModified()) }
            ?: emptyList()

    fun deletePrivate(appId: String, id: String): Boolean {
        if (state != "idle" || !Regex("^Chappy_[0-9_]+\\.mp4$").matches(id)) {
            throw IllegalArgumentException("VIDEO_DELETE_NOT_ALLOWED")
        }
        val root = privateDirectory(appId).canonicalFile
        val file = File(root, id).canonicalFile
        if (file.parentFile != root || !file.isFile || file.length() == 0L) {
            throw IllegalArgumentException("VIDEO_FILE_UNAVAILABLE")
        }
        if (!file.delete()) throw IllegalStateException("VIDEO_DELETE_FAILED")
        return true
    }

    /** Return only a verified file owned by the calling mini-app.
     * Exposed solely to the native system-document picker, never JavaScript.
     */
    fun privateExportSource(appId: String, id: String): File {
        if (state != "idle" || !Regex("^Chappy_[0-9_]+\\.mp4$").matches(id)) {
            throw IllegalArgumentException("VIDEO_EXPORT_NOT_ALLOWED")
        }
        val root = privateDirectory(appId).canonicalFile
        val file = File(root, id).canonicalFile
        if (file.parentFile != root || !file.isFile ||
            file.length() <= 0 || file.length() > 1024L * 1024 * 1024) {
            throw IllegalArgumentException("VIDEO_FILE_UNAVAILABLE")
        }
        return file
    }

    fun openPrivate(appId: String, id: String): Boolean {
        if (state != "idle" || !Regex("^Chappy_[0-9_]+\\.mp4$").matches(id)) {
            throw IllegalArgumentException("VIDEO_OPEN_NOT_ALLOWED")
        }
        val root = privateDirectory(appId).canonicalFile
        val file = File(root, id).canonicalFile
        if (file.parentFile != root || !file.isFile || file.length() == 0L) {
            throw IllegalArgumentException("VIDEO_FILE_UNAVAILABLE")
        }
        val player = VideoView(activity)
        val controls = MediaController(activity)
        player.setMediaController(controls)
        player.setVideoPath(file.absolutePath)
        val dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        dialog.setContentView(player)
        dialog.setOnDismissListener { player.stopPlayback() }
        player.setOnPreparedListener { player.start(); controls.show() }
        dialog.show()
        return true
    }
}
