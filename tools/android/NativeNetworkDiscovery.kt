package dev.chappy.chappy_player

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Foreground, user-initiated DNS-SD discovery for the trusted player UI only.
 * No raw subnet scanning, packet capture, service connection or .chappy bridge.
 * Results remain in memory and are erased when the host backgrounds.
 */
class NativeNetworkDiscovery(private val activity: Activity) {
    companion object {
        const val MAX_SERVICES = 24
        const val MAX_SCAN_MS = 15000L
        val SERVICE_TYPES = setOf("_http._tcp.", "_workstation._tcp.", "_ipp._tcp.")
    }

    private data class Found(
        val id: String,
        val name: String,
        val type: String,
        var address: String = "",
        var port: Int = 0,
        var resolved: Boolean = false
    )

    // Activity services must be obtained lazily after Activity.attach().
    private val nsd by lazy {
        activity.getSystemService(Context.NSD_SERVICE) as NsdManager
    }
    private val connectivity by lazy {
        activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }
    private val wifi by lazy {
        activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }
    private val handler = Handler(Looper.getMainLooper())
    private var foreground = false
    private var running = false
    private var generation = 0L
    private var serviceType = "_http._tcp."
    private var discovery: NsdManager.DiscoveryListener? = null
    private var timeout: Runnable? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val found = linkedMapOf<String, Found>()
    private val pending = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var lastError: String? = null
    private var deadlineMs = 0L

    fun onResume() { foreground = true }

    fun onPause() {
        foreground = false
        stopInternal(clearResults = true)
    }

    fun onDestroy() { onPause() }

    private fun serviceKey(info: NsdServiceInfo): String =
        info.serviceType + "|" + info.serviceName

    private fun hasLocalNetwork(): Boolean {
        val network = connectivity.activeNetwork ?: return false
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    // Separate foreground/network guard for user-confirmed TLS PC pairing.
    // Never grants raw LAN access to untrusted mini-app JavaScript.
    fun pairingAllowed(): Boolean =
        foreground && hasLocalNetwork() &&
            !(Build.VERSION.SDK_INT >= 37 &&
              activity.applicationInfo.targetSdkVersion >= 37)

    // NETLAB-04B requires active Wi-Fi, never a VPN or cellular route.
    // Kept distinct from older QR-v3 pairing to avoid changing its contract.
    fun trafficPairingAllowed(): Boolean {
        if (!pairingAllowed()) return false
        val network = connectivity.activeNetwork ?: return false
        val caps = connectivity.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
    }

    fun start(type: String): Map<String, Any?> {
        if (!foreground) throw IllegalStateException("Network Lab requires foreground")
        if (running || discovery != null) {
            throw IllegalStateException("Discovery already running")
        }
        if (type !in SERVICE_TYPES) {
            throw IllegalArgumentException("Unsupported DNS-SD service type")
        }
        // Android 17+ targetSdk 37 requires ACCESS_LOCAL_NETWORK or the
        // scoped service picker. Fail closed until the picker is implemented
        // and compiled with SDK 37; no implicit broad LAN permission.
        if (Build.VERSION.SDK_INT >= 37 &&
            activity.applicationInfo.targetSdkVersion >= 37) {
            throw IllegalStateException("Android 17 service picker not yet implemented")
        }
        if (!hasLocalNetwork()) {
            throw IllegalStateException("Wi-Fi or Ethernet connection required")
        }

        generation++
        val session = generation
        found.clear()
        pending.clear()
        resolving = false
        lastError = null
        serviceType = type
        deadlineMs = SystemClock.elapsedRealtime() + MAX_SCAN_MS
        running = true

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}
            override fun onDiscoveryStopped(regType: String) {}
            override fun onStartDiscoveryFailed(regType: String, errorCode: Int) {
                if (generation != session) return
                lastError = "Service discovery could not start ($errorCode)"
                stopInternal(clearResults = false)
            }
            override fun onStopDiscoveryFailed(regType: String, errorCode: Int) {
                if (generation == session) {
                    lastError = "Service discovery stop error ($errorCode)"
                }
            }
            override fun onServiceFound(info: NsdServiceInfo) {
                if (!running || generation != session) return
                if (info.serviceName.length > 120 ||
                    info.serviceType.length > 80) return
                val id = serviceKey(info)
                if (id !in found && found.size >= MAX_SERVICES) return
                if (id !in found) {
                    found[id] = Found(
                        id = id,
                        name = info.serviceName,
                        type = info.serviceType
                    )
                    pending.addLast(info)
                    resolveNext(session)
                }
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                if (generation != session) return
                found.remove(serviceKey(info))
            }
        }

        discovery = listener
        try {
            // On older Android releases mDNS needs a Wi-Fi multicast lock.
            if (Build.VERSION.SDK_INT < 33) {
                val lock = wifi.createMulticastLock("chappy-netlab-nsd")
                lock.setReferenceCounted(false)
                lock.acquire()
                multicastLock = lock
            }
            nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
            val task = Runnable {
                if (running && generation == session) {
                    stopInternal(clearResults = false)
                }
            }
            timeout = task
            handler.postDelayed(task, MAX_SCAN_MS)
        } catch (error: Exception) {
            stopInternal(clearResults = false)
            throw error
        }
        return snapshot()
    }

    private fun resolveNext(session: Long) {
        if (!running || session != generation || resolving) return
        while (pending.isNotEmpty()) {
            val item = pending.removeFirst()
            val id = serviceKey(item)
            if (!found.containsKey(id)) continue
            resolving = true
            try {
                @Suppress("DEPRECATION")
                nsd.resolveService(item, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        if (session != generation) return
                        resolving = false
                        resolveNext(session)
                    }
                    override fun onServiceResolved(info: NsdServiceInfo) {
                        if (running && generation == session) {
                            found[id]?.apply {
                                address = info.host?.hostAddress ?: ""
                                port = info.port.coerceIn(0, 65535)
                                resolved = address.isNotEmpty()
                            }
                        }
                        if (session != generation) return
                        resolving = false
                        resolveNext(session)
                    }
                })
            } catch (_: Exception) {
                resolving = false
                continue
            }
            return
        }
    }

    fun snapshot(): Map<String, Any?> = mapOf(
        "running" to running,
        "serviceType" to serviceType,
        "remainingSeconds" to
            (if (running) ((deadlineMs - SystemClock.elapsedRealtime())
                .coerceAtLeast(0L) + 999L) / 1000L else 0L),
        "error" to lastError,
        "services" to found.values.take(MAX_SERVICES).map {
            mapOf(
                "id" to it.id,
                "name" to it.name,
                "type" to it.type,
                "address" to it.address,
                "port" to it.port,
                "resolved" to it.resolved
            )
        }
    )

    fun stop(): Map<String, Any?> {
        stopInternal(clearResults = false)
        return snapshot()
    }

    private fun stopInternal(clearResults: Boolean) {
        generation++
        running = false
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        val listener = discovery
        discovery = null
        pending.clear()
        resolving = false
        if (listener != null) {
            try {
                nsd.stopServiceDiscovery(listener)
            } catch (_: Exception) {
                // The NSD framework may have already stopped this listener.
            }
        }
        multicastLock?.let { lock ->
            try {
                if (lock.isHeld) lock.release()
            } catch (_: Exception) {}
        }
        multicastLock = null
        if (clearResults) {
            found.clear()
            lastError = null
        }
    }
}
