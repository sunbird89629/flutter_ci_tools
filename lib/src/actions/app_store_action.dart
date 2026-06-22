import 'dart:convert';
import 'dart:io';

import '../context_keys.dart';
import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
///
/// The artifact file is read from the explicit [artifact] parameter if
/// provided, otherwise from `ContextKeys.buildArtifact` in the context bag.
class AppStoreUploadAction extends PipelineAction {
  /// Creates an App Store upload action.
  ///
  /// [issuerId] is the App Store Connect API issuer ID.
  /// [apiKeyId] is the App Store Connect API key ID.
  /// [apiKeyPath] is the filesystem path to the `.p8` private key file.
  /// [artifact] optionally specifies the IPA file to upload; if null, reads
  /// `ContextKeys.buildArtifact` from the context bag.
  /// [maxRetries] is the maximum number of upload attempts (default: 5).
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  AppStoreUploadAction({
    required this.issuerId,
    required this.apiKeyId,
    required this.apiKeyPath,
    this.artifact,
    this.maxRetries = 5,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// App Store Connect API issuer ID.
  final String issuerId;

  /// App Store Connect API key ID.
  final String apiKeyId;

  /// Filesystem path to the `.p8` private key file.
  final String apiKeyPath;

  /// Explicit IPA file to upload; falls back to `ContextKeys.buildArtifact`
  /// from the context bag when `null`.
  final File? artifact;

  /// Maximum number of upload attempts before throwing.
  final int maxRetries;

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    _shellRunner.setLogger(context.logger);
    final artifact = this.artifact ?? context.get<File>(ContextKeys.buildArtifact);
    context.logger.info('IPA: ${artifact.path}');
    context.logger.info('API Key: $apiKeyId');
    if (!File(apiKeyPath).existsSync()) {
      throw DeployException(
        'App Store API Key (.p8) not found at $apiKeyPath',
      );
    }
    final p8Content = File(apiKeyPath).readAsStringSync().trim();
    final apiKeyJson = jsonEncode({
      'key_id': apiKeyId,
      'issuer_id': issuerId,
      'key': p8Content,
      'in_house': false,
    });
    final apiKeyJsonFile = File(
      '${Directory.systemTemp.path}/flutter_ci_api_key_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    apiKeyJsonFile.writeAsStringSync(apiKeyJson);
    try {
      ShellResult? result;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        if (attempt > 1) {
          context.logger.info(
            'Retrying App Store upload (attempt $attempt/$maxRetries)...',
          );
          await Future.delayed(const Duration(seconds: 10));
        }
        result = await _shellRunner.runAndCapture('fastlane', [
          'pilot',
          'upload',
          '--ipa',
          artifact.path,
          '--api_key_path',
          apiKeyJsonFile.path,
          '--skip_waiting_for_build_processing',
        ]);
        if (result.exitCode == 0) break;
        context.logger.error(
          'App Store upload attempt $attempt failed: ${result.stderr}',
        );
      }
      if (result!.exitCode != 0) {
        throw DeployException(
          'App Store upload failed after $maxRetries attempts',
        );
      }
    } finally {
      if (apiKeyJsonFile.existsSync()) apiKeyJsonFile.deleteSync();
    }
    context.logger.success('App Store upload successful!');
  }
}
