import 'dart:convert';
import 'dart:io';

import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads the build artifact to Pgyer and returns the download URL.
class PgyerUploadAction extends PipelineAction<String> {
  /// Creates a Pgyer upload action.
  ///
  /// [apiKey] is the Pgyer API key for authentication.
  /// [buildUpdateDescription] is an optional build description shown on Pgyer.
  /// [artifact] optionally specifies the file to upload; if null, uses
  /// [PipelineContext.buildArtifact].
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  PgyerUploadAction({
    required this.apiKey,
    this.buildUpdateDescription,
    this.artifact,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Pgyer API key for authentication.
  final String apiKey;

  /// Optional build update description shown on the Pgyer download page.
  final String? buildUpdateDescription;

  /// Explicit file to upload; falls back to [PipelineContext.buildArtifact]
  /// when `null`.
  final File? artifact;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<String> run(PipelineContext context) async {
    final file = artifact ?? context.buildArtifact;
    final filePath = file.path;
    context.logger.info('Uploading $filePath ...');
    const maxAttempts = 3;
    ShellResult? result;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        context.logger.info('Retrying upload (attempt $attempt/$maxAttempts)...');
        await Future.delayed(const Duration(seconds: 5));
      }
      result = await _shellRunner.runAndCapture('curl', [
        '--http1.1',
        '-F',
        'file=@$filePath',
        '-F',
        '_api_key=$apiKey',
        if (buildUpdateDescription != null) ...[
          '-F',
          'buildUpdateDescription=$buildUpdateDescription',
        ],
        'https://api.xcxwo.com/apiv2/app/upload',
      ]);
      if (result.exitCode == 0) break;
      context.logger.error('Upload attempt $attempt failed: ${result.stderr}');
    }
    if (result!.exitCode != 0) {
      throw DeployException('Upload failed after $maxAttempts attempts');
    }
    try {
      final response = jsonDecode(result.stdout);
      if (response['code'] == 0) {
        final url = 'https://www.pgyer.com/${response['data']['buildKey']}';
        context.logger.success('Upload successful! Download URL: $url');
        return url;
      }
      throw DeployException(
        'Upload failed with API error: ${response['message']}',
      );
    } catch (e) {
      if (e is DeployException) rethrow;
      throw DeployException('Failed to parse upload response: $e');
    }
  }
}
