import 'dart:convert';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads a build artifact to Pgyer and stores the download URL in context.
///
/// Reads: `artifact_path` (String), `config.pgyerApiKey`, `pgyer_description` (String?)
/// Writes: `pgyer_url` (String)
class PgyerUploadAction extends PipelineAction {
  /// Creates a Pgyer upload action with an optional [shellRunner] for testing.
  PgyerUploadAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<void> run(PipelineContext context) async {
    final filePath = context.get<String>('artifact_path');
    final apiKey = context.config.pgyerApiKey!;
    final description = context.tryGet<String>('pgyer_description');

    Logger.info('Uploading $filePath ...');
    const maxAttempts = 3;
    ShellResult? result;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        Logger.info('Retrying upload (attempt $attempt/$maxAttempts)...');
        await Future.delayed(const Duration(seconds: 5));
      }
      result = await _shellRunner.runAndCapture('curl', [
        '--http1.1',
        '-F',
        'file=@$filePath',
        '-F',
        '_api_key=$apiKey',
        if (description != null) ...[
          '-F',
          'buildUpdateDescription=$description',
        ],
        'https://www.pgyer.com/apiv2/app/upload',
      ]);
      if (result.exitCode == 0) break;
      Logger.error('Upload attempt $attempt failed: ${result.stderr}');
    }

    if (result!.exitCode != 0) {
      throw DeployException('Upload failed after $maxAttempts attempts');
    }

    try {
      final response = jsonDecode(result.stdout);
      if (response['code'] == 0) {
        final buildKey = response['data']['buildKey'];
        final fullUrl = 'https://www.pgyer.com/$buildKey';
        Logger.success('Upload successful! Download URL: $fullUrl');
        context.set<String>('pgyer_url', fullUrl);
      } else {
        throw DeployException(
          'Upload failed with API error: ${response['message']}',
        );
      }
    } catch (e) {
      if (e is DeployException) rethrow;
      throw DeployException('Failed to parse upload response: $e');
    }
  }
}
