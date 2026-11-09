package dev.chappy.chappy_player

import android.os.SystemClock
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import kotlin.math.abs

/**
 * Offline, frame-only detector for consented foreground recording.
 *
 * Samples the Y (luminance) plane at 16x12 locations at most four times per
 * second. No frames or thumbnails leave the Android process, are stored, or
 * reach mini-app JavaScript. Global brightness offsets are subtracted so a
 * uniform auto-exposure change is less likely to count as subject motion.
 */
internal class NativeMotionAnalyzer(
    private val sensitivity: Int,
    private val onSample: (changedPercent: Int, moving: Boolean, baseline: Boolean) -> Unit,
    private val onFailure: () -> Unit,
) : ImageAnalysis.Analyzer {
    private var lastSampleMs = 0L
    private var previous: IntArray? = null
    private val columns = 16
    private val rows = 12

    override fun analyze(image: ImageProxy) {
        try {
            val now = SystemClock.elapsedRealtime()
            if (now - lastSampleMs < 250L) return
            lastSampleMs = now
            val width = image.width
            val height = image.height
            if (width <= 0 || height <= 0 || image.planes.isEmpty()) {
                onFailure()
                return
            }
            val plane = image.planes[0]
            val buffer = plane.buffer
            val rowStride = plane.rowStride
            val pixelStride = plane.pixelStride
            val current = IntArray(columns * rows)
            for (y in 0 until rows) {
                val py = ((2 * y + 1) * height / (2 * rows)).coerceIn(0, height - 1)
                for (x in 0 until columns) {
                    val px = ((2 * x + 1) * width / (2 * columns)).coerceIn(0, width - 1)
                    val offset = py * rowStride + px * pixelStride
                    if (offset < 0 || offset >= buffer.limit()) {
                        onFailure()
                        return
                    }
                    current[y * columns + x] = buffer.get(offset).toInt() and 0xff
                }
            }
            val last = previous
            previous = current
            if (last == null) {
                onSample(0, false, false)
                return
            }
            val meanNow = current.sum().toDouble() / current.size
            val meanOld = last.sum().toDouble() / last.size
            // Quantized spatial change after exposure correction.
            var changed = 0
            var residualTotal = 0.0
            for (i in current.indices) {
                val residual = abs((current[i] - meanNow) - (last[i] - meanOld))
                residualTotal += residual
                if (residual >= 12.0) changed++
            }
            val changedPercent = ((changed * 100.0) / current.size)
                .toInt().coerceIn(0, 100)
            // High sensitivity -> fewer affected image regions are required.
            val requiredPercent = 19 - sensitivity.coerceIn(0, 100) * 14 / 100
            val moving = changedPercent >= requiredPercent &&
                residualTotal / current.size >= 3.0
            onSample(changedPercent, moving, true)
        } catch (_: Exception) {
            // Analysis failures must never silently treat missing frames as
            // "no motion" and auto-stop a valid recording.
            onFailure()
        } finally {
            image.close() // Mandatory: never stall the other CameraX use cases.
        }
    }
}
