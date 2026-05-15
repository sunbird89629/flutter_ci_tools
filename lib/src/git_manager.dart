import 'dart:io';

import 'logger.dart';
import 'shell_runner.dart';

class GitManager {
  GitManager._();

  static Future<void> checkClean() async {
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
      exit(1);
    }
    Logger.success('Git status is clean.');
  }

  static Future<void> resetHard() async {
    await _runGitCommand(['reset', 'HEAD', '--hard']);
  }

  static Future<void> clean() async {
    await _runGitCommand(['clean', '-fd']);
  }

  static Future<void> restoreWorkspace() async {
    await resetHard();
    await clean();
  }

  static Future<String> getShortHash() async {
    final result = await _runGitCommand(['rev-parse', '--short', 'HEAD']);
    return result.stdout.toString().trim();
  }

  static Future<String> getRecentCommits({int count = 10}) async {
    final result = await _runGitCommand([
      'log', '--oneline', '--no-merges', '-n', '$count',
    ]);
    return result.stdout.toString().trim();
  }

  static Future<String> getBranch() async {
    final result = await _runGitCommand(['rev-parse', '--abbrev-ref', 'HEAD']);
    return result.stdout.toString().trim();
  }

  static Future<String> getCurrentUser() async {
    final result = await ShellRunner.runAndCapture('git', [
      'config', '--get', 'user.name',
    ]);
    final name = result.stdout.toString().trim();
    if (name.isNotEmpty) return name;
    return Platform.environment['CIRCLE_USERNAME'] ?? 'ci';
  }

  static Future<String> getLatestCommitBody() async {
    final result = await _runGitCommand(['log', '-1', '--pretty=%b']);
    return result.stdout.toString().trim();
  }

  static Future<ProcessResult> _runGitCommand(List<String> args) async {
    final result = await ShellRunner.runAndCapture('git', args);
    if (result.exitCode != 0) {
      Logger.error('Git command failed: git ${args.join(' ')}');
      Logger.error('Error: ${result.stderr}');
      exit(1);
    }
    return result;
  }
}
