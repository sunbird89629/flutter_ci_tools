import 'dart:io';
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';

/// Production [ShellRunner] implementation that executes real processes
/// via [Process.start] / [Process.run].
///
/// Automatically augments `PATH` with `~/.pub-cache/bin` and `/opt/homebrew/bin` (macOS).
class ShellRunnerImpl implements ShellRunner {
  /// Environment variables with augmented PATH for finding Flutter, Dart, and Homebrew tools.
  static late final Map<String, String> environment = () {
    final home = Platform.environment['HOME'] ?? '';
    final extraPaths = <String>['$home/.pub-cache/bin'];
    if (Platform.isMacOS) {
      extraPaths.add('/opt/homebrew/bin');
    }
    return {
      ...Platform.environment,
      'PATH': '${extraPaths.join(':')}:${Platform.environment['PATH']}',
    };
  }();

  static final _sensitiveArgPattern =
      RegExp(r'(_api_key|password|secret|token)=\S+', caseSensitive: false);

  static String _redactArgs(List<String> args) {
    return args
        .map((a) => a.replaceAll(_sensitiveArgPattern, r'$1=***'))
        .join(' ');
  }

  @override
  Future<void> run(String executable, List<String> args) async {
    Logger.command('$executable ${_redactArgs(args)}');
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: false,
    );

    final stdoutDone = process.stdout.forEach((data) => stdout.add(data));
    final stderrDone = process.stderr.forEach((data) => stderr.add(data));

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (exitCode != 0) {
      throw StateError('Command failed with exit code $exitCode');
    }
  }

  @override
  Future<ShellResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    final result = await Process.run(
      executable,
      args,
      environment: environment,
    );
    return ShellResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}
