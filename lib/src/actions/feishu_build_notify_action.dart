import '../utils/default_shell_runner.dart';
import '../pipeline.dart' show AppPlatform;
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'feishu_notify_action.dart';
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
/// Reads `context.buildName`, `context.buildNumber`,
/// and `context.metadata` to format the message text. Requires
/// `ResolveBuildVersionAction` and `CollectMetadataAction` earlier in the
/// pipeline body.
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.platform,
    required this.target,
    this.downloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String webhookUrl;
  final AppPlatform platform;
  final DeployTarget target;
  final String? downloadUrl;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final message = _formatMessage(context);
    await FeishuNotifyAction(
      webhookUrl: webhookUrl,
      message: message,
      shellRunner: _shellRunner,
    ).run(context);
  }

  String _formatMessage(PipelineContext context) {
    const sep = '──────────────────────────';
    final m = context.metadata;
    final lines = <String>[
      '🚀 ${context.appName} 新版本 ${context.buildNumber} (${platform.label} · ${target.label})',
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
