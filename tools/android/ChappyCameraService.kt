package dev.chappy.chappy_player

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Explicit opt-in camera foreground service. Recording is owned by this
 * service's LifecycleRegistry, never by a Flutter Activity or a JS page.
 *
 * Starts ONLY after a visible Activity confirms every selected option and
 * Android CAMERA / optional RECORD_AUDIO / notification permissions.
 * No boot receiver, remote start, automatic restart, or covert capture.
 */
class ChappyCameraService : Service() {
    companion object {
        private const val CHANNEL = "chappy_user_recording"
        private const val NOTICE_ID = 4305
        const val ACTION_STOP = "dev.chappy.player.STOP_USER_RECORDING"
        private const val ACTION_START = "dev.chappy.player.START_USER_RECORDING"

        @Volatile private var instance: ChappyCameraService? = null
        @Volatile private var pending = false
        @Volatile private var lastStatus: Map<String, Any>? = null

        fun isActive(): Boolean = pending || instance != null

        fun clearFinishedStatus() {
            if (!isActive()) lastStatus = null
        }

        fun readStatus(): Map<String, Any> {
            val service = instance
            val report = service?.recorder?.status() ?: lastStatus
            return (report ?: mapOf("state" to (if (pending) "starting" else "idle"))) +
                mapOf("backgroundSupported" to true,
                    "background" to (pending || service != null))
        }

        /**
         * Must be called synchronously from visible Activity (while-in-use
         * camera permission on Android 14+). The service itself promotes
         * immediately, before CameraX opens.
         */
        fun beginVisible(activity: MainActivity, owner: String, lens: String,
                         quality: String, audio: Boolean, storage: String,
                         motionMode: String, idleSeconds: Int,
                         sensitivity: Int): Map<String, Any> {
            if (Build.VERSION.SDK_INT < 30) {
                throw IllegalStateException("SCREEN_OFF_REQUIRES_ANDROID_11")
            }
            if (isActive()) throw IllegalStateException("SCREEN_OFF_VIDEO_BUSY")
            if (lens !in listOf("front", "back") || quality !in listOf("720", "1080") ||
                storage !in listOf("private", "gallery") ||
                motionMode !in listOf("normal", "pause", "stop") ||
                idleSeconds !in 10..300 || sensitivity !in 0..100 ||
                !Regex("^[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+$").matches(owner)) {
                throw IllegalArgumentException("INVALID_SCREEN_OFF_VIDEO_OPTIONS")
            }
            for (permission in listOfNotNull(
                Manifest.permission.CAMERA,
                if (audio) Manifest.permission.RECORD_AUDIO else null,
                if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null
            )) {
                if (ContextCompat.checkSelfPermission(activity, permission) !=
                    PackageManager.PERMISSION_GRANTED) {
                    throw SecurityException("Screen-off permission unavailable: $permission")
                }
            }
            val intent = Intent(activity, ChappyCameraService::class.java)
                .setAction(ACTION_START)
                .putExtra("owner", owner)
                .putExtra("lens", lens)
                .putExtra("quality", quality)
                .putExtra("audio", audio)
                .putExtra("storage", storage)
                .putExtra("motionMode", motionMode)
                .putExtra("idleSeconds", idleSeconds)
                .putExtra("sensitivity", sensitivity)
            lastStatus = null
            pending = true
            try {
                ContextCompat.startForegroundService(activity, intent)
            } catch (failure: Exception) {
                pending = false
                lastStatus = mapOf("state" to "idle",
                    "error" to "SCREEN_OFF_SERVICE_START_FAILED")
                throw failure
            }
            return readStatus()
        }

        /** Called only from the owner's visible UI or OS notification action. */
        fun requestStop(): Map<String, Any> {
            val service = instance
            if (service != null) service.stopRecording()
            else if (pending) {
                // Ordered explicit stop request, queued after the start intent.
                // The process stays under Android's service-start rules.
                lastStatus = mapOf("state" to "stopping")
            }
            return readStatus()
        }
        fun stopFromNotification() { instance?.stopRecording() }
    }

    private var recorder: NativeVideoRecorder? = null
    private var finished = false
    private var started = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL,
                "Chappy Recorder 録画中", NotificationManager.IMPORTANCE_LOW)
            channel.description = "画面OFF録画中の明示通知と停止操作"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_START || started) {
            // Never allow Android to restore a camera capture automatically.
            if (!started) stopSelf()
            return START_NOT_STICKY
        }
        started = true
        pending = false
        val owner = intent.getStringExtra("owner") ?: ""
        val lens = intent.getStringExtra("lens") ?: "back"
        val quality = intent.getStringExtra("quality") ?: "720"
        val audio = intent.getBooleanExtra("audio", false)
        val storage = intent.getStringExtra("storage") ?: "private"
        val motionMode = intent.getStringExtra("motionMode") ?: "normal"
        val idleSeconds = intent.getIntExtra("idleSeconds", 60)
        val sensitivity = intent.getIntExtra("sensitivity", 40)
        try {
            for (permission in listOfNotNull(
                Manifest.permission.CAMERA,
                if (audio) Manifest.permission.RECORD_AUDIO else null,
                if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null
            )) {
                if (ContextCompat.checkSelfPermission(this, permission) !=
                    PackageManager.PERMISSION_GRANTED) {
                    throw SecurityException("SCREEN_OFF_PERMISSION_DENIED")
                }
            }
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                (if (audio) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTICE_ID, ongoingNotification(), type)
            } else {
                startForeground(NOTICE_ID, ongoingNotification())
            }
            // User has opted in and the system's recording notification is live.
            val video = NativeVideoRecorder(this, onFinalized = { finishRecording() })
            recorder = video
            video.onCreate()
            video.onResume()
            video.start(owner, lens, quality, audio, storage, object : MethodChannel.Result {
                override fun success(result: Any?) { /* status() observes CameraX Start */ }
                override fun error(code: String, message: String?, details: Any?) {
                    failAndStop(code)
                }
                override fun notImplemented() { failAndStop("SCREEN_OFF_VIDEO_UNAVAILABLE") }
            }, motionMode, idleSeconds, sensitivity)
        } catch (failure: Exception) {
            failAndStop("SCREEN_OFF_" + failure.javaClass.simpleName)
        }
        return START_NOT_STICKY
    }

    private fun ongoingNotification(): Notification {
        val stopIntent = Intent(this, ChappyRecordingStopReceiver::class.java)
            .setAction(ACTION_STOP)
        val stopAction = PendingIntent.getBroadcast(
            this, 4305, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
                      else Notification.Builder(this)
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("Chappy Recorder — 録画中")
            .setContentText("画面OFFでもカメラを使用中。停止するにはここをタップ")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(
                android.R.drawable.ic_media_pause, "録画を停止", stopAction).build())
            .build()
    }

    private fun stopRecording() {
        val video = recorder ?: run { stopSelf(); return }
        val state = video.status()["state"]
        if (state == "idle") {
            finishRecording()
        } else if (state != "stopping") {
            video.stop()
            if (video.status()["state"] == "idle") finishRecording()
        }
    }

    private fun finishRecording() {
        if (finished) return
        finished = true
        lastStatus = (recorder?.status() ?: mapOf("state" to "idle")) +
            mapOf("backgroundSupported" to true, "background" to false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun failAndStop(reason: String) {
        if (finished) return
        finished = true
        lastStatus = mapOf("state" to "idle", "error" to reason,
            "backgroundSupported" to true, "background" to false)
        recorder?.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (!finished) {
            lastStatus = mapOf("state" to "idle", "error" to "SCREEN_OFF_SERVICE_INTERRUPTED",
                "backgroundSupported" to true, "background" to false)
        }
        recorder?.onDestroy()
        recorder = null
        if (instance === this) instance = null
        pending = false
        super.onDestroy()
    }
}

/** Explicit OS notification action. Never starts a new capture. */
class ChappyRecordingStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == ChappyCameraService.ACTION_STOP) {
            ChappyCameraService.stopFromNotification()
        }
    }
}
