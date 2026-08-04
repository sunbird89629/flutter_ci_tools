import 'dart:convert';

import '../pipeline_context.dart';
import '../utils/http_poster.dart';
import '../utils/http_poster_impl.dart';
import 'pipeline_action.dart';

/// Sends an arbitrary text message to a Feishu (Lark) webhook.
///
/// For standard build notifications prefer `FeishuBuildNotifyAction`.
///
/// Subclasses that need to compose the text from the pipeline context override
/// [buildMessage] instead of passing a fixed [message].
///
/// **This action never throws.** A notification is a side channel — losing it
/// must not fail a build that already produced its artifacts. Failures are
/// logged and the pipeline continues.
class FeishuNotifyAction extends PipelineAction {
  /// Creates a Feishu notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL. Empty means "skip silently".
  /// [message] is the plain-text message body to send; subclasses that build
  /// the text from the context leave it empty and override [buildMessage].
  /// [maxAttempts] is how many times to try before giving up (default: 3).
  /// [retryDelay] is the pause between attempts (default: 3s).
  ///
  /// 最坏耗时 ≈ `maxAttempts × 15s + (maxAttempts - 1) × retryDelay`
  /// （默认约 51 秒）。飞书长时间不可用时不想让流水线干等这么久，就调小
  /// [maxAttempts]。
  /// [httpPoster] overrides the default [HttpPoster] for testing.
  FeishuNotifyAction({
    required this.webhookUrl,
    this.message = '',
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 3),
    HttpPoster? httpPoster,
  }) : _http = httpPoster ?? HttpPosterImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Plain-text message body to send. Empty when [buildMessage] is overridden.
  final String message;

  /// Maximum number of attempts before giving up.
  final int maxAttempts;

  /// Pause between attempts.
  final Duration retryDelay;

  final HttpPoster _http;

  /// open.feishu.cn 有十几个 GSLB 节点，挑中不健康的会一直干等到系统默认超时。
  /// 这里快速失败，换节点交给外层重试。
  static const _connectTimeout = Duration(seconds: 5);
  static const _requestTimeout = Duration(seconds: 15);

  @override
  String get name => 'Send Feishu Notification';

  /// Builds the text to send. Defaults to the fixed [message].
  ///
  /// Override in a subclass to compose the body from [context] — the retry and
  /// error handling in [run] then apply unchanged.
  Future<String> buildMessage(PipelineContext context) async => message;

  @override
  Future<void> run(PipelineContext context) async {
    final log = context.logger;

    if (webhookUrl.trim().isEmpty) {
      log.info('Feishu webhook not configured — skipping notification.');
      return;
    }

    final payload = {
      'msg_type': 'text',
      'content': {'text': await buildMessage(context)},
    };

    log.info('Sending Feishu notification...');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        log.info('Retrying Feishu notification ($attempt/$maxAttempts)...');
        await Future.delayed(retryDelay);
      }

      String? failure;
      try {
        final response = await _http.postJson(
          Uri.parse(webhookUrl.trim()),
          payload,
          connectTimeout: _connectTimeout,
          timeout: _requestTimeout,
        );
        failure = _failureReason(response);
      } catch (e) {
        // 通知是旁路，任何异常（超时、DNS、TLS、URL 格式）都只记录不外抛
        failure = e.toString();
      }

      if (failure == null) {
        log.success('Feishu notification sent.');
        return;
      }
      log.error(
        'Feishu notification attempt $attempt/$maxAttempts failed: $failure',
      );
    }

    log.error(
      'Feishu notification failed after $maxAttempts attempts. '
      'Build result is unaffected.',
    );
  }

  /// 返回失败原因；真正成功时返回 `null`。
  ///
  /// 只看状态码不够：飞书对业务错误（token 失效、机器人被移除、限流）返回的是
  /// **HTTP 200** 加一个非零的 `code`。
  String? _failureReason(HttpResponse response) {
    final body = response.body.trim();
    if (!response.isSuccess) {
      return body.isEmpty
          ? 'HTTP ${response.statusCode}'
          : 'HTTP ${response.statusCode}: $body';
    }
    if (body.isEmpty) return null;

    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final code = decoded['code'];
      if (code is int && code != 0) {
        return 'webhook rejected the message '
            '(code=$code, msg=${decoded['msg']})';
      }
    } catch (_) {
      // 响应不是 JSON —— 判断不了，不误报失败
    }
    return null;
  }
}
