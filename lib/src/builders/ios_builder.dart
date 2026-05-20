import 'dart:io';

import '../shell_runner.dart';

class IOSBuilder {
  IOSBuilder({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  Future<File> buildIpa({
    required String buildName,
    required int buildNumber,
    required String envName,
    required String exportMethod,
  }) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$exportMethod',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return _findIpa();
  }

  File _findIpa() {
    final ipaDir = Directory('build/ios/ipa');
    if (!ipaDir.existsSync()) {
      throw StateError(
        'IPA build failed: Directory not found at ${ipaDir.path}',
      );
    }
    final ipaList = ipaDir
        .listSync()
        .where((e) => e.path.endsWith('.ipa'))
        .toList();
    if (ipaList.isEmpty) {
      throw StateError(
        'IPA build failed: No .ipa file found in ${ipaDir.path}',
      );
    }
    return ipaList.first as File;
  }
}
