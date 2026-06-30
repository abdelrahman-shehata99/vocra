import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A [HttpClientAdapter] whose response is produced by a test-supplied
/// handler — lets provider-adapter tests drive Dio with canned
/// success/error fixtures instead of hitting the real network.
class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody sseResponseBody(
  List<String> chunks, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  final stream = Stream.fromIterable(
    chunks.map((c) => Uint8List.fromList(utf8.encode(c))),
  );
  return ResponseBody(
    stream,
    statusCode,
    headers:
        headers ??
        {
          'content-type': ['text/event-stream'],
        },
  );
}

ResponseBody errorResponseBody(
  int statusCode, {
  Map<String, List<String>>? headers,
  String body = '',
}) {
  final stream = Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(body)));
  return ResponseBody(stream, statusCode, headers: headers ?? {});
}

ResponseBody bytesResponseBody(
  List<int> bytes, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody(
    Stream.value(Uint8List.fromList(bytes)),
    statusCode,
    headers: headers ?? {},
  );
}
