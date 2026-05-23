import 'dart:io';

import 'package:flutter_ci_tools/src/actions/app_store_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];
  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  PipelineContext ctx() => PipelineContext(
        config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 1000),
        platforms: {AppPlatform.ios},
      );

  test('name is correct', () {
    final action = AppStoreUploadAction(
      artifact: File('build/ios/ipa/app.ipa'),
      issuerId: 'issuer',
      apiKeyId: 'key-id',
      apiKeyPath: '/some/AuthKey.p8',
    );
    expect(action.name, 'Upload to App Store');
  });

  test('throws when api key file does not exist', () async {
    final action = AppStoreUploadAction(
      artifact: File('build/ios/ipa/app.ipa'),
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

    // Make sure the ci/ directory exists for api_key_tmp.json
    Directory('ci').createSync(recursive: true);

    final shell = _FakeShellRunner();
    final action = AppStoreUploadAction(
      artifact: File('build/ios/ipa/app.ipa'),
      issuerId: 'iss',
      apiKeyId: 'kid',
      apiKeyPath: p8.path,
      shellRunner: shell,
    );
    try {
      await action.run(ctx());
      expect(
        shell.runCalls.single,
        contains(
          'fastlane pilot upload --ipa build/ios/ipa/app.ipa --api_key_path ci/api_key_tmp.json --skip_waiting_for_build_processing',
        ),
      );
      // tmp json file should be cleaned up
      expect(File('ci/api_key_tmp.json').existsSync(), isFalse);
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  });
}
