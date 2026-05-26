import 'dart:io';

import '../pipeline_context.dart';
import '../utils/default_shell_runner.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Android build output format.
enum AndroidBuildType {
  /// Standard APK package.
  apk,

  /// Android App Bundle for Play Store upload.
  appbundle,
}

/// Builds an Android artifact (APK or AAB) and returns the output file.
///
/// Reads `context.buildName` and `context.buildNumber` — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
class BuildAndroidAction extends PipelineAction<File> {
  BuildAndroidAction({
    required this.envName,
    required this.buildType,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String envName;
  final AndroidBuildType buildType;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Build Android';

  @override
  Future<File> run(PipelineContext context) async {
    final (subcommand, outputPath) = switch (buildType) {
      AndroidBuildType.apk => (
          'apk',
          'build/app/outputs/flutter-apk/app-release.apk',
        ),
      AndroidBuildType.appbundle => (
          'appbundle',
          'build/app/outputs/bundle/release/app-release.aab',
        ),
    };
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      subcommand,
      '--build-name=${context.buildName}',
      '--build-number=${context.buildNumber}',
      '--dart-define=ENV=$envName',
    ]);
    return File(outputPath);
  }
}
