package dev.chappy.chappy_player

import android.app.Activity
import android.content.Intent
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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

    @Deprecated("Deprecated in Android SDK, used for document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
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
