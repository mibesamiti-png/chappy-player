package dev.chappy.chappy_player

import android.net.TrafficStats
import android.os.Process
import android.os.SystemClock

/**
 * Read-only Android traffic counters for the trusted Network Lab host UI.
 * This reads aggregated network-layer bytes since boot; not payloads, packets,
 * remote LAN devices, per-app inventories, or Wi-Fi-only statistics.
 *
 * No background worker, persistence, additional permissions or .chappy bridge.
 * MainActivity must enforce foreground visibility for every call.
 */
class NativeTrafficCounters {
    fun snapshot(): Map<String, Any?> {
        val totalRx = TrafficStats.getTotalRxBytes()
        val totalTx = TrafficStats.getTotalTxBytes()
        val myUid = Process.myUid()
        val appRx = TrafficStats.getUidRxBytes(myUid)
        val appTx = TrafficStats.getUidTxBytes(myUid)
        val totalValid = totalRx >= 0L && totalTx >= 0L
        val appValid = appRx >= 0L && appTx >= 0L

        return mapOf(
            "elapsedMs" to SystemClock.elapsedRealtime(),
            "supported" to totalValid,
            "rxBytes" to if (totalValid) totalRx else null,
            "txBytes" to if (totalValid) totalTx else null,
            "appSupported" to appValid,
            "appRxBytes" to if (appValid) appRx else null,
            "appTxBytes" to if (appValid) appTx else null,
            "source" to "android.trafficstats.since_boot"
        )
    }
}
