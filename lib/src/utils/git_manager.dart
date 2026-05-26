import 'git_manager_impl.dart';

/// Interface for Git operations used by the build pipeline.
///
/// Implementations can be swapped for testing via dependency injection.
abstract class GitManager {
  /// Default singleton instance.
  static GitManager instance = GitManagerImpl();

  /// Throws [GitException] if the working tree has uncommitted changes.
  Future<void> checkClean();

  /// Runs `git reset HEAD --hard`.
  Future<void> resetHard();

  /// Runs `git clean -fd` to remove untracked files.
  Future<void> clean();

  /// Restores the workspace by calling [resetHard] then [clean].
  Future<void> restoreWorkspace();

  /// Returns the short hash of HEAD (e.g. `"abc1234"`).
  Future<String> getShortHash();

  /// Returns the last [count] commits in `--oneline` format.
  Future<String> getRecentCommits({int count = 10});

  /// Returns the current branch name.
  Future<String> getBranch();

  /// Returns the Git user name from `git config`, falling back to CI environment variables.
  Future<String> getCurrentUser();

  /// Returns the body of the latest commit message.
  Future<String> getLatestCommitBody();
}
