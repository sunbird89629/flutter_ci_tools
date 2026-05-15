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

  static Future<BuildMetadata> collect() async {
    final results = await Future.wait([
      GitManager.getBranch(),
      GitManager.getCurrentUser(),
      GitManager.getShortHash(),
      GitManager.getRecentCommits(count: 15),
      GitManager.getLatestCommitBody(),
    ]);
    return BuildMetadata(
      branch: results[0],
      gitUser: results[1],
      gitHash: results[2],
      recentCommits: results[3],
      commitBody: results[4],
    );
  }
}
