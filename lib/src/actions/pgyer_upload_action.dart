import 'dart:convert';
import 'dart:io';

import '../context_keys.dart';
import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads the build artifact to Pgyer and stores the download URL in the
/// context bag under [resultKey].
class PgyerUploadAction extends PipelineAction {
  /// Creates a Pgyer upload action.
  ///
  /// [apiKey] is the Pgyer API key for authentication.
  /// [buildUpdateDescription] is an optional build description shown on Pgyer.
  /// [artifact] optionally specifies the file to upload; if null, reads
  /// `ContextKeys.buildArtifact` from the context bag.
  /// [resultKey] is the context key under which the download URL is stored.
  /// Defaults to [ContextKeys.pgyerDownloadUrl]; override when uploading
  /// multiple artifacts in parallel so each URL lands under a distinct key.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  PgyerUploadAction({
    required this.apiKey,
    this.buildUpdateDescription,
    this.artifact,
    this.resultKey = ContextKeys.pgyerDownloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Pgyer API key for authentication.
  final String apiKey;

  /// Optional build update description shown on the Pgyer download page.
  final String? buildUpdateDescription;

  /// Explicit file to upload; falls back to `ContextKeys.buildArtifact`
  /// from the context bag when `null`.
  final File? artifact;

  /// Context key under which the download URL is stored. Defaults to
  /// [ContextKeys.pgyerDownloadUrl]; override when uploading multiple
  /// artifacts in parallel so each URL lands under a distinct key.
  final String resultKey;

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<void> run(PipelineContext context) async {
    final file = artifact ?? context.get<File>(ContextKeys.buildArtifact);
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
        context.put(resultKey, url);
        return;
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
