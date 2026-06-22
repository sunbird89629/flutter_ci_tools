import 'dart:io';
import 'package:flutter_ci_tools/src/utils/logger.dart';

import 'package:flutter_ci_tools/src/actions/app_store_action.dart';
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
    c.put(ContextKeys.buildArtifact, File('build/ios/ipa/app.ipa'));
    return c;
  }

  test('name is correct', () {
    final action = AppStoreUploadAction(
      issuerId: 'issuer',
      apiKeyId: 'key-id',
      apiKeyPath: '/some/AuthKey.p8',
    );
    expect(action.name, 'Upload to App Store');
  });

  test('throws when api key file does not exist', () async {
    final action = AppStoreUploadAction(
      issuerId: 'issuer',
      apiKeyId: 'key-id',
      apiKeyPath: '/nonexistent/path/AuthKey.p8',
      shellRunner: _FakeShellRunner(),
    );
    expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
  });

  test('runs fastlane pilot upload with expected args when key exists',
      () async {
    final tmpDir = Directory.systemTemp.createTempSync();
    final p8 = File('${tmpDir.path}/AuthKey.p8');
    p8.writeAsStringSync('FAKEKEY');

    final shell = _FakeShellRunner();
    final action = AppStoreUploadAction(
      issuerId: 'iss',
      apiKeyId: 'kid',
      apiKeyPath: p8.path,
      shellRunner: shell,
    );
    try {
      await action.run(ctx());
      final call = shell.runAndCaptureCalls.single;
      // The tmp JSON file path is generated at runtime under systemTemp,
      // so we match the surrounding command shape and verify the path
      // looks like a system-temp path that has since been cleaned up.
      expect(
          call,
          startsWith(
              'fastlane pilot upload --ipa build/ios/ipa/app.ipa --api_key_path '));
      expect(call, endsWith(' --skip_waiting_for_build_processing'));
      final tmpJsonPath = call
          .replaceFirst(
              'fastlane pilot upload --ipa build/ios/ipa/app.ipa --api_key_path ',
              '')
          .replaceFirst(' --skip_waiting_for_build_processing', '');
      expect(tmpJsonPath, contains(Directory.systemTemp.path));
      expect(tmpJsonPath, endsWith('.json'));
      // Cleaned up after the fastlane call returns.
      expect(File(tmpJsonPath).existsSync(), isFalse);
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  });

  test('retries on failure up to maxRetries times', () async {
    final tmpDir = Directory.systemTemp.createTempSync();
    final p8 = File('${tmpDir.path}/AuthKey.p8');
    p8.writeAsStringSync('FAKEKEY');

    final shell = _FailingShellRunner();
    final action = AppStoreUploadAction(
      issuerId: 'iss',
      apiKeyId: 'kid',
      apiKeyPath: p8.path,
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
      tmpDir.deleteSync(recursive: true);
    }
  });
}
