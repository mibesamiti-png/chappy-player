package dev.chappy.chappy_player

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * Foreground-only AudioRecord capture for the offline mini-app microphone API.
 *
 * No PCM is written to a file, network, or diagnostic log. A worker thread
 * reduces a microphone buffer to RMS and 64 coarse amplitude envelopes.
 * AudioRecord has a shorter life than the Activity; onPause always stops it.
 */
class NativeMicCapture {
    private val lock = Any()
    @Volatile private var active: Session? = null
    @Volatile private var lastError: String? = null

    private class Session(
        val recorder: AudioRecord,
        val sampleRate: Int,
        val source: String
    ) {
        val running = AtomicBoolean(true)
        @Volatile var rms: Double = 0.0
        @Volatile var envelopes: List<Double> = List(64) { 0.0 }
        @Volatile var framesRead: Long = 0
        @Volatile var error: String? = null
    }

    /** Must be called only after the Android RECORD_AUDIO check and UI consent. */
    @SuppressLint("MissingPermission")
    fun start(): Map<String, Any> {
        synchronized(lock) {
            if (active != null) throw IllegalStateException("NATIVE_MIC_BUSY")
            var chosen: Session? = null
            var failure = "AUDIO_RECORD_UNAVAILABLE"
            for ((rate, sourceId, sourceName) in listOf(
                Triple(16000, MediaRecorder.AudioSource.MIC, "mic"),
                Triple(48000, MediaRecorder.AudioSource.MIC, "mic"),
                Triple(16000, MediaRecorder.AudioSource.VOICE_RECOGNITION, "voice_recognition")
            )) {
                val minBytes = AudioRecord.getMinBufferSize(
                    rate, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                if (minBytes <= 0) continue
                var recorder: AudioRecord? = null
                try {
                    recorder = AudioRecord(
                        sourceId, rate, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, maxOf(minBytes, 4096)
                    )
                    if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                        failure = "AUDIO_RECORD_NOT_INITIALIZED"
                        recorder.release()
                        continue
                    }
                    recorder.startRecording()
                    if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                        failure = "AUDIO_RECORD_NOT_RECORDING"
                        recorder.release()
                        continue
                    }
                    chosen = Session(recorder, rate, sourceName)
                    break
                } catch (_: SecurityException) {
                    recorder?.release()
                    throw SecurityException("RECORD_AUDIO_PERMISSION_MISSING")
                } catch (_: Exception) {
                    failure = "AUDIO_RECORD_START_FAILED"
                    try { recorder?.release() } catch (_: Exception) {}
                }
            }
            val session = chosen ?: throw IllegalStateException(failure)
            lastError = null
            active = session
            Thread({ captureLoop(session) }, "chappy-microphone-level").apply {
                isDaemon = true
                start()
            }
            return mapOf(
                "running" to true, "sampleRate" to session.sampleRate,
                "channels" to 1, "source" to session.source
            )
        }
    }

    private fun captureLoop(session: Session) {
        val pcm = ShortArray(1024)
        try {
            while (session.running.get()) {
                val count = session.recorder.read(
                    pcm, 0, pcm.size, AudioRecord.READ_BLOCKING
                )
                if (!session.running.get()) break
                if (count < 0) {
                    session.error = "AUDIO_RECORD_READ_ERROR"
                    break
                }
                if (count == 0) continue
                var sumSquares = 0.0
                val envelope = ArrayList<Double>(64)
                for (bucket in 0 until 64) {
                    val first = bucket * count / 64
                    val end = (bucket + 1) * count / 64
                    var bucketSquares = 0.0
                    for (i in first until end) {
                        val v = pcm[i].toDouble() / 32768.0
                        val power = v * v
                        sumSquares += power
                        bucketSquares += power
                    }
                    envelope.add(sqrt(bucketSquares / maxOf(1, end - first))
                        .coerceIn(0.0, 1.0))
                }
                session.rms = sqrt(sumSquares / count).coerceIn(0.0, 1.0)
                session.envelopes = envelope
                session.framesRead += count
            }
        } catch (_: Exception) {
            if (session.running.get()) session.error = "AUDIO_RECORD_WORKER_ERROR"
        } finally {
            session.running.set(false)
            try { session.recorder.stop() } catch (_: Exception) {}
            try { session.recorder.release() } catch (_: Exception) {}
            synchronized(lock) {
                if (active === session) {
                    lastError = session.error
                    active = null
                }
            }
        }
    }

    /** The values are coarse amplitude envelopes, never raw PCM samples. */
    fun levels(): Map<String, Any> {
        val session = active
        return if (session != null && session.running.get()) {
            mapOf(
                "running" to true, "rms" to session.rms,
                "levels" to session.envelopes, "framesRead" to session.framesRead,
                "sampleRate" to session.sampleRate, "source" to session.source
            )
        } else {
            mapOf(
                "running" to false, "rms" to 0.0,
                "levels" to emptyList<Double>(),
                "framesRead" to 0L, "error" to (lastError ?: "STOPPED")
            )
        }
    }

    fun stop() {
        val session = active ?: return
        session.running.set(false)
        try { session.recorder.stop() } catch (_: Exception) {}
        // The capture worker owns release() and clears active in its finally.
    }
}
