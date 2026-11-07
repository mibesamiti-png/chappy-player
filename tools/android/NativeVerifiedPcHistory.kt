package dev.chappy.chappy_player

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

/**
 * An opt-in, device-local history of QR-v3 verified PC public fingerprints.
 *
 * Not an authorization list: no socket, auto-reconnect, trust decision, PC
 * command, secret or .chappy bridge consumes these records. Records are only
 * hints for future explicit pairing; every connection must still authenticate.
 */
internal class NativeVerifiedPcHistory(
    context: Context,
    private val identity: NativePcIdentity
) {
    private val file = AtomicFile(File(context.filesDir, "verified-pc-history-v1.aesgcm"))
    private val keyAlias = "dev.chappy.player.verified_pc_history.aesgcm.v1"
    private val fingerprintPattern = Regex("^[0-9a-f]{64}$")

    companion object {
        private const val MAX_RECORDS = 24
        private const val MAX_BLOB = 8192
        private const val NONCE_SIZE = 12
    }

    private fun owner(): String {
        val status = identity.status()
        return status["fingerprint"] as? String
            ?: throw IllegalStateException("Create an Android device identity first")
    }

    private fun secret(create: Boolean): SecretKey? {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null)
        if (existing != null) {
            return existing as? SecretKey
                ?: throw IllegalStateException("Invalid history encryption key")
        }
        if (!create) return null
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            ).setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    private fun decrypt(): JSONObject? {
        if (!file.exists()) return null
        val encrypted = file.openRead().use { input ->
            // Compatible with minSdk 24, bounded even for corrupt/cyclic input.
            val output = ByteArrayOutputStream()
            val chunk = ByteArray(1024)
            while (true) {
                val count = input.read(chunk)
                if (count < 0) break
                require(output.size() + count <= MAX_BLOB) {
                    "Corrupt verified-PC history"
                }
                output.write(chunk, 0, count)
            }
            output.toByteArray().also { data ->
                require(data.size >= NONCE_SIZE + 16) {
                    "Corrupt verified-PC history"
                }
            }
        }
        val key = secret(false)
            ?: throw IllegalStateException("History decryption key is missing")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE, key,
            GCMParameterSpec(128, encrypted.copyOfRange(0, NONCE_SIZE))
        )
        val plaintext = cipher.doFinal(encrypted.copyOfRange(NONCE_SIZE, encrypted.size))
        require(plaintext.size <= MAX_BLOB) { "History is too large" }
        return JSONObject(String(plaintext, StandardCharsets.UTF_8))
    }

    private fun read(ownerFp: String): MutableList<Pair<String, Long>> {
        val document = decrypt() ?: return mutableListOf()
        require(document.length() == 3 && document.optInt("schema", -1) == 1)
        require(document.getString("owner") == ownerFp) {
            "Device key changed: old verification history is not reusable"
        }
        val records = document.getJSONArray("records")
        require(records.length() <= MAX_RECORDS) { "Too many history records" }
        val found = mutableListOf<Pair<String, Long>>()
        for (index in 0 until records.length()) {
            val item = records.getJSONObject(index)
            require(item.length() == 2)
            val fp = item.getString("fingerprint")
            val added = item.getLong("added")
            require(fingerprintPattern.matches(fp) && added > 0)
            require(found.none { it.first == fp }) { "Duplicate history fingerprint" }
            found.add(fp to added)
        }
        return found
    }

    private fun write(ownerFp: String, entries: List<Pair<String, Long>>) {
        require(entries.size <= MAX_RECORDS)
        val recordArray = JSONArray()
        for ((fp, added) in entries) {
            recordArray.put(JSONObject().put("fingerprint", fp).put("added", added))
        }
        val payload = JSONObject()
            .put("schema", 1).put("owner", ownerFp)
            .put("records", recordArray)
            .toString().toByteArray(StandardCharsets.UTF_8)
        require(payload.size <= MAX_BLOB - NONCE_SIZE - 16)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        // AndroidKeyStore GCM supplies a fresh provider-generated IV.
        cipher.init(Cipher.ENCRYPT_MODE, secret(true)
            ?: throw IllegalStateException("History encryption key unavailable"))
        val nonce = cipher.iv
        require(nonce.size == NONCE_SIZE)
        val encrypted = nonce + cipher.doFinal(payload)
        require(encrypted.size <= MAX_BLOB)
        val stream = file.startWrite()
        try {
            stream.write(encrypted)
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    private fun result(records: List<Pair<String, Long>>): List<Map<String, Any>> =
        records.map { (fp, added) ->
            mapOf("fingerprint" to fp, "added" to added)
        }

    @Synchronized
    fun list(): List<Map<String, Any>> = result(read(owner()))

    @Synchronized
    fun remember(fingerprint: String): List<Map<String, Any>> {
        require(fingerprintPattern.matches(fingerprint)) {
            "Expected a lowercase SPKI SHA-256 fingerprint"
        }
        val device = owner()
        require(fingerprint != device) { "Self identity cannot be a PC" }
        val current = read(device)
        // Record only on an explicit trusted-UI request following QR-v3 success.
        if (current.any { it.first == fingerprint }) return result(current)
        require(current.size < MAX_RECORDS) { "Verified PC history is full" }
        current.add(fingerprint to (System.currentTimeMillis() / 1000L))
        write(device, current)
        return result(current)
    }

    @Synchronized
    fun forget(fingerprint: String): List<Map<String, Any>> {
        require(fingerprintPattern.matches(fingerprint))
        val device = owner()
        val current = read(device)
        current.removeAll { it.first == fingerprint }
        if (current.isEmpty()) {
            // No trust record remains; delete the encrypted file.
            file.delete()
        } else {
            write(device, current)
        }
        return result(current)
    }

    @Synchronized
    fun clearAll() {
        file.delete()
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(keyAlias)) store.deleteEntry(keyAlias)
    }
}
