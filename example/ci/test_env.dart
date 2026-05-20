import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class TestEnvBuilder extends EnvBuilder {
  TestEnvBuilder() : super(exampleConfig);

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'ad-hoc';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  Future<File> buildAndroid() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
    final result = await Process.run('fvm', [
      'flutter',
      'build',
      'apk',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    if (result.exitCode != 0) {
      throw StateError('flutter build apk failed: ${result.stderr}');
    }
    return File('build/app/outputs/flutter-apk/app-release.apk');
  }

  @override
  Future<void> processArtifacts(File apk, File ipa) async {
    await uploadAndNotify(AppPlatform.android, apk);
    await uploadAndNotify(AppPlatform.ios, ipa);
  }
}
