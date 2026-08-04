import 'dart:convert';

import '../utils/shell_runner_impl.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Sends an arbitrary text message to a Feishu (Lark) webhook.
///
/// For standard build notifications prefer [FeishuBuildNotifyAction].
///
/// **This action never throws.** A notification is a side channel — losing it
/// must not fail a build that already produced its artifacts. Failures are
/// logged and the pipeline continues.
class FeishuNotifyAction extends PipelineAction {
  /// Creates a Feishu notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL. Empty means "skip silently".
  /// [message] is the plain-text message body to send.
  /// [maxAttempts] is how many times to try before giving up (default: 3).
  /// [retryDelay] is the pause between attempts (default: 3s).
  ///
  /// 最坏耗时 ≈ `maxAttempts × 15s + (maxAttempts - 1) × retryDelay`
  /// （默认约 51 秒）。飞书长时间不可用时不想让流水线干等这么久，就调小
  /// [maxAttempts]。
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  FeishuNotifyAction({
    required this.webhookUrl,
    required this.message,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 3),
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Plain-text message body to send.
  final String message;

  /// Maximum number of attempts before giving up.
  final int maxAttempts;

  /// Pause between attempts.
  final Duration retryDelay;

  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    _shellRunner.setLogger(context.logger);
    final log = context.logger;

    if (webhookUrl.trim().isEmpty) {
      log.info('Feishu webhook not configured — skipping notification.');
      return;
    }

    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });

    log.info('Sending Feishu notification...');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        log.info('Retrying Feishu notification ($attempt/$maxAttempts)...');
        await Future.delayed(retryDelay);
      }

      final result = await _shellRunner.runAndCapture('curl', [
        // 静默进度条但保留错误输出，否则进度表会糊进 CI 日志
        '-sS',
        // HTTP 4xx/5xx 时以非零码退出；默认 curl 会把它当成功
        '-f',
        // open.feishu.cn 有十几个 GSLB 节点，挑中不健康的会一直干等到系统默认
        // 超时。这里快速失败，换节点交给外层重试——curl 自己的 --retry 也能换 IP，
        // 但它是静默的，而且会和外层相乘（3×3=9 次、最坏 2.5 分钟），故不用。
        '--connect-timeout', '5',
        '--max-time', '15',
        '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-d', jsonMessage,
        webhookUrl,
      ]);

      final failure = _failureReason(result);
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
  /// 只看退出码不够：飞书对业务错误（token 失效、机器人被移除、限流）返回的是
  /// **HTTP 200** 加一个非零的 `code`，curl 会当成功。
  String? _failureReason(ShellResult result) {
    if (result.exitCode != 0) {
      final stderr = result.stderr.trim();
      return stderr.isEmpty ? 'curl exited with ${result.exitCode}' : stderr;
    }

    final body = result.stdout.trim();
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
