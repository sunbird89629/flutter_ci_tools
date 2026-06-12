import 'dart:convert';

import '../utils/shell_runner_impl.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Sends an arbitrary text message to a Feishu (Lark) webhook.
///
/// For standard build notifications prefer [FeishuBuildNotifyAction].
class FeishuNotifyAction extends PipelineAction {
  /// Creates a Feishu notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL.
  /// [message] is the plain-text message body to send.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  FeishuNotifyAction({
    required this.webhookUrl,
    required this.message,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Plain-text message body to send.
  final String message;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    context.logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });
    final result = await _shellRunner.runAndCapture('curl', [
      '-X',
      'POST',
      '-H',
      'Content-Type: application/json',
      '-d',
      jsonMessage,
      webhookUrl,
    ]);
    if (result.exitCode == 0) {
      context.logger.success('Feishu notification sent.');
    } else {
      context.logger.error('Failed to send Feishu notification: ${result.stderr}');
    }
  }
}
