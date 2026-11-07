package dev.chappy.chappy_player

import android.app.Activity
import android.Manifest
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.content.Intent
import android.content.ClipData
import android.provider.Settings
import android.provider.OpenableColumns
import android.os.Bundle
import android.view.KeyEvent
import androidx.core.content.FileProvider
import android.net.Uri
import java.io.IOException
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Strict preflight for an update APK downloaded into the player's private cache.
 * Rejects changes of package name, signing key and non-incrementing versionCode.
 *
 * The Android package installer remains the final authority. A legitimate
 * signing-key rotation is deliberately not accepted by this first release:
 * fail closed instead of silently risking user data.
 */
class MainActivity : FlutterActivity() {
    private val updateChannel = "dev.chappy.player/update"
    private val backupChannel = "dev.chappy.player/backup_export"
    private val externalChannelName = "dev.chappy.player/external_chappy"
    private val mediaChannelName = "dev.chappy.player/media_permissions"
    private val networkLabChannelName = "dev.chappy.player/network_lab"
    private val mediaPermissionRequestCode = 0x44FA
    private val nativeMic = NativeMicCapture()
    private val nativeVideo = NativeVideoRecorder(this)
    private val miniDevices = NativeMiniAppDevices(this)
    private val networkDiscovery = NativeNetworkDiscovery(this)
    private val pcIdentity = NativePcIdentity()
    private val trafficCounters = NativeTrafficCounters()
    private val videoExporter = NativeVideoExport(this)
    private val zipBackup = NativeVideoZipBackup(this)
    private val zipRestore = NativeVideoZipRestore(this)
    private val miniDocuments = NativeMiniAppDocuments(this)
    private val miniAssets = NativeMiniAppAssets(this)
    @Volatile private var micActivityVisible = false
    private var mediaPermissionCallback: MethodChannel.Result? = null
    private var mediaRequestedPermissions: List<String> = emptyList()
    private var incomingChannel: MethodChannel? = null
    private var mediaControlChannel: MethodChannel? = null
    private var pendingExternalUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nativeVideo.onCreate()
        captureExternalIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        micActivityVisible = true
        nativeVideo.onResume()
        miniDevices.onResume()
        networkDiscovery.onResume()
    }

    override fun onPause() {
        micActivityVisible = false
        miniDevices.onPause()
        networkDiscovery.onPause()
        nativeMic.stop()
        nativeVideo.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        nativeMic.stop()
        miniDevices.onDestroy()
        networkDiscovery.onDestroy()
        videoExporter.onDestroy()
        zipBackup.onDestroy()
        zipRestore.onDestroy()
        miniDocuments.onDestroy()
        miniAssets.onDestroy()
        nativeVideo.onDestroy()
        super.onDestroy()
    }

    // Hardware volume shortcuts are enabled ONLY while the foreground user has
    // explicitly entered the recorder's dark mode. Android's privacy indicators
    // remain under OS control. Repeated and key-up events do not retrigger.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (micActivityVisible && nativeVideo.isDark() &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
             event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                val shortcut = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP)
                    "start" else "stop"
                mediaControlChannel?.invokeMethod("videoVolumeShortcut", shortcut)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureExternalIntent(intent)
        incomingChannel?.invokeMethod("incomingChappyAvailable", null)
    }

    @Suppress("DEPRECATION")
    private fun captureExternalIntent(incoming: Intent?) {
        if (incoming == null) return
        val uri = when (incoming.action) {
            Intent.ACTION_VIEW -> incoming.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    incoming.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    incoming.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        }
        // content:// grants are scoped to a single user-selected document.
        if (uri?.scheme == "content") pendingExternalUri = uri
    }

    private fun copyExternalChappy(uri: Uri): Map<String, Any> {
        var filename: String? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
            null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) filename = cursor.getString(index)
            }
        }
        val name = filename ?: throw IOException(
            "ファイル名を取得できません。ホーム画面のファイル選択を使ってください")
        if (name.length > 240 || !name.endsWith(".chappy", ignoreCase = true)) {
            throw IOException(".chappyファイルのみ開けます")
        }
        val root = File(cacheDir, "chappy_external").apply { mkdirs() }
        val copy = File.createTempFile("incoming-", ".chappy", root)
        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IOException("ファイルを開けません")
            var received = 0L
            input.use { source ->
                copy.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        received += count
                        if (received > 12L * 1024 * 1024) {
                            throw IOException(".chappyが12MiBを超えています")
                        }
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (received < 22) throw IOException("空または不完全な.chappyです")
            return mapOf("path" to copy.absolutePath, "fileName" to name,
                "sizeBytes" to received)
        } catch (error: Exception) {
            copy.delete()
            throw error
        }
    }
    private val backupRequestCode = 0x64C4
    private data class PendingBackup(
        val source: File,
        val expectedSize: Long,
        val expectedSha256: String,
        val callback: MethodChannel.Result
    )
    private var pendingBackup: PendingBackup? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, externalChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "takePendingChappy") {
                    result.notImplemented()
                } else {
                    val uri = pendingExternalUri
                    pendingExternalUri = null
                    if (uri == null) {
                        result.success(null)
                    } else {
                        Thread {
                            try {
                                val receipt = copyExternalChappy(uri)
                                runOnUiThread { result.success(receipt) }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    result.error("EXTERNAL_CHAPPY_FAILED",
                                        "受信した.chappyの取り込みに失敗: ${error.message}", null)
                                }
                            }
                        }.start()
                    }
                }
            }
        }
        // Trusted Flutter host UI only; never exposed in the untrusted
        // .chappy JavaScript bridge. Every scan needs user confirmation in UI.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkLabChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (!micActivityVisible) {
                            result.error("NETLAB_NOT_FOREGROUND",
                                "Network discovery needs a visible player", null)
                        } else {
                            try {
                                val kind = call.argument<String>("serviceType") ?: ""
                                result.success(networkDiscovery.start(kind))
                            } catch (error: Exception) {
                                result.error("NETLAB_START_DENIED",
                                    error.message ?: "Discovery unavailable", null)
                            }
                        }
                    }
                    "snapshot" -> {
                        result.success(networkDiscovery.snapshot())
                    }
                    "pairingAllowed" -> {
                        result.success(micActivityVisible &&
                            networkDiscovery.pairingAllowed())
                    }
                    "pcIdentityStatus", "pcIdentityCreate", "pcIdentityRevoke" -> {
                        if (!micActivityVisible) {
                            result.error("NETLAB_NOT_FOREGROUND",
                                "Device identity needs the visible trusted host", null)
                        } else {
                            try {
                                when (call.method) {
                                    "pcIdentityStatus" ->
                                        result.success(pcIdentity.status())
                                    "pcIdentityCreate" ->
                                        result.success(pcIdentity.create())
                                    else -> result.success(pcIdentity.revoke())
                                }
                            } catch (error: Exception) {
                                result.error("NETLAB_IDENTITY_FAILED",
                                    "端末キー操作に失敗: ${error.javaClass.simpleName}", null)
                            }
                        }
                    }
                    "trafficSnapshot" -> {
                        if (!micActivityVisible) {
                            result.error("NETLAB_NOT_FOREGROUND",
                                "Device traffic read requires a visible player", null)
                        } else {
                            result.success(trafficCounters.snapshot())
                        }
                    }
                    "stop" -> {
                        result.success(networkDiscovery.stop())
                    }
                    else -> result.notImplemented()
                }
            }
        mediaControlChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
        mediaControlChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startNativeMic" -> {
                        if (!micActivityVisible || nativeVideo.isRecording() ||
                            ContextCompat.checkSelfPermission(this,
                                Manifest.permission.RECORD_AUDIO) !=
                                PackageManager.PERMISSION_GRANTED) {
                            result.error("NATIVE_MIC_NOT_ALLOWED",
                                "Foreground and Android microphone permission required", null)
                        } else {
                            try {
                                result.success(nativeMic.start())
                            } catch (error: SecurityException) {
                                result.error("NATIVE_MIC_PERMISSION", "Android denied audio input", null)
                            } catch (error: Exception) {
                                result.error("NATIVE_MIC_START_FAILED",
                                    error.message ?: "AudioRecord unavailable", null)
                            }
                        }
                    }
                    "readNativeMic" -> {
                        if (!micActivityVisible) {
                            nativeMic.stop()
                            result.success(mapOf("running" to false))
                        } else {
                            result.success(nativeMic.levels())
                        }
                    }
                    "stopNativeMic" -> {
                        nativeMic.stop()
                        result.success(true)
                    }
                    "startNativeVideo" -> {
                        val owner = call.argument<String>("owner") ?: ""
                        val lens = call.argument<String>("lens") ?: "back"
                        val quality = call.argument<String>("quality") ?: "720"
                        val sound = call.argument<Boolean>("audio") ?: false
                        val visibility = call.argument<String>("storage") ?: "private"
                        if (!micActivityVisible) {
                            result.error("VIDEO_NOT_ALLOWED", "App must be visible", null)
                        } else {
                            nativeMic.stop()
                            nativeVideo.start(owner, lens, quality, sound, visibility, result)
                        }
                    }
                    "stopNativeVideo" -> result.success(nativeVideo.stop())
                    "readNativeVideo" -> result.success(nativeVideo.status())
                    "listPrivateVideos" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_NOT_ALLOWED", "App must be visible", null)
                        } else {
                            try {
                                result.success(nativeVideo.listPrivate(
                                    call.argument<String>("owner") ?: ""))
                            } catch (error: Exception) {
                                result.error("VIDEO_LIST_FAILED", error.message, null)
                            }
                        }
                    }
                    "deletePrivateVideo" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_NOT_ALLOWED", "App must be visible", null)
                        } else {
                            try {
                                result.success(nativeVideo.deletePrivate(
                                    call.argument<String>("owner") ?: "",
                                    call.argument<String>("id") ?: ""))
                            } catch (error: Exception) {
                                result.error("VIDEO_DELETE_FAILED", error.message, null)
                            }
                        }
                    }
                    "openPrivateVideo" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_NOT_ALLOWED", "App must be visible", null)
                        } else {
                            try {
                                result.success(nativeVideo.openPrivate(
                                    call.argument<String>("owner") ?: "",
                                    call.argument<String>("id") ?: ""))
                            } catch (error: Exception) {
                                result.error("VIDEO_OPEN_FAILED", error.message, null)
                            }
                        }
                    }
                    "setVideoDark" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_NOT_ALLOWED", "App must be visible", null)
                        } else {
                            result.success(nativeVideo.setDark(
                                call.argument<Boolean>("enabled") == true))
                        }
                    }
                    "readVideoStorage" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_NOT_ALLOWED", "App must be visible", null)
                        } else {
                            try {
                                result.success(nativeVideo.storageInfo(
                                    call.argument<String>("owner") ?: ""))
                            } catch (error: Exception) {
                                result.error("VIDEO_STORAGE_FAILED", error.message, null)
                            }
                        }
                    }
                    "setVideoBrightness" -> {
                        val brightness = call.argument<Number>("brightness")?.toFloat()
                        if (!micActivityVisible || brightness == null ||
                            brightness !in 0.01f..1.0f) {
                            result.error("VIDEO_BRIGHTNESS_NOT_ALLOWED",
                                "Foreground dark recording gesture required", null)
                        } else {
                            result.success(nativeVideo.setDarkBrightness(brightness))
                        }
                    }
                    "binaryAssetTransferStatus" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND",
                                "Transfer progress requires foreground app", null)
                        } else {
                            result.success(miniAssets.transferStatus(
                                call.argument<String>("owner") ?: ""))
                        }
                    }
                    "cancelBinaryAssetTransfer" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND",
                                "Transfer cancellation requires foreground app", null)
                        } else {
                            result.success(miniAssets.cancelTransfer(
                                call.argument<String>("owner") ?: ""))
                        }
                    }
                    "importBinaryAsset" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND", "File import needs visible app", null)
                        } else {
                            miniAssets.importAsset(call.argument<String>("owner") ?: "", result)
                        }
                    }
                    "listBinaryAssets" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND", "Asset list needs visible app", null)
                        } else {
                            try {
                                result.success(miniAssets.list(
                                    call.argument<String>("owner") ?: ""))
                            } catch (error: Exception) {
                                result.error("ASSET_LIST_FAILED", error.message, null)
                            }
                        }
                    }
                    "exportBinaryAsset" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND", "File export needs visible app", null)
                        } else {
                            miniAssets.exportAsset(
                                call.argument<String>("owner") ?: "",
                                call.argument<String>("id") ?: "", result)
                        }
                    }
                    "exportCompressedAssetZip" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND",
                                "ZIP export requires a visible mini-app", null)
                        } else {
                            miniAssets.exportZip(
                                call.argument<String>("owner") ?: "",
                                call.argument<String>("id") ?: "",
                                call.argument<Int>("level") ?: 6, result)
                        }
                    }
                    "deleteBinaryAsset" -> {
                        if (!micActivityVisible) {
                            result.error("ASSET_NOT_FOREGROUND", "Deletion needs visible app", null)
                        } else {
                            miniAssets.deleteAsset(
                                call.argument<String>("owner") ?: "",
                                call.argument<String>("id") ?: "", result)
                        }
                    }
                    "pickDocumentText" -> {
                        if (!micActivityVisible) {
                            result.error("DOCUMENT_NOT_FOREGROUND",
                                "Foreground file picker required", null)
                        } else {
                            miniDocuments.pickText(result)
                        }
                    }
                    "saveDocumentText" -> {
                        if (!micActivityVisible) {
                            result.error("DOCUMENT_NOT_FOREGROUND",
                                "Foreground file picker required", null)
                        } else {
                            val fileName = call.argument<String>("fileName") ?: ""
                            val contents = call.argument<String>("text") ?: ""
                            miniDocuments.saveText(fileName, contents, result)
                        }
                    }
                    "availableMotionSensors" -> {
                        if (!micActivityVisible) {
                            result.error("MOTION_NOT_FOREGROUND",
                                "Sensor availability requires visible app", null)
                        } else {
                            result.success(miniDevices.availableSensors())
                        }
                    }
                    "hasHapticMotor" -> {
                        if (!micActivityVisible) {
                            result.error("HAPTICS_NOT_FOREGROUND",
                                "Vibration availability requires visible app", null)
                        } else {
                            result.success(miniDevices.hasHapticMotor())
                        }
                    }
                    "sampleMotion" -> {
                        if (!micActivityVisible) {
                            result.error("MOTION_NOT_FOREGROUND",
                                "Motion sample requires a visible app", null)
                        } else {
                            miniDevices.sample(call.argument<String>("type") ?: "", result)
                        }
                    }
                    "playHaptic" -> {
                        if (!micActivityVisible) {
                            result.error("HAPTICS_NOT_FOREGROUND",
                                "Haptic feedback requires a visible app", null)
                        } else {
                            result.success(miniDevices.haptic(
                                call.argument<String>("effect") ?: ""))
                        }
                    }
                    "restorePrivateVideosZip" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_RESTORE_NOT_FOREGROUND",
                                "ZIP restore needs a visible app", null)
                        } else {
                            try {
                                val owner = call.argument<String>("owner") ?: ""
                                val target = nativeVideo.beginPrivateRestore(owner)
                                zipRestore.begin(owner, target, result) {
                                    nativeVideo.endPrivateRestore()
                                }
                            } catch (error: Exception) {
                                result.error("VIDEO_RESTORE_NOT_ALLOWED",
                                    error.message, null)
                            }
                        }
                    }
                    "backupPrivateVideosZip" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_BACKUP_NOT_FOREGROUND",
                                "Video backup needs a visible app", null)
                        } else {
                            try {
                                val owner = call.argument<String>("owner") ?: ""
                                val sources = nativeVideo.privateBackupSources(owner)
                                zipBackup.begin(owner, sources, result)
                            } catch (error: Exception) {
                                result.error("VIDEO_BACKUP_NOT_ALLOWED",
                                    error.message, null)
                            }
                        }
                    }
                    "exportPrivateVideo" -> {
                        if (!micActivityVisible) {
                            result.error("VIDEO_EXPORT_NOT_FOREGROUND",
                                "Export needs a visible app", null)
                        } else {
                            try {
                                val source = nativeVideo.privateExportSource(
                                    call.argument<String>("owner") ?: "",
                                    call.argument<String>("id") ?: "")
                                videoExporter.begin(source, result)
                            } catch (error: Exception) {
                                result.error("VIDEO_EXPORT_NOT_ALLOWED",
                                    error.message, null)
                            }
                        }
                    }
                    "requestMediaPermissions" -> {
                        val names = call.argument<List<String>>("types")
                        if (names.isNullOrEmpty() || names.size != names.toSet().size ||
                            names.any { it != "camera" && it != "microphone" }) {
                            result.error("MEDIA_TYPES_UNSUPPORTED",
                                "Camera/microphone are the only supported media resources", null)
                        } else if (mediaPermissionCallback != null) {
                            result.error("MEDIA_PERMISSION_BUSY",
                                "A media permission prompt is already open", null)
                        } else {
                            val requested = names.map {
                                if (it == "camera") Manifest.permission.CAMERA
                                else Manifest.permission.RECORD_AUDIO
                            }
                            if (requested.all {
                                    ContextCompat.checkSelfPermission(this, it) ==
                                        PackageManager.PERMISSION_GRANTED
                                }) {
                                result.success(true)
                            } else {
                                mediaRequestedPermissions = requested
                                mediaPermissionCallback = result
                                ActivityCompat.requestPermissions(this,
                                    requested.toTypedArray(), mediaPermissionRequestCode)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchVerifiedInstaller" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "更新APKのパスがありません", null)
                        } else {
                            try {
                                result.success(launchVerifiedInstaller(path))
                            } catch (error: Exception) {
                                result.error("INSTALLER_LAUNCH_FAILED",
                                    "Androidのインストール画面を開けません: ${error.message}", null)
                            }
                        }
                    }
                    "checkApkCompatibility" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APKのファイルパスがありません", null)
                        } else {
                            try {
                                result.success(checkApkCompatibility(path))
                            } catch (error: Exception) {
                                result.error("PREFLIGHT_FAILED",
                                    "APKの互換性を確認できません: ${error.message}", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "exportVerifiedBackup") {
                    result.notImplemented()
                } else if (pendingBackup != null) {
                    result.error("EXPORT_BUSY", "バックアップ保存処理が実行中です", null)
                } else {
                    try {
                        val path = call.argument<String>("path")
                            ?: throw IllegalArgumentException("保存元が指定されていません")
                        val name = call.argument<String>("fileName")
                            ?: throw IllegalArgumentException("保存ファイル名がありません")
                        val size = call.argument<Number>("sizeBytes")?.toLong()
                            ?: throw IllegalArgumentException("保存サイズがありません")
                        val hash = call.argument<String>("sha256")
                            ?: throw IllegalArgumentException("SHA-256がありません")
                        if (!Regex("^chappy-data-\\d{4}-\\d{2}-\\d{2}\\.chappybackup$").matches(name) ||
                            !Regex("^[a-f0-9]{64}$").matches(hash)) {
                            throw IllegalArgumentException("バックアップの名前または検証値が不正です")
                        }
                        val root = File(cacheDir, "chappy_backup_export").canonicalFile
                        val source = File(path).canonicalFile
                        if (!source.path.startsWith(root.path + File.separator) ||
                            !source.isFile || size <= 0 || size > 12L * 1024 * 1024 ||
                            source.length() != size) {
                            throw IllegalArgumentException("保存元のファイルとサイズが一致しません")
                        }
                        pendingBackup = PendingBackup(source, size, hash, result)
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, backupRequestCode)
                    } catch (error: Exception) {
                        pendingBackup = null
                        result.error("BACKUP_SETUP_FAILED",
                            "保存先の選択を開始できません: ${error.message}", null)
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != mediaPermissionRequestCode) return
        val callback = mediaPermissionCallback ?: return
        val requested = mediaRequestedPermissions
        mediaPermissionCallback = null
        mediaRequestedPermissions = emptyList()
        callback.success(requested.isNotEmpty() && requested.all {
            ContextCompat.checkSelfPermission(this, it) ==
                PackageManager.PERMISSION_GRANTED
        })
    }

    @Deprecated("Deprecated in Android SDK, used for document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (videoExporter.onResult(requestCode, resultCode, data)) return
        if (zipBackup.onResult(requestCode, resultCode, data)) return
        if (zipRestore.onResult(requestCode, resultCode, data)) return
        if (miniDocuments.onResult(requestCode, resultCode, data)) return
        if (miniAssets.onResult(requestCode, resultCode, data)) return
        if (requestCode != backupRequestCode) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingBackup ?: return
        pendingBackup = null
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            pending.callback.success(mapOf("status" to "cancelled"))
            return
        }
        // Content providers may be slow; never copy and hash on the UI thread.
        Thread {
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                var copied = 0L
                val output = contentResolver.openOutputStream(destination, "wt")
                    ?: throw IOException("保存先へ書き込めません")
                output.use { stream ->
                    pending.source.inputStream().use { source ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val length = source.read(buffer)
                            if (length < 0) break
                            stream.write(buffer, 0, length)
                            digest.update(buffer, 0, length)
                            copied += length
                            if (copied > pending.expectedSize) {
                                throw IOException("保存サイズが上限を超えました")
                            }
                        }
                    }
                    stream.flush()
                }
                if (copied != pending.expectedSize ||
                    digest.digest().toHex() != pending.expectedSha256) {
                    throw IOException("保存元データの照合に失敗しました")
                }

                // Verify what Android actually stored, not merely the bytes
                // handed to the ContentResolver output stream.
                val checked = MessageDigest.getInstance("SHA-256")
                var readBytes = 0L
                val input = contentResolver.openInputStream(destination)
                    ?: throw IOException("保存したファイルを読み戻せません")
                input.use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val length = stream.read(buffer)
                        if (length < 0) break
                        checked.update(buffer, 0, length)
                        readBytes += length
                        if (readBytes > pending.expectedSize) {
                            throw IOException("読み戻したファイルが想定より大きいです")
                        }
                    }
                }
                if (readBytes != pending.expectedSize ||
                    checked.digest().toHex() != pending.expectedSha256) {
                    throw IOException("保存先のサイズまたはSHA-256が一致しません（0KB対策）")
                }
                runOnUiThread {
                    pending.callback.success(mapOf(
                        "status" to "saved",
                        "sizeBytes" to readBytes.toInt(),
                        "sha256" to pending.expectedSha256
                    ))
                }
            } catch (error: Exception) {
                // Never report success if the document provider left a 0-byte
                // or partial file. We deliberately do not delete the URI:
                // providers can have unusual overwrite/permission behavior.
                runOnUiThread {
                    pending.callback.error("BACKUP_UNVERIFIED",
                        "外部バックアップを検証できませんでした: ${error.message}。" +
                            "0KBなどの不完全なファイルが残っていれば削除してください。", null)
                }
            }
        }.start()
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { byte -> "%02x".format(byte) }

    /**
     * Open Android's own installer with a one-time content URI grant.
     * This is invoked only after the user taps the update button, after the
     * HTTPS download's SHA-256 has been verified by Dart.
     *
     * A successful return means the installer was OPENED, not that Android
     * has installed the app. This code never uninstalls an existing package.
     */
    private fun launchVerifiedInstaller(path: String): Map<String, String> {
        val candidate = File(path).canonicalFile
        val updateCache = File(cacheDir, "chappy_updates").canonicalFile
        if (!candidate.path.startsWith(updateCache.path + File.separator) ||
            !candidate.isFile || !candidate.name.endsWith(".apk")) {
            return mapOf("status" to "blocked", "code" to "INVALID_PATH")
        }
        if (candidate.length() < 1024 || candidate.length() > 180L * 1024 * 1024) {
            return mapOf("status" to "blocked", "code" to "INVALID_SIZE")
        }
        val verdict = checkApkCompatibility(path)
        if (verdict["compatible"] != true) {
            return mapOf(
                "status" to "blocked",
                "code" to (verdict["code"]?.toString() ?: "APK_UNREADABLE")
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(settingsIntent)
            return mapOf("status" to "permission_required")
        }
        val contentUri = FileProvider.getUriForFile(
            this, "$packageName.chappyupdates", candidate
        )
        val installer = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(contentResolver, "Chappy Player update", contentUri)
        }
        startActivity(installer)
        return mapOf("status" to "installer_opened")
    }

    private fun checkApkCompatibility(path: String): Map<String, Any> {
        val candidate = File(path).canonicalFile
        val privateCache = cacheDir.canonicalFile
        if (!candidate.path.startsWith(privateCache.path + File.separator) ||
            !candidate.isFile) {
            return report(false, "INVALID_PATH", 0L, 0L)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

        @Suppress("DEPRECATION")
        val archive = packageManager.getPackageArchiveInfo(candidate.path, flags)
            ?: return report(false, "APK_UNREADABLE", 0L, 0L)
        @Suppress("DEPRECATION")
        val installed = packageManager.getPackageInfo(packageName, flags)
        val oldBuild = versionCode(installed)
        val newBuild = versionCode(archive)

        if (archive.packageName != packageName) {
            return report(false, "PACKAGE_ID_MISMATCH", oldBuild, newBuild)
        }
        if (newBuild <= oldBuild) {
            return report(false, "VERSION_NOT_NEWER", oldBuild, newBuild)
        }

        val oldSigners = currentSigners(installed)
        val newSigners = currentSigners(archive)
        if (oldSigners.isEmpty() || newSigners.isEmpty()) {
            return report(false, "SIGNATURE_UNREADABLE", oldBuild, newBuild)
        }
        if (oldSigners != newSigners) {
            return report(false, "SIGNATURE_MISMATCH", oldBuild, newBuild)
        }
        return report(true, "COMPATIBLE", oldBuild, newBuild)
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun currentSigners(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        if (signatures == null || signatures.isEmpty()) return emptySet()
        return signatures.map {
            MessageDigest.getInstance("SHA-256")
                .digest(it.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }.toSet()
    }

    private fun report(
        compatible: Boolean,
        code: String,
        installedBuild: Long,
        candidateBuild: Long
    ): Map<String, Any> = mapOf(
        "compatible" to compatible,
        "code" to code,
        "installedBuild" to installedBuild,
        "candidateBuild" to candidateBuild
    )
}
