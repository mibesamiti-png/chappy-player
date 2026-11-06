package dev.chappy.chappy_player

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground-only per-request sensor reading and bounded, predefined haptics.
 * The Flutter host checks each .chappy manifest AND confirms first use.
 * Never creates a long-lived motion logger or collects background readings.
 */
class NativeMiniAppDevices(private val activity: Activity) {
    private val sensors =
        activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val handler = Handler(Looper.getMainLooper())
    private var foreground = false
    private var activeListener: SensorEventListener? = null
    private var activeResult: MethodChannel.Result? = null
    private var activeTimeout: Runnable? = null
    private var lastHapticAt = 0L

    fun onResume() { foreground = true }
    fun onPause() {
        foreground = false
        cancelSample("MOTION_NOT_FOREGROUND", "Sensor read cancelled: app backgrounded")
    }
    fun onDestroy() { onPause() }

    private fun cancelSample(code: String, message: String) {
        activeListener?.let { sensors.unregisterListener(it) }
        activeListener = null
        activeTimeout?.let { handler.removeCallbacks(it) }
        activeTimeout = null
        val previous = activeResult
        activeResult = null
        previous?.error(code, message, null)
    }

    fun sample(type: String, result: MethodChannel.Result) {
        if (!foreground) {
            result.error("MOTION_NOT_FOREGROUND", "App must be visible", null)
            return
        }
        if (activeResult != null) {
            result.error("MOTION_BUSY", "Previous sensor sample still pending", null)
            return
        }
        val sensorType = when (type) {
            "accelerometer" -> Sensor.TYPE_ACCELEROMETER
            "gyroscope" -> Sensor.TYPE_GYROSCOPE
            "magnetometer" -> Sensor.TYPE_MAGNETIC_FIELD
            else -> {
                result.error("MOTION_TYPE_UNSUPPORTED", "Unknown sensor type", null)
                return
            }
        }
        val device = sensors.getDefaultSensor(sensorType)
        if (device == null) {
            result.success(mapOf("available" to false, "type" to type))
            return
        }

        // Always unregister at the first reading, timeout, or Activity pause.
        val listener = object : SensorEventListener {
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            override fun onSensorChanged(event: SensorEvent) {
                if (activeListener !== this || activeResult !== result) return
                val data = event.values.take(3).map { it.toDouble() }
                sensors.unregisterListener(this)
                activeListener = null
                activeTimeout?.let { handler.removeCallbacks(it) }
                activeTimeout = null
                activeResult = null
                result.success(mapOf(
                    "available" to true,
                    "type" to type,
                    "values" to data,
                    "accuracy" to event.accuracy,
                    "timestampMs" to SystemClock.elapsedRealtime()
                ))
            }
        }
        activeResult = result
        activeListener = listener
        val timeout = Runnable {
            if (activeResult === result) {
                cancelSample("MOTION_TIMEOUT", "No sensor sample in 1500 ms")
            }
        }
        activeTimeout = timeout
        if (!sensors.registerListener(listener, device, SensorManager.SENSOR_DELAY_GAME)) {
            cancelSample("MOTION_UNAVAILABLE", "Sensor registration failed")
            return
        }
        handler.postDelayed(timeout, 1500L)
    }

    fun haptic(effect: String): Boolean {
        if (!foreground) return false
        val now = SystemClock.elapsedRealtime()
        if (now - lastHapticAt < 120L) return false
        val kind = when (effect) {
            "tick" -> if (Build.VERSION.SDK_INT >= 29) VibrationEffect.EFFECT_TICK else -1
            "click" -> if (Build.VERSION.SDK_INT >= 29) VibrationEffect.EFFECT_CLICK else -1
            "heavy" -> if (Build.VERSION.SDK_INT >= 29) VibrationEffect.EFFECT_HEAVY_CLICK else -1
            else -> return false
        }
        val motor = if (Build.VERSION.SDK_INT >= 31) {
            activity.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } ?: return false
        if (!motor.hasVibrator()) return false
        lastHapticAt = now
        val vibration = if (Build.VERSION.SDK_INT >= 29 && kind != -1) {
            VibrationEffect.createPredefined(kind)
        } else {
            val duration = when (effect) {
                "tick" -> 12L
                "heavy" -> 45L
                else -> 22L
            }
            VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        motor.vibrate(vibration)
        return true
    }
}
