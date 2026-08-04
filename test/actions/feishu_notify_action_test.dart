import 'dart:async';
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/feishu_notify_action.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/http_poster.dart';
import 'package:test/test.dart';

class _FakeHttpPoster implements HttpPoster {
  _FakeHttpPoster({this.results = const []});

  /// 依次返回的结果；用完后重复最后一个。空列表表示一律返回 200。
  /// 元素是 [HttpResponse] 时按响应返回，是 [Object] 异常时抛出。
  final List<Object> results;

  int calls = 0;
  Uri? lastUrl;
  Object? lastBody;
  Duration? lastConnectTimeout;
  Duration? lastTimeout;

  @override
  Future<HttpResponse> postJson(
    Uri url,
    Object body, {
    Duration connectTimeout = const Duration(seconds: 5),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastUrl = url;
    lastBody = body;
    lastConnectTimeout = connectTimeout;
    lastTimeout = timeout;
    final index = calls;
    calls++;
    if (results.isEmpty) {
      return const HttpResponse(statusCode: 200, body: '{"code":0}');
    }
    final result = results[index < results.length ? index : results.length - 1];
    if (result is HttpResponse) return result;
    throw result;
  }
}

PipelineContext _context() =>
    PipelineContext(appName: 'TestApp', seedBuildNumber: 1000);

FeishuNotifyAction _action(
  _FakeHttpPoster http, {
  int maxAttempts = 3,
  String url = 'https://open.feishu.cn/hook',
}) =>
    FeishuNotifyAction(
      webhookUrl: url,
      message: 'hello world',
      maxAttempts: maxAttempts,
      retryDelay: Duration.zero,
      httpPoster: http,
    );

void main() {
  test('FeishuNotifyAction posts the given message to the configured webhook',
      () async {
    final http = _FakeHttpPoster();
    final action = _action(http);

    await action.run(_context());

    expect(action.name, 'Send Feishu Notification');
    expect(http.lastUrl, Uri.parse('https://open.feishu.cn/hook'));
    expect(http.lastBody, {
      'msg_type': 'text',
      'content': {'text': 'hello world'},
    });
    expect(http.calls, 1, reason: '成功时不该重试');
  });

  test('带上超时，避免挑中坏节点后干等', () async {
    final http = _FakeHttpPoster();

    await _action(http).run(_context());

    expect(http.lastConnectTimeout, const Duration(seconds: 5));
    expect(http.lastTimeout, const Duration(seconds: 15));
  });

  test('网络异常与超时都当成可重试的失败，不外抛', () async {
    for (final error in [
      const SocketException('connection timed out'),
      TimeoutException('too slow'),
    ]) {
      final http = _FakeHttpPoster(results: [error]);

      await _action(http, maxAttempts: 3).run(_context());

      expect(http.calls, 3, reason: '$error 应重试到上限');
    }
  });

  test('非 2xx 状态码视为失败并重试', () async {
    final http = _FakeHttpPoster(
      results: const [HttpResponse(statusCode: 500, body: 'oops')],
    );

    await _action(http, maxAttempts: 2).run(_context());

    expect(http.calls, 2);
  });

  test('前几次失败、后续成功时停止重试', () async {
    final http = _FakeHttpPoster(
      results: const [
        HttpResponse(statusCode: 502, body: ''),
        HttpResponse(statusCode: 200, body: '{"code":0}'),
      ],
    );

    await _action(http, maxAttempts: 3).run(_context());

    expect(http.calls, 2, reason: '成功后不该继续重试');
  });

  test('HTTP 200 但业务码非零视为失败并重试', () async {
    // 飞书对 token 失效之类的错误返回 200 + 非零 code，只看状态码会误判成功
    final http = _FakeHttpPoster(
      results: const [
        HttpResponse(
          statusCode: 200,
          body: '{"code":9499,"msg":"bad request"}',
        ),
      ],
    );

    await _action(http, maxAttempts: 2).run(_context());

    expect(http.calls, 2);
  });

  test('响应不是 JSON 时不误报失败', () async {
    final http = _FakeHttpPoster(
      results: const [HttpResponse(statusCode: 200, body: 'ok')],
    );

    await _action(http, maxAttempts: 3).run(_context());

    expect(http.calls, 1);
  });

  test('webhook 未配置时直接跳过，不发请求', () async {
    final http = _FakeHttpPoster();

    await _action(http, url: '  ').run(_context());

    expect(http.calls, 0);
  });
}
