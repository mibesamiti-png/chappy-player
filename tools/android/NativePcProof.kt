package dev.chappy.chappy_player

import android.util.Base64
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec

/**
 * Host-internal P-256 proof of identity ownership (NETLAB-03B-3).
 *
 * Deliberately NOT routed to MainActivity MethodChannel or .chappy JavaScript.
 * In particular, no network request, pairing approval, stored peer trust,
 * remote PC control or auto-sign occurs here. Future enrollment must receive
 * an explicitly approved, verifier-issued one-time challenge on pinned TLS.
 */
internal object NativePcProof {
    private const val ALIAS = "dev.chappy.player.pc_identity.p256.v1"
    private const val VERSION = "CHAPPY-NETLAB-03B-PROOF-V1"
    private const val MAX_EXPIRY = 253402300799L
    private val HEX16 = Regex("^[0-9a-f]{32}$")
    private val HEX32 = Regex("^[0-9a-f]{64}$")
    private val P256_ORDER = BigInteger(
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16
    )

    internal fun canonicalChallenge(
        role: String, invitation: String, tlsFingerprint: String,
        peerFingerprint: String, nonce: String, expiresAt: Long
    ): ByteArray {
        require(role == "pc" || role == "android") { "Invalid proof role" }
        require(HEX16.matches(invitation)) { "Invalid invitation" }
        require(HEX32.matches(tlsFingerprint) && HEX32.matches(peerFingerprint)
                && HEX32.matches(nonce)) { "Invalid SHA256/nonce hex" }
        require(expiresAt in 1..MAX_EXPIRY) { "Invalid expiry" }
        // This must be byte-identical to identity_proof.canonical_challenge.
        val message = buildString {
            append(VERSION).append('\n')
            append("role=").append(role).append('\n')
            append("invitation=").append(invitation).append('\n')
            append("tls=").append(tlsFingerprint).append('\n')
            append("peer=").append(peerFingerprint).append('\n')
            append("nonce=").append(nonce).append('\n')
            append("expires=").append(expiresAt).append('\n')
        }
        return message.toByteArray(Charsets.US_ASCII)
    }

    /** Only for a future trusted host-controlled, on-screen approval workflow. */
    internal fun signAndroid(
        invitation: String, tlsFingerprint: String, peerFingerprint: String,
        nonce: String, expiresAt: Long
    ): Map<String, String> {
        val now = System.currentTimeMillis() / 1000L
        require(expiresAt > now && expiresAt - now <= 90L) {
            "Identity proof must expire within 90 seconds"
        }
        val message = canonicalChallenge(
            "android", invitation, tlsFingerprint, peerFingerprint, nonce, expiresAt
        )
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        require(store.containsAlias(ALIAS)) { "Explicit device identity is missing" }
        val key = store.getKey(ALIAS, null) as? PrivateKey
            ?: throw IllegalStateException("AndroidKeyStore identity is unavailable")
        val publicSpki = store.getCertificate(ALIAS)?.publicKey?.encoded
            ?: throw IllegalStateException("Public identity is unavailable")
        require(publicSpki.size in 1..256)
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(key)
        signer.update(message)
        val signature = signer.sign()
        require(signature.size in 1..256)
        return mapOf(
            "algorithm" to "P-256-SHA256",
            "spki" to Base64.encodeToString(publicSpki, Base64.NO_WRAP),
            "signature" to Base64.encodeToString(signature, Base64.NO_WRAP)
        )
    }

    private fun decodeCanonical(value: String, maxSize: Int): ByteArray {
        require(value.length <= 4 * ((maxSize + 2) / 3))
        val decoded = Base64.decode(value, Base64.NO_WRAP)
        require(decoded.size in 1..maxSize)
        require(Base64.encodeToString(decoded, Base64.NO_WRAP) == value)
        return decoded
    }

    /**
     * Never trust a key merely because it appears in response. The fingerprint
     * must be obtained independently, and nonce/invitation consumed once by
     * a later session owner. This alone is NOT persistent pairing.
     */
    internal fun verifyPeerProof(
        response: Map<String, String>, expectedSignerFingerprint: String,
        role: String, invitation: String, tlsFingerprint: String,
        peerFingerprint: String, nonce: String, expiresAt: Long,
        nowEpochSeconds: Long
    ): Boolean {
        if (nowEpochSeconds !in 1..MAX_EXPIRY ||
            expiresAt !in 1..MAX_EXPIRY ||
            nowEpochSeconds > expiresAt ||
            expiresAt - nowEpochSeconds > 600L ||
            !HEX32.matches(expectedSignerFingerprint)) return false
        return try {
            val message = canonicalChallenge(
                role, invitation, tlsFingerprint, peerFingerprint, nonce, expiresAt
            )
            if (response.keys != setOf("algorithm", "spki", "signature") ||
                response["algorithm"] != "P-256-SHA256") return false
            val spki = decodeCanonical(response.getValue("spki"), 256)
            val signature = decodeCanonical(response.getValue("signature"), 256)
            val digestHex = MessageDigest.getInstance("SHA-256").digest(spki)
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
            if (digestHex != expectedSignerFingerprint) return false
            val key = KeyFactory.getInstance("EC")
                .generatePublic(X509EncodedKeySpec(spki)) as? ECPublicKey
                ?: return false
            if (key.params.curve.field.fieldSize != 256 ||
                key.params.order != P256_ORDER) return false
            val verifier = Signature.getInstance("SHA256withECDSA")
            verifier.initVerify(key)
            verifier.update(message)
            verifier.verify(signature)
        } catch (_: Exception) {
            false
        }
    }
}
