import 'dart:io';

import 'package:flutter_ci_tools/src/default_shell_runner.dart';

import '../shell_runner.dart';

/// Builds iOS IPA artifacts using `fvm flutter build ipa`.
class IOSBuilder {
  /// Creates an [IOSBuilder] with an optional [shellRunner].
  IOSBuilder({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  /// Builds a release IPA and returns the output file.
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
