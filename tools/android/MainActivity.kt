package dev.chappy.chappy_player

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
