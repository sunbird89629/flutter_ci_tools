import 'dart:convert';

import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads the build artifact from [PipelineContext.buildArtifact] to Pgyer
/// and returns the download URL.
class PgyerUploadAction extends PipelineAction<String> {
  PgyerUploadAction({
    required this.apiKey,
    this.description,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  final String apiKey;
  final String? description;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<String> run(PipelineContext context) async {
    final filePath = context.buildArtifact.path;
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
        'https://api.xcxwo.com/apiv2/app/upload',
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
        final url = 'https://www.pgyer.com/${response['data']['buildKey']}';
        Logger.success('Upload successful! Download URL: $url');
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
