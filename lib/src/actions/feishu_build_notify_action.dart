import 'dart:convert';

import '../default_shell_runner.dart';
import '../logger.dart';
import '../pipeline.dart' show AppPlatform;
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Destination where a build artifact will be uploaded.
///
/// Used to label the standard Feishu build-notification message.
enum DeployTarget {
  pgyer('Pgyer'),
  googlePlay('Google Play'),
  appStore('App Store');

  final String label;
  const DeployTarget(this.label);
}

/// Sends the standard "new build" message to Feishu.
///
/// Reads `config.feishuWebhookUrl` and uses `config.appName`, `buildNumber`,
/// and `metadata` from [PipelineContext] to format the message text.
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({
    required this.platform,
    required this.target,
    this.downloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final AppPlatform platform;
  final DeployTarget target;
  final String? downloadUrl;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final message = _formatMessage(context);
    final webhookUrl = context.config.feishuWebhookUrl!;
    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });
    Logger.info('Sending Feishu notification...');
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

  String _formatMessage(PipelineContext context) {
    const sep = '──────────────────────────';
    final m = context.metadata;
    final lines = <String>[
      '🚀 ${context.config.appName} 新版本 ${context.buildNumber} (${platform.label} · ${target.label})',
      'branch: ${m.branch}  by: ${m.gitUser}',
      sep,
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'git_hash:    ${m.gitHash}',
    ];
    if (downloadUrl != null) {
      lines
        ..add(sep)
        ..add('🔗 下载: $downloadUrl');
    }
    lines
      ..add(sep)
      ..add('最近提交:')
      ..add(m.recentCommits);
    if (m.commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(m.commitBody);
    }
    return lines.join('\n');
  }
}
