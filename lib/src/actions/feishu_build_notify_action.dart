import '../utils/shell_runner_impl.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'feishu_notify_action.dart';
import 'pipeline_action.dart';

/// Destination where a build artifact will be uploaded.
///
/// Used to label the standard Feishu build-notification message.
enum DeployTarget {
  /// Pgyer beta distribution platform.
  pgyer('Pgyer'),

  /// Google Play Store.
  googlePlay('Google Play'),

  /// Apple App Store.
  appStore('App Store');

  /// Human-readable deploy target name.
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
  /// Creates a Feishu build notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL.
  /// [target] is the deploy destination (Pgyer, Google Play, etc.).
  /// [downloadUrl] is an optional direct download link included in the message.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.target,
    this.downloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Deploy destination label (Pgyer, Google Play, or App Store).
  final DeployTarget target;

  /// Optional direct download link included in the notification message.
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
      '🚀 ${context.appName} 新版本 ${context.buildNumber} (${target.label})',
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
