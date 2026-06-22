import 'dart:convert';
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

  /// Logger used for command output. Actions inject [PipelineContext.logger]
  /// via [setLogger] at the start of [ShellRunner.run].
  Logger _logger;

  @override
  void setLogger(Logger logger) => _logger = logger;

  /// Creates a [ShellRunnerImpl].
  ///
  /// [logger] defaults to [Logger.silent] when not injected at construction,
  /// but should be overridden via [setLogger] before execution.
  ShellRunnerImpl({Logger? logger})
      : _logger = logger ?? Logger.silent();

  @override
  Future<void> run(String executable, List<String> args) async {
    _logger.command('$executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: true,
    );

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(_logger.verbose);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(_logger.verbose);

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
