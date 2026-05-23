import 'dart:convert';

import '../default_shell_runner.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Sends an arbitrary text message to a Feishu (Lark) webhook.
///
/// For standard build notifications prefer [FeishuBuildNotifyAction].
class FeishuNotifyAction extends PipelineAction<void> {
  FeishuNotifyAction({
    required this.message,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String message;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final webhookUrl = context.config.feishuWebhookUrl!;
    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });
    final result = await _shellRunner.runAndCapture('curl', [
      '-X', 'POST',
      '-H', 'Content-Type: application/json',
      '-d', jsonMessage,
      webhookUrl,
    ]);
    if (result.exitCode == 0) {
      Logger.success('Feishu notification sent.');
    } else {
      Logger.error('Failed to send Feishu notification: ${result.stderr}');
    }
  }
}
