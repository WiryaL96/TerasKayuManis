import 'dart:async';

import 'package:http/http.dart' as http;

/// Fail inside the SDK transport so late authentication responses never reach
/// GoTrue's session installation code. Bound both headers and entire body.
class DeadlineClient extends http.BaseClient {
  DeadlineClient(this.inner, {this.timeout = const Duration(seconds: 15)});
  final http.Client inner;
  final Duration timeout;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.followRedirects = false;
    final watch = Stopwatch()..start();
    final response = await inner.send(request).timeout(timeout);
    final remaining = timeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Authentication timed out');
    }
    final bytes = await _bounded(response.stream).timeout(remaining);
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
      contentLength: bytes.length,
    );
  }

  @override
  void close() => inner.close();

  Future<List<int>> _bounded(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('Authentication response too large');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }
}
