import 'dart:io';

import 'package:flutter_ci_tools/src/default_shell_runner.dart';

import 'exceptions.dart';
import 'logger.dart';
import 'shell_runner.dart';

/// Interface for Git operations used by the build pipeline.
///
/// Implementations can be swapped for testing via dependency injection.
abstract class GitManager {
  /// Default singleton instance.
  static GitManager instance = DefaultGitManager();

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

/// Default [GitManager] implementation using [ShellRunner] to execute Git commands.
class DefaultGitManager implements GitManager {
  /// Creates a [DefaultGitManager] with an optional [shellRunner].
  DefaultGitManager({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  Future<void> checkClean() async {
    if (Platform.environment['CIRCLECI'] == 'true') {
      Logger.info('Skipping git check in CI environment.');
      return;
    }
    Logger.info('Checking for uncommitted changes...');
    final result = await _runGitCommand(['status', '--porcelain']);
    if (result.stdout.toString().trim().isNotEmpty) {
      Logger.error(
        'Uncommitted changes detected. Please commit or stash them before running this script.',
      );
      Logger.info('Changes:\n${result.stdout}');
      throw GitException(
        'Uncommitted changes detected',
        result.exitCode,
      );
    }
    Logger.success('Git status is clean.');
  }

  @override
  Future<void> resetHard() async {
    await _shellRunner.run('git', ['reset', 'HEAD', '--hard']);
  }

  @override
  Future<void> clean() async {
    await _shellRunner.run('git', ['clean', '-fd']);
  }

  @override
  Future<void> restoreWorkspace() async {
    await resetHard();
    await clean();
  }

  @override
  Future<String> getShortHash() async {
    final result = await _runGitCommand(['rev-parse', '--short', 'HEAD']);
    return result.stdout.toString().trim();
  }

  @override
  Future<String> getRecentCommits({int count = 10}) async {
    final result = await _runGitCommand([
      'log',
      '--oneline',
      '--no-merges',
      '-n',
      '$count',
    ]);
    return result.stdout.toString().trim();
  }

  @override
  Future<String> getBranch() async {
    final result = await _runGitCommand(['rev-parse', '--abbrev-ref', 'HEAD']);
    return result.stdout.toString().trim();
  }

  @override
  Future<String> getCurrentUser() async {
    final userResult = await _shellRunner.runAndCapture('git', [
      'config',
      '--get',
      'user.name',
    ]);
    final name = userResult.stdout.toString().trim();
    if (name.isNotEmpty) return name;
    return Platform.environment['CIRCLE_USERNAME'] ?? 'ci';
  }

  @override
  Future<String> getLatestCommitBody() async {
    final result = await _runGitCommand(['log', '-1', '--pretty=%b']);
    return result.stdout.toString().trim();
  }

  Future<ShellResult> _runGitCommand(List<String> args) async {
    final result = await _shellRunner.runAndCapture('git', args);
    if (result.exitCode != 0) {
      Logger.error('Git command failed: git ${args.join(' ')}');
      Logger.error('Error: ${result.stderr}');
      throw GitException(
        'git ${args.join(' ')} failed',
        result.exitCode,
      );
    }
    return result;
  }
}
