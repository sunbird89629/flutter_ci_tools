import 'dart:convert';
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
class AppStoreUploadAction extends PipelineAction<void> {
  AppStoreUploadAction({
    required this.artifact,
    required this.issuerId,
    required this.apiKeyId,
    required this.apiKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final File artifact;
  final String issuerId;
  final String apiKeyId;
  final String apiKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('IPA: ${artifact.path}');
    Logger.info('API Key: $apiKeyId');
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
    final apiKeyJsonFile = File('ci/api_key_tmp.json');
    apiKeyJsonFile.writeAsStringSync(apiKeyJson);
    try {
      await _shellRunner.run('fastlane', [
        'pilot', 'upload',
        '--ipa', artifact.path,
        '--api_key_path', apiKeyJsonFile.path,
        '--skip_waiting_for_build_processing',
      ]);
    } finally {
      apiKeyJsonFile.deleteSync();
    }
    Logger.success('App Store upload successful!');
  }
}
