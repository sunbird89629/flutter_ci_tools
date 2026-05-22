import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an AAB file to Google Play via Fastlane Supply.
///
/// Reads: `artifact_path` (String), `google_play_package_name` (String),
///        `google_play_json_key_path` (String)
class GooglePlayUploadAction extends PipelineAction {
  /// Creates a Google Play upload action with an optional [shellRunner] for testing.
  GooglePlayUploadAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Google Play';

  @override
  Future<void> run(PipelineContext context) async {
    final aabPath = context.get<String>('artifact_path');
    final packageName = context.get<String>('google_play_package_name');
    final jsonKeyPath = context.get<String>('google_play_json_key_path');

    Logger.section('Uploading to Google Play');
    Logger.info('AAB: $aabPath');
    Logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw DeployException(
        'Google Play Service Account JSON not found at $jsonKeyPath',
      );
    }
    await _shellRunner.run('fastlane', [
      'supply',
      '--aab',
      aabPath,
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
