import 'dart:convert';

import '../default_shell_runner.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Sends a text message to a Feishu (Lark) webhook.
///
/// Reads: `config.feishuWebhookUrl`, `notification_message` (String)
class FeishuNotifyAction extends PipelineAction<void> {
  /// Creates a Feishu notify action with an optional [shellRunner] for testing.
  FeishuNotifyAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final webhookUrl = context.config.feishuWebhookUrl!;
    final message = context.get<String>('notification_message');

    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      "msg_type": "text",
      "content": {"text": message},
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
      Logger.success('Feishu notification sent.');
    } else {
      Logger.error('Failed to send Feishu notification: ${result.stderr}');
    }
  }
}
