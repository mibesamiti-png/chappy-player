package dev.chappy.chappy_player

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.spec.ECGenParameterSpec

/**
 * Explicitly created Android-only identity key for FUTURE PC mutual pairing.
 *
 * P-256 private signing material remains inside the AndroidKeyStore provider.
 * No arbitrary signing endpoint, no private key export, no WebView/.chappy
 * bridge, no persistent PC trust, and no remote-control authorization.
 *
 * Creation/revocation are only invoked from trusted Flutter host UI, when
 * the Activity is foreground; status is a public-key hash, never a secret.
 */
class NativePcIdentity {
    companion object {
        private const val ALIAS = "dev.chappy.player.pc_identity.p256.v1"
    }

    private fun store(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Synchronized
    fun status(): Map<String, Any> {
        val keyStore = store()
        if (!keyStore.containsAlias(ALIAS)) {
            return mapOf("created" to false, "algorithm" to "P-256")
        }
        val certificate = keyStore.getCertificate(ALIAS)
            ?: throw IllegalStateException("PC identity certificate unavailable")
        val publicBytes = certificate.publicKey.encoded
            ?: throw IllegalStateException("Public key unavailable")
        val digest = MessageDigest.getInstance("SHA-256").digest(publicBytes)
        val fingerprint = digest.joinToString("") {
            "%02x".format(it.toInt() and 0xff)
        }
        return mapOf(
            "created" to true,
            "algorithm" to "P-256",
            "fingerprint" to fingerprint
        )
    }

    @Synchronized
    fun create(): Map<String, Any> {
        if (store().containsAlias(ALIAS)) {
            throw IllegalStateException("Device identity already exists")
        }
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore"
        )
        val options = KeyGenParameterSpec.Builder(
            ALIAS, KeyProperties.PURPOSE_SIGN
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .build()
        generator.initialize(options)
        generator.generateKeyPair()
        return status()
    }

    /**
     * Re-read and compare the precise public identity under the same lock
     * before deleting. The Flutter dialog alone cannot authorize a stale
     * fingerprint after an identity change.
     */
    @Synchronized
    fun revoke(expectedFingerprint: String): Boolean {
        require(Regex("^[0-9a-f]{64}$").matches(expectedFingerprint)) {
            "Invalid expected identity fingerprint"
        }
        val keyStore = store()
        if (!keyStore.containsAlias(ALIAS)) return false
        val currentFingerprint = status()["fingerprint"] as? String
            ?: throw IllegalStateException("Current device identity unavailable")
        require(currentFingerprint == expectedFingerprint) {
            "Device identity changed; retry with the current public fingerprint"
        }
        keyStore.deleteEntry(ALIAS)
        return true
    }
}
