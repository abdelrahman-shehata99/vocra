import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A controllable fake [WebSocketChannel] for testing [DeepgramStt] without
/// a real socket. [emit] pushes a server->client message; [sink] records
/// what the transport sent.
class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();

  @override
  final FakeWebSocketSink sink = FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future<void>.value();

  void emit(Object message) => _incoming.add(message);

  void emitError(Object error) => _incoming.addError(error);

  Future<void> closeIncoming() => _incoming.close();
}

class FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = [];
  int? closeCode;
  String? closeReason;
  bool isClosed = false;
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    isClosed = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  Future get done => _doneCompleter.future;
}
