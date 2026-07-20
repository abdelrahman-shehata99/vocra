import Flutter
import UIKit

/// Registers the optional native-AEC mic channels (spec §9, T18). v1's
/// happy path (`FlutterMicSource` via the `record` plugin) does not depend
/// on this class at all — it's only loaded when an app opts into
/// full-duplex mode and constructs a `NativeAecMicSource`.
public class VoiceFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let engine = AecAudioEngine()
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = VoiceFlutterPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "voice_flutter/aec_mic",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "voice_flutter/aec_mic/stream",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(AecAudioEngine.isAvailable())
        case "start":
            guard eventSink != nil else {
                result(
                    FlutterError(
                        code: "NO_LISTENER",
                        message: "Subscribe to the event stream before start()",
                        details: nil
                    )
                )
                return
            }
            do {
                try engine.start { [weak self] data in
                    // Hop to the main thread: this closure is invoked from
                    // AVAudioEngine's real-time audio thread, but
                    // FlutterEventSink must only be called on the main
                    // thread.
                    DispatchQueue.main.async {
                        self?.eventSink?(FlutterStandardTypedData(bytes: data))
                    }
                }
                result(nil)
            } catch {
                result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
            }
        case "stop":
            engine.stop()
            result(nil)
        case "sampleRate":
            result(Int(AecAudioEngine.sampleRate))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        engine.stop()
        return nil
    }
}
