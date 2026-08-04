import '../context_keys.dart';
import '../pipeline_context.dart';
import '../utils/http_poster.dart';
import 'feishu_notify_action.dart';

/// Sends the standard "new build" message to Feishu.
///
/// Reads `context.buildName`, `ContextKeys.buildNumber` from the context bag,
/// and `context.git` to format the message text. Requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
///
/// Download URLs are read from the context KV bag via [downloadUrlKeys];
/// absent/empty values are skipped. When `null`, no download line is shown.
class FeishuBuildNotifyAction extends FeishuNotifyAction {
  /// Creates a Feishu build notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL.
  /// [target] labels the deploy destination in the message title, e.g.
  /// `'Pgyer'`, `'Google Play'`. Purely cosmetic — it does not affect what
  /// gets uploaded where.
  /// [downloadUrlKeys] are context keys to read download URLs from;
  /// absent/empty values are skipped. `null` means no download line is shown.
  /// [maxAttempts] / [retryDelay] behave as on [FeishuNotifyAction];
  /// see it for the resulting worst-case duration.
  /// [httpPoster] overrides the default [HttpPoster] for testing.
  FeishuBuildNotifyAction({
    required super.webhookUrl,
    required this.target,
    this.downloadUrlKeys,
    super.maxAttempts,
    super.retryDelay,
    super.httpPoster,
  });

  /// Deploy destination label shown in the message title, e.g. `'Pgyer'`.
  final String target;

  /// Context keys to read download URLs from; absent/empty values are skipped.
  /// `null` means no download line is shown.
  final List<String>? downloadUrlKeys;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<String> buildMessage(PipelineContext context) async {
    const sep = '──────────────────────────';
    final git = context.git;
    final branch = await git.getBranch();
    final gitUser = await git.getCurrentUser();
    final gitHash = await git.getShortHash();
    final recentCommits = await git.getRecentCommits(count: 15);
    final commitBody = await git.getLatestCommitBody();
    final lines = <String>[
      '🚀 ${context.appName} 新版本 ${context.get<int>(ContextKeys.buildNumber)} ($target)',
      'branch: $branch  by: $gitUser',
      sep,
      'versionName: ${context.buildName}',
      'versionCode: ${context.get<int>(ContextKeys.buildNumber)}',
      'git_hash:    $gitHash',
    ];
    final urls = downloadUrlKeys == null
        ? const <String>[]
        : downloadUrlKeys!
            .map((k) => context.tryGet<String>(k))
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList();
    if (urls.isNotEmpty) {
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
