import 'dart:io';

import 'package:flutter_ci_tools/src/utils/shell_runner_impl.dart';

import 'exceptions.dart';
import 'git_manager.dart';
import 'logger.dart';
import 'shell_runner.dart';

/// Production [GitManager] implementation using [ShellRunner] to execute Git commands.
class GitManagerImpl implements GitManager {
  /// Creates a [GitManagerImpl] with an optional [shellRunner] and [logger].
  GitManagerImpl({ShellRunner? shellRunner, Logger? logger})
      : _shellRunner = shellRunner ?? ShellRunnerImpl(),
        logger = logger ?? Logger.silent();

  final ShellRunner _shellRunner;
  Logger logger;

  @override
  Future<void> checkClean() async {
    if (Platform.environment['CIRCLECI'] == 'true') {
      logger.info('Skipping git check in CI environment.');
      return;
    }
    logger.info('Checking for uncommitted changes...');
    final result = await _runGitCommand(['status', '--porcelain']);
    if (result.stdout.toString().trim().isNotEmpty) {
      logger.error(
        'Uncommitted changes detected. Please commit or stash them before running this script.',
      );
      logger.info('Changes:\n${result.stdout}');
      throw GitException(
        'Uncommitted changes detected',
        result.exitCode,
      );
    }
    logger.success('Git status is clean.');
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
      logger.error('Git command failed: git ${args.join(' ')}');
      logger.error('Error: ${result.stderr}');
      throw GitException(
        'git ${args.join(' ')} failed',
        result.exitCode,
      );
    }
    return result;
  }
}
