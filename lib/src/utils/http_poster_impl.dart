import 'dart:convert';
import 'dart:io';

import 'package:flutter_ci_tools/src/utils/http_poster.dart';

/// Production [HttpPoster] backed by `dart:io`'s [HttpClient].
class HttpPosterImpl implements HttpPoster {
  @override
  Future<HttpResponse> postJson(
    Uri url,
    Object body, {
    Duration connectTimeout = const Duration(seconds: 5),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    // curl 会自己读 HTTP_PROXY / HTTPS_PROXY，HttpClient 默认不读。CI 跑在
    // 走代理的内网里时，不补这行就直接连不通。
    client.findProxy = (uri) => HttpClient.findProxyFromEnvironment(uri);
    try {
      return await _post(client, url, body).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpResponse> _post(HttpClient client, Uri url, Object body) async {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return HttpResponse(
      statusCode: response.statusCode,
      body: await response.transform(utf8.decoder).join(),
    );
  }
}
