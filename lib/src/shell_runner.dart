import 'dart:io';

import 'logger.dart';

class ShellResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

abstract class ShellRunner {
  static ShellRunner instance = DefaultShellRunner();

  Future<void> run(String executable, List<String> args);
  Future<ShellResult> runAndCapture(String executable, List<String> args);
}

class DefaultShellRunner implements ShellRunner {
  static Map<String, String> get environment => {
        ...Platform.environment,
        'PATH':
            '${Platform.environment['HOME']}/.pub-cache/bin:/opt/homebrew/bin:${Platform.environment['PATH']}',
      };

  @override
  Future<void> run(String executable, List<String> args) async {
    Logger.command('$executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: true,
    );

    final stdoutSubscription =
        process.stdout.listen((data) => stdout.add(data));
    final stderrSubscription =
        process.stderr.listen((data) => stderr.add(data));

    final exitCode = await process.exitCode;

    await Future.delayed(const Duration(milliseconds: 200));
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();

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
