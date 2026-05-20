import 'dart:io';

import '../shell_runner.dart';

class AndroidBuilder {
  AndroidBuilder({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  Future<File> buildApk({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'apk',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return File('build/app/outputs/flutter-apk/app-release.apk');
  }

  Future<File> buildAppBundle({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'appbundle',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return File('build/app/outputs/bundle/release/app-release.aab');
  }
}
