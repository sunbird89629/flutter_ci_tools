import 'dart:convert';
import 'dart:io';

import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
///
/// Reads the IPA path from [PipelineContext.buildArtifact].
class AppStoreUploadAction extends PipelineAction<void> {
  /// Creates an App Store upload action.
  ///
  /// [issuerId] is the App Store Connect API issuer ID.
  /// [apiKeyId] is the App Store Connect API key ID.
  /// [apiKeyPath] is the filesystem path to the `.p8` private key file.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  AppStoreUploadAction({
    required this.issuerId,
    required this.apiKeyId,
    required this.apiKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// App Store Connect API issuer ID.
  final String issuerId;

  /// App Store Connect API key ID.
  final String apiKeyId;

  /// Filesystem path to the `.p8` private key file.
  final String apiKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    final artifact = context.buildArtifact;
    Logger.info('IPA: ${artifact.path}');
    final maskedKeyId = apiKeyId.length > 6
        ? '${apiKeyId.substring(0, 4)}***${apiKeyId.substring(apiKeyId.length - 2)}'
        : '***';
    Logger.info('API Key: $maskedKeyId');
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
    final apiKeyJsonFile =
        File('${Directory.systemTemp.createTempSync('flutter_ci_').path}/api_key.json');
    apiKeyJsonFile.writeAsStringSync(apiKeyJson);
    try {
      await _shellRunner.run('fastlane', [
        'pilot',
        'upload',
        '--ipa',
        artifact.path,
        '--api_key_path',
        apiKeyJsonFile.path,
        '--skip_waiting_for_build_processing',
      ]);
    } finally {
      final tempDir = apiKeyJsonFile.parent;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
    Logger.success('App Store upload successful!');
  }
}
