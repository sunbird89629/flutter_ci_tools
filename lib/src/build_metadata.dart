import 'git_manager.dart';

/// Snapshot of Git and build context collected at the start of a pipeline run.
class BuildMetadata {
  /// Current Git branch name.
  final String branch;

  /// Git user who triggered the build.
  final String gitUser;

  /// Short hash of the HEAD commit.
  final String gitHash;

  /// Formatted list of recent commits for notification messages.
  final String recentCommits;

  /// Body of the latest commit message (used for release notes).
  final String commitBody;

  BuildMetadata({
    required this.branch,
    required this.gitUser,
    required this.gitHash,
    required this.recentCommits,
    required this.commitBody,
  });

  /// Collects metadata from [git] by querying branch, user, hash, and recent commits.
  static Future<BuildMetadata> collect(GitManager git) async {
    final branch = await git.getBranch();
    final gitUser = await git.getCurrentUser();
    final gitHash = await git.getShortHash();
    final recentCommits = await git.getRecentCommits(count: 15);
    final commitBody = await git.getLatestCommitBody();
    return BuildMetadata(
      branch: branch,
      gitUser: gitUser,
      gitHash: gitHash,
      recentCommits: recentCommits,
      commitBody: commitBody,
    );
  }
}
