import 'dart:io';

import 'logger.dart';

class ShellRunner {
  ShellRunner._();

  static Map<String, String> get _environment => {
    ...Platform.environment,
    'PATH':
        '${Platform.environment['HOME']}/.pub-cache/bin:/opt/homebrew/bin:${Platform.environment['PATH']}',
  };

  static Future<void> run(String executable, List<String> args) async {
    Logger.command('$executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      environment: _environment,
      runInShell: true,
    );

    final stdoutSubscription = process.stdout.listen((data) => stdout.add(data));
    final stderrSubscription = process.stderr.listen((data) => stderr.add(data));

    final exitCode = await process.exitCode;

    await Future.delayed(const Duration(milliseconds: 200));
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();

    if (exitCode != 0) {
      throw 'Command failed with exit code $exitCode';
    }
  }

  static Future<ProcessResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    final result = await Process.run(
      executable,
      args,
      environment: _environment,
    );
    return result;
  }
}
