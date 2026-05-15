import 'git_manager.dart';

class BuildMetadata {
  final String branch;
  final String gitUser;
  final String gitHash;
  final String recentCommits;
  final String commitBody;

  BuildMetadata({
    required this.branch,
    required this.gitUser,
    required this.gitHash,
    required this.recentCommits,
    required this.commitBody,
  });

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
