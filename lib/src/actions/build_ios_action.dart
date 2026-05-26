import 'dart:io';

import '../pipeline_context.dart';
import '../utils/default_shell_runner.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Builds an iOS IPA and returns the output file.
///
/// Reads `context.buildName` and `context.buildNumber` — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
class BuildIOSAction extends PipelineAction<File> {
  BuildIOSAction({
    required this.envName,
    required this.exportMethod,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String envName;
  final String exportMethod;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Build iOS';

  @override
  Future<File> run(PipelineContext context) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$exportMethod',
      '--build-name=${context.buildName}',
      '--build-number=${context.buildNumber}',
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
    final ipaList =
        ipaDir.listSync().where((e) => e.path.endsWith('.ipa')).toList();
    if (ipaList.isEmpty) {
      throw StateError(
        'IPA build failed: No .ipa file found in ${ipaDir.path}',
      );
    }
    return ipaList.first as File;
  }
}
