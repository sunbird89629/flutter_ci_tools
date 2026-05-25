import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an AAB file to Google Play via Fastlane Supply.
class GooglePlayUploadAction extends PipelineAction<void> {
  GooglePlayUploadAction({
    required this.artifact,
    required this.packageName,
    required this.jsonKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final File artifact;
  final String packageName;
  final String jsonKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Google Play';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('AAB: ${artifact.path}');
    Logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw DeployException(
        'Google Play Service Account JSON not found at $jsonKeyPath',
      );
    }
    await _shellRunner.run('fastlane', [
      'supply',
      '--aab',
      artifact.path,
      '--package_name',
      packageName,
      '--json_key',
      jsonKeyPath,
      '--track',
      'internal',
      '--skip_upload_metadata',
      '--skip_upload_images',
      '--skip_upload_screenshots',
    ]);
    Logger.success('Google Play upload successful!');
  }
}
