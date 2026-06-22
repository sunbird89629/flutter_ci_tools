import 'dart:io';

import 'package:flutter_ci_tools/src/actions/google_play_action.dart';
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:flutter_ci_tools/src/context_keys.dart';
import 'package:flutter_ci_tools/src/utils/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  @override
  void setLogger(Logger logger) {}
  final List<String> runAndCaptureCalls = [];
  int callCount = 0;

  @override
  Future<void> run(String exe, List<String> args) async {}

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    runAndCaptureCalls.add('$exe ${args.join(' ')}');
    callCount++;
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _FailingShellRunner implements ShellRunner {
  @override
  void setLogger(Logger logger) {}
  int callCount = 0;

  @override
  Future<void> run(String exe, List<String> args) async {}

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    callCount++;
    return ShellResult(exitCode: 1, stdout: '', stderr: 'network error');
  }
}

void main() {
  PipelineContext ctx() {
    final c = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 1000,
    );
    c.put(ContextKeys.buildArtifact, File('build/app-release.aab'));
    return c;
  }

  test('name is correct', () {
    final action = GooglePlayUploadAction(
      packageName: 'com.example.app',
      jsonKeyPath: '/some/key.json',
    );
    expect(action.name, 'Upload to Google Play');
  });

  test('throws when json key file does not exist', () async {
    final action = GooglePlayUploadAction(
      packageName: 'com.example.app',
      jsonKeyPath: '/nonexistent/path/key.json',
      shellRunner: _FakeShellRunner(),
    );
    expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
  });

  test('runs fastlane supply with expected args when key exists', () async {
    final tmpKey =
        File('${Directory.systemTemp.createTempSync().path}/key.json');
    tmpKey.writeAsStringSync('{}');
    final shell = _FakeShellRunner();
    final action = GooglePlayUploadAction(
      packageName: 'com.example.app',
      jsonKeyPath: tmpKey.path,
      shellRunner: shell,
    );
    try {
      await action.run(ctx());
      expect(
        shell.runAndCaptureCalls.single,
        contains(
          'fastlane supply --aab build/app-release.aab --package_name com.example.app --json_key ${tmpKey.path} --track internal --skip_upload_metadata --skip_upload_images --skip_upload_screenshots',
        ),
      );
    } finally {
      tmpKey.parent.deleteSync(recursive: true);
    }
  });

  test('retries on failure up to maxRetries times', () async {
    final tmpKey =
        File('${Directory.systemTemp.createTempSync().path}/key.json');
    tmpKey.writeAsStringSync('{}');
    final shell = _FailingShellRunner();
    final action = GooglePlayUploadAction(
      packageName: 'com.example.app',
      jsonKeyPath: tmpKey.path,
      maxRetries: 3,
      shellRunner: shell,
    );
    try {
      await expectLater(
        () => action.run(ctx()),
        throwsA(isA<DeployException>()),
      );
      expect(shell.callCount, 3);
    } finally {
      tmpKey.parent.deleteSync(recursive: true);
    }
  });
}
