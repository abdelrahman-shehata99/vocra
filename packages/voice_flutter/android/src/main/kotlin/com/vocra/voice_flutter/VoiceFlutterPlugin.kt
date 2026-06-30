package com.vocra.voice_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val METHOD_CHANNEL = "voice_flutter/aec_mic"
private const val EVENT_CHANNEL = "voice_flutter/aec_mic/stream"

/**
 * Registers the optional native-AEC mic channels (spec §9, T18). v1's happy path
 * ([FlutterMicSource] via the `record` plugin) does not depend on this class at all — it's only
 * loaded when an app opts into [DuplexMode.fullDuplex] and constructs a `NativeAecMicSource`.
 */
class VoiceFlutterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val recorder = AecAudioRecorder()
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        recorder.stop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(AecAudioRecorder.isAvailable())
            "start" -> {
                val sink = eventSink
                if (sink == null) {
                    result.error("NO_LISTENER", "Subscribe to the event stream before start()", null)
                    return
                }
                try {
                    recorder.start(sink) { action -> mainHandler.post(action) }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("START_FAILED", e.message, null)
                }
            }
            "stop" -> {
                recorder.stop()
                result.success(null)
            }
            "sampleRate" -> result.success(AecAudioRecorder.SAMPLE_RATE)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        recorder.stop()
    }
}
