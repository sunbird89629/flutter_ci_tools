import 'dart:io';

import '../context_keys.dart';
import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an AAB file to Google Play via Fastlane Supply.
///
/// The artifact file is read from the explicit [artifact] parameter if
/// provided, otherwise from `ContextKeys.buildArtifact` in the context bag.
class GooglePlayUploadAction extends PipelineAction {
  /// Creates a Google Play upload action.
  ///
  /// [packageName] is the Android application ID (e.g. `"com.example.app"`).
  /// [jsonKeyPath] is the filesystem path to the Google Play service account JSON key.
  /// [artifact] optionally specifies the AAB file to upload; if null, reads
  /// `ContextKeys.buildArtifact` from the context bag.
  /// [maxRetries] is the maximum number of upload attempts (default: 5).
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  GooglePlayUploadAction({
    required this.packageName,
    required this.jsonKeyPath,
    this.artifact,
    this.maxRetries = 5,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Android application ID (e.g. `"com.example.app"`).
  final String packageName;

  /// Filesystem path to the Google Play service account JSON key file.
  final String jsonKeyPath;

  /// Explicit AAB file to upload; falls back to `ContextKeys.buildArtifact`
  /// from the context bag when `null`.
  final File? artifact;

  /// Maximum number of upload attempts before throwing.
  final int maxRetries;

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Google Play';

  @override
  Future<void> run(PipelineContext context) async {
    _shellRunner.setLogger(context.logger);
    final artifact = this.artifact ?? context.get<File>(ContextKeys.buildArtifact);
    context.logger.info('AAB: ${artifact.path}');
    context.logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw DeployException(
        'Google Play Service Account JSON not found at $jsonKeyPath',
      );
    }

    ShellResult? result;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      if (attempt > 1) {
        context.logger.info(
          'Retrying Google Play upload (attempt $attempt/$maxRetries)...',
        );
        await Future.delayed(const Duration(seconds: 10));
      }
      result = await _shellRunner.runAndCapture('fastlane', [
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
      if (result.exitCode == 0) break;
      context.logger.error(
        'Google Play upload attempt $attempt failed: ${result.stderr}',
      );
    }
    if (result!.exitCode != 0) {
      throw DeployException(
        'Google Play upload failed after $maxRetries attempts',
      );
    }
    context.logger.success('Google Play upload successful!');
  }
}
