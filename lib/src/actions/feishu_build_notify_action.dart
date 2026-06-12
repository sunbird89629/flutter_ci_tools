import '../context_keys.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import '../utils/shell_runner_impl.dart';
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
/// Reads `context.buildName`, `ContextKeys.buildNumber` from the context bag,
/// and `context.git` to format the message text. Requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
class FeishuBuildNotifyAction extends PipelineAction<void> {
  /// Creates a Feishu build notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL.
  /// [target] is the deploy destination (Pgyer, Google Play, etc.).
  /// [downloadUrl] is an optional single download link included in the message.
  /// [downloadUrls] is an optional list of download links; when provided,
  /// overrides [downloadUrl].
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.target,
    this.downloadUrl,
    this.downloadUrls,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Deploy destination label (Pgyer, Google Play, or App Store).
  final DeployTarget target;

  /// Optional single download link included in the notification message.
  final String? downloadUrl;

  /// Optional list of download links; when provided, overrides [downloadUrl].
  final List<String>? downloadUrls;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final message = await _formatMessage(context);
    await FeishuNotifyAction(
      webhookUrl: webhookUrl,
      message: message,
      shellRunner: _shellRunner,
    ).run(context);
  }

  Future<String> _formatMessage(PipelineContext context) async {
    const sep = '──────────────────────────';
    final git = context.git;
    final branch = await git.getBranch();
    final gitUser = await git.getCurrentUser();
    final gitHash = await git.getShortHash();
    final recentCommits = await git.getRecentCommits(count: 15);
    final commitBody = await git.getLatestCommitBody();
    final lines = <String>[
      '🚀 ${context.appName} 新版本 ${context.get<int>(ContextKeys.buildNumber)} (${target.label})',
      'branch: $branch  by: $gitUser',
      sep,
      'versionName: ${context.buildName}',
      'versionCode: ${context.get<int>(ContextKeys.buildNumber)}',
      'git_hash:    $gitHash',
    ];
    final urls = downloadUrls ?? (downloadUrl != null ? [downloadUrl!] : null);
    if (urls != null && urls.isNotEmpty) {
      lines.add(sep);
      if (urls.length == 1) {
        lines.add('🔗 下载: ${urls.single}');
      } else {
        lines.add('🔗 下载链接:');
        for (var i = 0; i < urls.length; i++) {
          lines.add('  ${i + 1}. ${urls[i]}');
        }
      }
    }
    lines
      ..add(sep)
      ..add('最近提交:')
      ..add(recentCommits);
    if (commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(commitBody);
    }
    return lines.join('\n');
  }
}
