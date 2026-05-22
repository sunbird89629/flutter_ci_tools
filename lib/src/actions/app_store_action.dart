import 'dart:convert';
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
///
/// Reads: `artifact_path` (String), `app_store_issuer_id` (String),
///        `app_store_api_key_id` (String), `app_store_api_key_path` (String)
class AppStoreUploadAction extends PipelineAction {
  /// Creates an App Store upload action with an optional [shellRunner] for testing.
  AppStoreUploadAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    final ipaPath = context.get<String>('artifact_path');
    final issuerId = context.get<String>('app_store_issuer_id');
    final apiKeyId = context.get<String>('app_store_api_key_id');
    final apiKeyPath = context.get<String>('app_store_api_key_path');

    Logger.section('Uploading to App Store');
    Logger.info('IPA: $ipaPath');
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
        'pilot',
        'upload',
        '--ipa',
        ipaPath,
        '--api_key_path',
        apiKeyJsonFile.path,
        '--skip_waiting_for_build_processing',
      ]);
    } finally {
      apiKeyJsonFile.deleteSync();
    }
    Logger.success('App Store upload successful!');
  }
}
