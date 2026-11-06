package dev.chappy.chappy_player

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.security.DigestOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import java.util.UUID
import org.json.JSONObject

/**
 * Binary file library for .chappy mini-apps. No payload bytes, content URIs
 * or private paths ever cross the JS bridge. Every import/export uses Android
 * Storage Access Framework and each app has a separate internal directory.
 */
class NativeMiniAppAssets(private val activity: Activity) {
    companion object {
        const val IMPORT_REQUEST = 0x64CB
        const val EXPORT_REQUEST = 0x64CC
        const val ZIP_REQUEST = 0x64CD
        private const val MAX_FILE_BYTES = 256L * 1024 * 1024
        private const val MAX_STORE_BYTES = 512L * 1024 * 1024
        private const val MAX_FILES = 32
        private val ownerPattern =
            Regex("^[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+$")
        private val idPattern = Regex("^[a-f0-9]{32}$")
    }
    private enum class Mode { IMPORT, EXPORT, EXPORT_ZIP }
    private data class Item(
        val id: String, val name: String, val mime: String, val size: Long,
        val sha: String, val createdMs: Long,
    ) {
        fun exposed() = mapOf(
            "id" to id, "name" to name, "mime" to mime, "sizeBytes" to size,
            "sha256" to sha, "createdMs" to createdMs,
        )
    }
    private data class Pending(
        val owner: String, val mode: Mode, val result: MethodChannel.Result,
        val item: Item? = null,
        val compressionLevel: Int = 6,
        @Volatile var cancelRequested: Boolean = false,
    )
    private var pending: Pending? = null
    private var copying = false
    private var closed = false

    // Immutable numeric/status snapshots exposed to the UI, not file contents.
    @Volatile private var transferPhase = "idle"
    @Volatile private var transferDoneBytes = 0L
    @Volatile private var transferTotalBytes = -1L

    fun transferStatus(owner: String): Map<String, Any> {
        val current = pending
        if (!ownerPattern.matches(owner) || current == null ||
            current.owner != owner || closed) {
            return mapOf("active" to false, "phase" to "idle")
        }
        return mapOf(
            "active" to true,
            "phase" to transferPhase,
            "bytesDone" to transferDoneBytes,
            "totalBytes" to transferTotalBytes,
            "cancelable" to (copying &&
                transferPhase in setOf("copying", "verifying") &&
                !current.cancelRequested),
            "cancelRequested" to current.cancelRequested,
        )
    }

    fun cancelTransfer(owner: String): Boolean {
        val current = pending ?: return false
        if (closed || !copying || current.owner != owner ||
            transferPhase !in setOf("copying", "verifying") ||
            !ownerPattern.matches(owner)) return false
        current.cancelRequested = true
        return true
    }

    private fun checkTransferActive(request: Pending) {
        if (closed || request.cancelRequested || Thread.currentThread().isInterrupted) {
            throw IOException("ASSET_TRANSFER_CANCELLED")
        }
    }

    private fun resetProgress() {
        transferPhase = "idle"
        transferDoneBytes = 0L
        transferTotalBytes = -1L
    }

    private fun declaredSize(uri: Uri): Long {
        return try {
            activity.contentResolver.query(
                uri, arrayOf(OpenableColumns.SIZE), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0)
                else -1L
            } ?: -1L
        } catch (_: Exception) { -1L }
    }

    private fun directory(owner: String): File {
        if (!ownerPattern.matches(owner) || owner.length > 120) {
            throw IOException("Invalid mini-app owner")
        }
        val parent = File(activity.filesDir, "chappy_private_assets").canonicalFile
        if (!parent.exists() && !parent.mkdirs()) throw IOException("No asset directory")
        val root = File(parent, owner).canonicalFile
        if (root.parentFile != parent || (!root.exists() && !root.mkdir())) {
            throw IOException("Invalid asset storage")
        }
        return root
    }

    private fun file(root: File, id: String, ext: String): File {
        if (!idPattern.matches(id) || ext !in setOf(".blob", ".json", ".part")) {
            throw IOException("Invalid asset handle")
        }
        val f = File(root, id + ext).canonicalFile
        if (f.parentFile != root) throw IOException("Asset escaped private storage")
        return f
    }

    private fun safeName(raw: String?): String {
        val cleaned = (raw ?: "").filter {
            it != '/' && it != '\\' && it.code >= 32 && it.code != 127 &&
                it != '\u202e' && it != '\u202d'
        }.trim().take(100)
        return cleaned.takeIf { it.isNotBlank() && it != "." && it != ".." }
            ?: "imported-file.bin"
    }

    private fun safeMime(raw: String?): String {
        val value = (raw ?: "").trim()
        return if (value.length in 3..100 &&
            Regex("^[a-zA-Z0-9!#$&^_.+-]+/[a-zA-Z0-9!#$&^_.+-]+$").matches(value)
        ) value else "application/octet-stream"
    }

    private fun load(root: File, id: String): Item {
        val metadata = file(root, id, ".json")
        val body = file(root, id, ".blob")
        if (!metadata.isFile || !body.isFile ||
            metadata.length() !in 1..4096) throw IOException("Asset unavailable")
        val json = JSONObject(metadata.readText(Charsets.UTF_8))
        val sha = json.getString("sha256")
        val item = Item(
            json.getString("id"), json.getString("name"),
            json.getString("mime"), json.getLong("sizeBytes"),
            sha, json.getLong("createdMs"),
        )
        if (item.id != id || !idPattern.matches(id) ||
            item.name != safeName(item.name) || item.mime != safeMime(item.mime) ||
            !Regex("^[a-f0-9]{64}$").matches(item.sha) ||
            item.size !in 1..MAX_FILE_BYTES || body.length() != item.size) {
            throw IOException("Asset metadata or size mismatch")
        }
        return item
    }

    private fun all(root: File): List<Item> {
        val records = root.listFiles()
            ?: throw IOException("Cannot list private assets")
        val ids = records.filter {
            it.isFile && Regex("^[a-f0-9]{32}\\.json$").matches(it.name)
        }.map { it.name.removeSuffix(".json") }
        if (ids.size > MAX_FILES) throw IOException("Private asset quota exceeded")
        return ids.map { load(root, it) }.sortedByDescending { it.createdMs }
    }

    /** Remove only old unfinished import temp files. Never touch completed
     * assets, and never run while a transfer owns this vault.
     */
    private fun cleanupStaleImports(root: File) {
        if (pending != null || copying) return
        val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
        root.listFiles()?.forEach { candidate ->
            if (candidate.isFile &&
                Regex("^[a-f0-9]{32}\\.part$").matches(candidate.name) &&
                candidate.lastModified() > 0L &&
                candidate.lastModified() < cutoff &&
                candidate.canonicalFile.parentFile == root) {
                candidate.delete()
            }
        }
    }

    fun list(owner: String): List<Map<String, Any>> {
        if (closed || pending != null || copying) {
            throw IOException("Asset import or export already in progress")
        }
        val root = directory(owner)
        cleanupStaleImports(root)
        return all(root).map { it.exposed() }
    }

    fun importAsset(owner: String, result: MethodChannel.Result) {
        if (!reserve(result)) return
        try {
            val root = directory(owner)
            cleanupStaleImports(root)
            val existing = all(root)
            if (existing.size >= MAX_FILES ||
                existing.sumOf { it.size } >= MAX_STORE_BYTES) {
                result.error("ASSET_QUOTA", "Private file storage is full", null)
                return
            }
            val request = Pending(owner, Mode.IMPORT, result)
            pending = request
            transferPhase = "picker"
            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(picker, IMPORT_REQUEST)
        } catch (error: Exception) {
            pending = null
            resetProgress()
            result.error("ASSET_IMPORT_FAILED", error.message, null)
        }
    }

    fun exportAsset(owner: String, id: String, result: MethodChannel.Result) {
        if (!reserve(result)) return
        try {
            val root = directory(owner)
            val record = load(root, id)
            val request = Pending(owner, Mode.EXPORT, result, record)
            pending = request
            transferPhase = "picker"
            val picker = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = record.mime
                putExtra(Intent.EXTRA_TITLE, record.name)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(picker, EXPORT_REQUEST)
        } catch (error: Exception) {
            pending = null
            resetProgress()
            result.error("ASSET_EXPORT_FAILED", error.message, null)
        }
    }

    /**
     * Explicit, lossless ZIP export of one vault item. Keep the source untouched;
     * report real saved ZIP bytes even when already-compressed input grows.
     */
    fun exportZip(
        owner: String, id: String, level: Int, result: MethodChannel.Result,
    ) {
        if (!reserve(result)) return
        if (level !in setOf(1, 6, 9)) {
            result.error("ASSET_COMPRESSION_LEVEL", "Choose 1, 6 or 9", null)
            return
        }
        try {
            val record = load(directory(owner), id)
            pending = Pending(owner, Mode.EXPORT_ZIP, result, record, level)
            transferPhase = "picker"
            val picker = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(Intent.EXTRA_TITLE, record.name + ".zip")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(picker, ZIP_REQUEST)
        } catch (error: Exception) {
            pending = null
            resetProgress()
            result.error("ASSET_ZIP_FAILED", error.message, null)
        }
    }

    fun deleteAsset(owner: String, id: String, result: MethodChannel.Result) {
        if (!reserve(result)) return
        try {
            val root = directory(owner)
            val record = load(root, id)
            val state = Pending(owner, Mode.EXPORT, result, record)
            pending = state
            transferPhase = "confirm-delete"
            AlertDialog.Builder(activity)
                .setTitle("ミニアプリ内のファイルを削除")
                .setMessage("「" + record.name + "」を削除しますか？" +
                    "この操作では端末の元ファイルや書き出したコピーは削除しません。")
                .setNegativeButton("キャンセル") { _, _ ->
                    if (pending === state) {
                        pending = null
                        resetProgress()
                        result.success(false)
                    }
                }
                .setPositiveButton("削除する") { _, _ ->
                    if (pending !== state) return@setPositiveButton
                    try {
                        val body = file(root, id, ".blob")
                        val meta = file(root, id, ".json")
                        // Only delete handles owned by this exact mini-app.
                        if (!body.isFile || !meta.isFile) {
                            throw IOException("Asset disappeared before deletion")
                        }
                        if (!body.delete() || !meta.delete()) {
                            throw IOException("Unable to delete private asset")
                        }
                        pending = null
                        resetProgress()
                        result.success(true)
                    } catch (error: Exception) {
                        pending = null
                        resetProgress()
                        result.error("ASSET_DELETE_FAILED", error.message, null)
                    }
                }.setCancelable(false).show()
        } catch (error: Exception) {
            pending = null
            resetProgress()
            result.error("ASSET_DELETE_FAILED", error.message, null)
        }
    }

    private fun reserve(callback: MethodChannel.Result): Boolean {
        if (closed || pending != null || copying) {
            callback.error("ASSET_BUSY", "Another file operation is active", null)
            return false
        }
        return true
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != IMPORT_REQUEST && requestCode != EXPORT_REQUEST &&
            requestCode != ZIP_REQUEST) {
            return false
        }
        val request = pending ?: return true
        if (copying ||
            (requestCode == IMPORT_REQUEST && request.mode != Mode.IMPORT) ||
            (requestCode == EXPORT_REQUEST && request.mode != Mode.EXPORT) ||
            (requestCode == ZIP_REQUEST && request.mode != Mode.EXPORT_ZIP)) {
            return true
        }
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            pending = null
            resetProgress()
            request.result.success(mapOf("status" to "cancelled"))
            return true
        }
        copying = true
        transferDoneBytes = 0L
        transferTotalBytes = if (request.mode == Mode.IMPORT) {
            declaredSize(uri).takeIf { it > 0L } ?: -1L
        } else request.item?.size ?: -1L
        transferPhase = "copying"
        Thread {
            try {
                checkTransferActive(request)
                val response = when (request.mode) {
                    Mode.IMPORT -> copyIntoPrivate(request.owner, uri, request)
                    Mode.EXPORT -> copyOutVerified(
                        request.owner, request.item
                            ?: throw IOException("Asset selection missing"), uri, request)
                    Mode.EXPORT_ZIP -> copyOutCompressedZip(
                        request.owner, request.item
                            ?: throw IOException("Asset selection missing"), uri, request)
                }
                activity.runOnUiThread {
                    pending = null
                    copying = false
                    resetProgress()
                    if (!closed) request.result.success(response)
                }
            } catch (error: Exception) {
                if (request.mode != Mode.IMPORT) {
                    // If this user-selected document was partially written,
                    // attempt to remove it; some providers may reject deletion.
                    try { activity.contentResolver.delete(uri, null, null) }
                    catch (_: Exception) {}
                }
                activity.runOnUiThread {
                    pending = null
                    copying = false
                    resetProgress()
                    if (!closed) {
                        if (request.cancelRequested ||
                            error.message == "ASSET_TRANSFER_CANCELLED") {
                            request.result.success(mapOf("status" to "cancelled"))
                        } else request.result.error(
                            "ASSET_TRANSFER_FAILED", error.message, null)
                    }
                }
            }
        }.start()
        return true
    }

    private fun displayName(uri: Uri): String {
        val name = try {
            activity.contentResolver.query(uri,
                arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) { null }
        return safeName(name)
    }

    private fun copyIntoPrivate(
        owner: String, uri: Uri, request: Pending,
    ): Map<String, Any> {
        val root = directory(owner)
        val before = all(root)
        val previousBytes = before.sumOf { it.size }
        if (before.size >= MAX_FILES || previousBytes >= MAX_STORE_BYTES) {
            throw IOException("Private asset storage quota exceeded")
        }
        val id = UUID.randomUUID().toString().replace("-", "")
        val staging = file(root, id, ".part")
        val body = file(root, id, ".blob")
        val metadata = file(root, id, ".json")
        val name = displayName(uri)
        val mime = safeMime(activity.contentResolver.getType(uri))
        var size = 0L
        val hash = MessageDigest.getInstance("SHA-256")
        try {
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IOException("Selected file cannot be read")
            input.use { source ->
                FileOutputStream(staging).use { target ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        checkTransferActive(request)
                        val n = source.read(buffer)
                        if (n < 0) break
                        size += n
                        if (size > MAX_FILE_BYTES ||
                            size > MAX_STORE_BYTES - previousBytes) {
                            throw IOException("Selected file exceeds private storage limit")
                        }
                        target.write(buffer, 0, n)
                        hash.update(buffer, 0, n)
                        transferDoneBytes = size
                    }
                    target.fd.sync()
                }
            }
            checkTransferActive(request)
            if (size <= 0) throw IOException("Empty files cannot be imported")
            transferPhase = "finalizing"
            if (!staging.renameTo(body)) {
                throw IOException("Could not commit private file")
            }
            val record = Item(id, name, mime, size,
                hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) },
                System.currentTimeMillis())
            metadata.writeText(JSONObject().apply {
                put("id", id)
                put("name", record.name)
                put("mime", record.mime)
                put("sizeBytes", size)
                put("sha256", record.sha)
                put("createdMs", record.createdMs)
            }.toString(), Charsets.UTF_8)
            return mapOf("status" to "imported", "file" to record.exposed())
        } catch (error: Exception) {
            staging.delete()
            body.delete()
            metadata.delete()
            throw error
        }
    }

    private fun copyOutVerified(
        owner: String, record: Item, uri: Uri, request: Pending,
    ): Map<String, Any> {
        val root = directory(owner)
        // Revalidate original metadata immediately before touching destination.
        if (load(root, record.id) != record) {
            throw IOException("Asset metadata changed since export selection")
        }
        val body = file(root, record.id, ".blob")
        val sourceHash = MessageDigest.getInstance("SHA-256")
        var bytes = 0L
        val output = activity.contentResolver.openOutputStream(uri, "w")
            ?: throw IOException("Selected destination cannot be written")
        output.use { target ->
            body.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    checkTransferActive(request)
                    val n = input.read(buffer)
                    if (n < 0) break
                    bytes += n
                    if (bytes > record.size) throw IOException("Source changed")
                    target.write(buffer, 0, n)
                    sourceHash.update(buffer, 0, n)
                    transferDoneBytes = bytes
                }
            }
            target.flush()
        }
        val sourceDigest = sourceHash.digest()
        if (bytes != record.size ||
            !sourceDigest.contentEquals(hexBytes(record.sha))) {
            throw IOException("Private asset content no longer matches its checksum")
        }
        transferPhase = "verifying"
        val destinationHash = MessageDigest.getInstance("SHA-256")
        var readback = 0L
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Destination cannot be verified after export")
        input.use { stream ->
            val buffer = ByteArray(65536)
            while (true) {
                checkTransferActive(request)
                val n = stream.read(buffer)
                if (n < 0) break
                readback += n
                if (readback > bytes) throw IOException("Destination unexpectedly larger")
                destinationHash.update(buffer, 0, n)
            }
        }
        if (readback != bytes ||
            !sourceDigest.contentEquals(destinationHash.digest())) {
            throw IOException("Exported asset failed SHA-256 verification")
        }
        checkTransferActive(request)
        transferPhase = "finalizing"
        return mapOf("status" to "saved", "sizeBytes" to bytes,
            "sha256" to record.sha)
    }

    /**
     * Stream a standards-compliant DEFLATE ZIP without materializing
     * the source bytes in JavaScript or writing temporary public files.
     * SHA-256 verifies the source against vault metadata and the actual
     * saved ZIP bytes against what the encoder wrote.
     */
    private fun copyOutCompressedZip(
        owner: String, record: Item, uri: Uri, request: Pending,
    ): Map<String, Any> {
        val root = directory(owner)
        if (load(root, record.id) != record) {
            throw IOException("Asset metadata changed before compression")
        }
        val sourceFile = file(root, record.id, ".blob")
        val archiveDigest = MessageDigest.getInstance("SHA-256")
        val inputDigest = MessageDigest.getInstance("SHA-256")
        var sourceBytes = 0L
        val output = activity.contentResolver.openOutputStream(uri, "w")
            ?: throw IOException("ZIP destination cannot be opened")
        ZipOutputStream(DigestOutputStream(output, archiveDigest)).use { zip ->
            zip.setLevel(request.compressionLevel)
            zip.putNextEntry(ZipEntry("files/" + record.name))
            sourceFile.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    checkTransferActive(request)
                    val count = input.read(buffer)
                    if (count < 0) break
                    sourceBytes += count
                    if (sourceBytes > record.size) {
                        throw IOException("Source grew while compressing")
                    }
                    zip.write(buffer, 0, count)
                    inputDigest.update(buffer, 0, count)
                    transferDoneBytes = sourceBytes
                }
            }
            if (sourceBytes != record.size ||
                !inputDigest.digest().contentEquals(hexBytes(record.sha))) {
                throw IOException("Source file failed SHA-256 verification")
            }
            checkTransferActive(request)
            zip.closeEntry()
            val manifest = JSONObject().apply {
                put("schemaVersion", 1)
                put("format", "chappy-asset-zip")
                put("fileName", record.name)
                put("mime", record.mime)
                put("sourceBytes", sourceBytes)
                put("sourceSha256", record.sha)
                put("compressionLevel", request.compressionLevel)
            }.toString().toByteArray(Charsets.UTF_8)
            zip.putNextEntry(ZipEntry("manifest.json"))
            zip.write(manifest)
            zip.closeEntry()
        }

        transferPhase = "verifying"
        val expectedArchiveHash = archiveDigest.digest()
        val actualArchiveHash = MessageDigest.getInstance("SHA-256")
        var zippedBytes = 0L
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Saved ZIP cannot be read back")
        input.use { stream ->
            val buffer = ByteArray(65536)
            while (true) {
                checkTransferActive(request)
                val count = stream.read(buffer)
                if (count < 0) break
                zippedBytes += count
                if (zippedBytes > record.size + 1048576L) {
                    throw IOException("ZIP output unexpectedly larger than source")
                }
                actualArchiveHash.update(buffer, 0, count)
            }
        }
        if (zippedBytes <= 0 ||
            !expectedArchiveHash.contentEquals(actualArchiveHash.digest())) {
            throw IOException("Saved ZIP failed SHA-256 readback")
        }
        checkTransferActive(request)
        transferPhase = "finalizing"
        return mapOf(
            "status" to "saved",
            "originalBytes" to sourceBytes,
            "zipBytes" to zippedBytes,
            "savedBytes" to (sourceBytes - zippedBytes),
            "percentSmaller" to (100.0 * (sourceBytes - zippedBytes) / sourceBytes),
            "compressionLevel" to request.compressionLevel,
            "sha256" to hex(expectedArchiveHash),
        )
    }

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun hexBytes(hex: String): ByteArray {
        if (!Regex("^[a-f0-9]{64}$").matches(hex)) {
            throw IOException("Malformed asset SHA-256")
        }
        return ByteArray(32) { idx -> hex.substring(idx * 2, idx * 2 + 2).toInt(16).toByte() }
    }

    fun onDestroy() {
        closed = true
        pending?.cancelRequested = true
        pending = null
        resetProgress()
    }
}
