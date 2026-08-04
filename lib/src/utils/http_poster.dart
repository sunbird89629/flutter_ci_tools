/// The part of an HTTP response this package cares about.
class HttpResponse {
  /// Creates an HTTP response.
  const HttpResponse({required this.statusCode, required this.body});

  /// HTTP status code, e.g. 200.
  final int statusCode;

  /// Response body decoded as UTF-8.
  final String body;

  /// Whether [statusCode] is in the 2xx range.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Sends HTTP requests. Injected into actions so tests can fake the network.
abstract class HttpPoster {
  /// POSTs [body] as JSON to [url] and returns the response.
  ///
  /// [body] is JSON-encoded by the implementation, which also sets
  /// `Content-Type: application/json`.
  ///
  /// [connectTimeout] bounds establishing the connection; [timeout] bounds the
  /// whole request including reading the body. Throws on network failure,
  /// timeout, or TLS error — a non-2xx status is *not* an error here, it comes
  /// back as an [HttpResponse] so callers can inspect the body.
  Future<HttpResponse> postJson(
    Uri url,
    Object body, {
    Duration connectTimeout,
    Duration timeout,
  });
}
