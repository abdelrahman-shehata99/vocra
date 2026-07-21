package com.vocra.voice_flutter

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Captures mono 16 kHz PCM16 audio using [MediaRecorder.AudioSource.VOICE_COMMUNICATION] with
 * hardware acoustic echo cancellation and noise suppression attached, when the device supports
 * them (spec §9 — Android side).
 *
 * This is part of the *optional* full-duplex native AEC module. It has been written against the
 * documented Android Audio framework APIs but has not been exercised on a physical device as
 * part of this build — unlike the rest of this SDK, runtime echo-cancellation quality can't be
 * verified without one. [isAvailable] lets the Dart side detect support and fall back to
 * half-duplex when AEC isn't present, per the spec's explicit fallback instruction.
 */
class AecAudioRecorder {
    companion object {
        const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT

        fun isAvailable(): Boolean {
            return AcousticEchoCanceler.isAvailable()
        }
    }

    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private val running = AtomicBoolean(false)

    @SuppressLint("MissingPermission") // caller (Dart side) is responsible for RECORD_AUDIO
    fun start(eventSink: EventChannel.EventSink, uiThreadHandler: (() -> Unit) -> Unit) {
        if (running.get()) return

        val minBufferSize =
            AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (minBufferSize <= 0) {
            throw IllegalStateException("AudioRecord.getMinBufferSize returned $minBufferSize")
        }
        // A few frames' worth of headroom beyond the platform minimum.
        val bufferSize = minBufferSize * 4

        val record =
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize,
            )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw IllegalStateException("AudioRecord failed to initialize")
        }
        audioRecord = record

        if (AcousticEchoCanceler.isAvailable()) {
            echoCanceler = AcousticEchoCanceler.create(record.audioSessionId)?.apply { enabled = true }
        }
        if (NoiseSuppressor.isAvailable()) {
            noiseSuppressor = NoiseSuppressor.create(record.audioSessionId)?.apply { enabled = true }
        }

        running.set(true)
        record.startRecording()

        captureThread =
            thread(start = true, name = "voice_flutter-aec-capture") {
                // ~20ms frames at 16kHz mono 16-bit: 16000 * 0.02 * 2 bytes = 640 bytes.
                val frame = ByteArray(640)
                while (running.get()) {
                    val read = record.read(frame, 0, frame.size)
                    if (read > 0) {
                        val chunk = frame.copyOf(read)
                        uiThreadHandler { eventSink.success(chunk) }
                    }
                }
            }
    }

    fun stop() {
        if (!running.getAndSet(false)) return
        captureThread?.join(500)
        captureThread = null

        audioRecord?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
                // Already stopped — not exceptional during teardown.
            }
            it.release()
        }
        audioRecord = null

        echoCanceler?.release()
        echoCanceler = null
        noiseSuppressor?.release()
        noiseSuppressor = null
    }
}
