package dev.chappy.chappy_player

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetAddress
import java.net.Proxy
import java.net.SocketTimeoutException
import java.net.URL

/**
 * NETLAB-05C: one-shot, user-approved router identity *candidate*.
 *
 * The gateway comes from Android's active Wi-Fi default route. One standard
 * SSDP rootdevice discovery datagram is emitted; ONLY replies from that exact
 * IPv4 gateway are accepted. At most one 16KiB device-description document is
 * read from that same gateway without credentials, redirects, or control calls.
 * Nothing is persisted or exposed to untrusted .chappy JavaScript.
 *
 * UPnP metadata is self-asserted and MUST NOT be trusted as device identity.
 */
class NativeRouterIdentity(private val activity: Activity) {
    companion object {
        private const val MAX_SSDP_REPLY = 2048
        private const val MAX_XML_BYTES = 16384
        private const val MAX_WAIT_MS = 2400L
        private const val MAX_RESPONSES = 8
    }

    @Volatile private var foreground = false
    @Volatile private var generation = 0L

    fun onResume() { foreground = true }
    fun onPause() {
        foreground = false
        generation++
    }
    fun onDestroy() { onPause() }

    private fun isPrivateIpv4(address: InetAddress?): Boolean {
        if (address !is Inet4Address) return false
        val octets = address.address.map { it.toInt() and 255 }
        return octets[0] == 10 ||
            (octets[0] == 172 && octets[1] in 16..31) ||
            (octets[0] == 192 && octets[1] == 168)
    }

    private fun requireSession(session: Long) {
        check(foreground && generation == session) {
            "Router identity request cancelled"
        }
    }

    private fun clean(value: String?): String? {
        if (value == null) return null
        val candidate = value.trim()
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
        if (candidate.isEmpty() || candidate.length > 96 ||
            candidate.any { it.code < 32 || it.code == 127 ||
                it == '<' || it == '>' || it == '\\' }) return null
        return candidate
    }

    private fun extractXmlField(xml: String, name: String): String? {
        // Bounded, display-only text extraction: never parse entities or DTDs.
        val tag = Regex(
            "<(?:[A-Za-z][A-Za-z0-9_-]*:)?$name[^>]*>([^<]{1,96})</(?:[A-Za-z][A-Za-z0-9_-]*:)?$name>",
            RegexOption.IGNORE_CASE
        )
        return clean(tag.find(xml)?.groupValues?.getOrNull(1))
    }

    private fun descriptionUrl(message: String, gateway: String): URL? {
        if (!message.startsWith("HTTP/1.1 200") &&
            !message.startsWith("HTTP/1.0 200")) return null
        if (message.length > MAX_SSDP_REPLY) return null
        val location = message.split("\r\n", "\n")
            .firstOrNull { it.startsWith("LOCATION:", ignoreCase = true) }
            ?.substringAfter(':')?.trim() ?: return null
        if (location.length > 512 || location.any { it.code < 32 }) return null
        return try {
            val url = URL(location)
            if (url.protocol != "http" || url.host != gateway ||
                url.userInfo != null || url.ref != null ||
                url.port == 0 || url.port > 65535 ||
                url.path.isEmpty() || url.path.length > 256) {
                null
            } else {
                url
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun readDescription(network: Network, url: URL): Map<String, String>? {
        val connection = network.openConnection(url, Proxy.NO_PROXY) as? HttpURLConnection
            ?: return null
        try {
            connection.connectTimeout = 1200
            connection.readTimeout = 1200
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept", "text/xml, application/xml")
            if (connection.responseCode != 200) return null
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(2048)
            connection.inputStream.use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > MAX_XML_BYTES) return null
                    output.write(buffer, 0, count)
                }
            }
            val xml = output.toString(Charsets.UTF_8.name())
            if (!xml.contains("<root", ignoreCase = true) ||
                xml.contains("<!DOCTYPE", ignoreCase = true) ||
                xml.contains("<!ENTITY", ignoreCase = true)) return null
            val model = extractXmlField(xml, "modelName")
            val manufacturer = extractXmlField(xml, "manufacturer")
            val friendly = extractXmlField(xml, "friendlyName")
            val modelNumber = extractXmlField(xml, "modelNumber")
            if (model == null && manufacturer == null &&
                friendly == null && modelNumber == null) return null
            return mapOf(
                "manufacturer" to (manufacturer ?: ""),
                "modelName" to (model ?: ""),
                "modelNumber" to (modelNumber ?: ""),
                "friendlyName" to (friendly ?: "")
            )
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Called ONLY from a background worker thread in the Android host.
     * No management login, configuration change, packet inspection or sweep.
     */
    fun probe(): Map<String, Any?> {
        val session = generation
        requireSession(session)
        if (Build.VERSION.SDK_INT >= 37 &&
            activity.applicationInfo.targetSdkVersion >= 37) {
            throw IllegalStateException("Android local network picker not available")
        }
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE)
            as ConnectivityManager
        val network = cm.activeNetwork ?: throw IllegalStateException("No active Wi-Fi")
        val caps = cm.getNetworkCapabilities(network)
            ?: throw IllegalStateException("No Wi-Fi network capabilities")
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
            throw IllegalStateException("Active Wi-Fi without VPN required")
        }
        val link = cm.getLinkProperties(network)
            ?: throw IllegalStateException("No Wi-Fi route information")
        val gateway = link.routes.firstNotNullOfOrNull { route ->
            val candidate = route.gateway
            if (route.isDefaultRoute && isPrivateIpv4(candidate)) candidate else null
        } as? Inet4Address
            ?: throw IllegalStateException("Private IPv4 gateway unavailable")
        val gatewayAddress = gateway.hostAddress
            ?: throw IllegalStateException("Gateway address unavailable")

        // The route is trustworthy as a local OS observation; vendor/model is not.
        var outcome: Map<String, String>? = null
        val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE)
            as WifiManager
        var lock: WifiManager.MulticastLock? = null
        try {
            requireSession(session)
            lock = wifi.createMulticastLock("chappy-router-identity")
            lock.setReferenceCounted(false)
            lock.acquire()
            DatagramSocket().use { socket ->
                // Bind to the same active Wi-Fi route; never silently use cellular.
                network.bindSocket(socket)
                val payload = (
                    "M-SEARCH * HTTP/1.1\r\n" +
                    "HOST: 239.255.255.250:1900\r\n" +
                    "MAN: \"ssdp:discover\"\r\n" +
                    "MX: 1\r\n" +
                    "ST: upnp:rootdevice\r\n\r\n"
                ).toByteArray(Charsets.US_ASCII)
                socket.send(DatagramPacket(
                    payload, payload.size,
                    InetAddress.getByName("239.255.255.250"), 1900
                ))
                val until = SystemClock.elapsedRealtime() + MAX_WAIT_MS
                var received = 0
                while (received < MAX_RESPONSES &&
                    SystemClock.elapsedRealtime() < until) {
                    requireSession(session)
                    socket.soTimeout = (until - SystemClock.elapsedRealtime())
                        .coerceIn(1L, 450L).toInt()
                    val packet = DatagramPacket(ByteArray(MAX_SSDP_REPLY), MAX_SSDP_REPLY)
                    try {
                        socket.receive(packet)
                    } catch (_: SocketTimeoutException) {
                        continue
                    }
                    received++
                    if (packet.address != gateway) continue
                    val reply = String(packet.data, 0, packet.length, Charsets.US_ASCII)
                    val url = descriptionUrl(reply, gatewayAddress) ?: continue
                    // Only one no-credential XML GET to the OS-selected gateway.
                    outcome = readDescription(network, url)
                    break
                }
            }
        } catch (_: Exception) {
            // Lack of UPnP support is normal: keep the OS gateway observation.
        } finally {
            try {
                if (lock?.isHeld == true) lock.release()
            } catch (_: Exception) {}
        }

        requireSession(session)
        if (cm.activeNetwork != network) {
            throw IllegalStateException("Network changed during identification")
        }
        val hint = outcome
        return mapOf(
            "gatewayIpv4" to gatewayAddress,
            "manufacturer" to (hint?.get("manufacturer") ?: ""),
            "modelName" to (hint?.get("modelName") ?: ""),
            "modelNumber" to (hint?.get("modelNumber") ?: ""),
            "friendlyName" to (hint?.get("friendlyName") ?: ""),
            "evidence" to if (hint == null) "gateway_only" else "upnp_self_report",
            "source" to "android_wifi_default_route"
        )
    }
}
