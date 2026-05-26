import 'dart:io';

import '../pipeline_context.dart';
import '../utils/shell_runner_impl.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Builds an iOS IPA and stores it in context.
///
/// Reads `context.buildName` and `context.buildNumber` — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
///
/// After completion, the output file is available via `context.buildArtifact`.
class BuildIOSAction extends PipelineAction<void> {
  /// Creates an iOS build action.
  ///
  /// [envName] is the `--dart-define=ENV` value (e.g. `"prod"`, `"staging"`).
  /// [exportMethod] is the Xcode export method (e.g. `"ad-hoc"`, `"app-store"`).
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  BuildIOSAction({
    required this.envName,
    required this.exportMethod,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// The `--dart-define=ENV` value passed to the Flutter build.
  final String envName;

  /// Xcode export method (e.g. `"ad-hoc"`, `"app-store"`, `"development"`).
  final String exportMethod;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Build iOS';

  @override
  Future<void> run(PipelineContext context) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$exportMethod',
      '--build-name=${context.buildName}',
      '--build-number=${context.buildNumber}',
      '--dart-define=ENV=$envName',
    ]);
    context.setBuildArtifact(_findIpa());
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
