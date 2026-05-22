import 'dart:convert';
import 'dart:io';

import 'package:flutter_ci_tools/src/default_shell_runner.dart';

import 'exceptions.dart';
import 'logger.dart';
import 'shell_runner.dart';

/// Interface for deploying build artifacts and sending notifications.
///
/// Implementations can be swapped for testing via dependency injection.
abstract class DeployService {
  /// Default singleton instance.
  static DeployService instance = DefaultDeployService();

  /// Uploads a build file to Pgyer and returns the download URL.
  Future<String> uploadToPgyer(
    String filePath,
    String apiKey, {
    String? updateDescription,
  });

  /// Sends a text message to a Feishu (Lark) webhook.
  Future<void> sendFeishuNotification(String webhookUrl, String text);

  /// Uploads an AAB file to Google Play via Fastlane Supply.
  Future<void> uploadToGooglePlay(
    File aabFile, {
    required String packageName,
    required String jsonKeyPath,
  });

  /// Uploads an IPA file to App Store Connect via Fastlane Pilot.
  Future<void> uploadToAppStore(
    File ipaFile, {
    required String issuerId,
    required String apiKeyId,
    required String apiKeyPath,
  });
}

/// Default [DeployService] implementation using [ShellRunner] for external commands.
class DefaultDeployService implements DeployService {
  /// Creates a [DefaultDeployService] with an optional [shellRunner].
  DefaultDeployService({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  Future<String> uploadToPgyer(
    String filePath,
    String apiKey, {
    String? updateDescription,
  }) async {
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
        '-F', 'file=@$filePath',
        '-F', '_api_key=$apiKey',
        if (updateDescription != null) ...[
          '-F', 'buildUpdateDescription=$updateDescription',
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
        return fullUrl;
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

  @override
  Future<void> sendFeishuNotification(
    String webhookUrl,
    String text,
  ) async {
    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      "msg_type": "text",
      "content": {"text": text},
    });
    final result = await _shellRunner.runAndCapture('curl', [
      '-X', 'POST',
      '-H', 'Content-Type: application/json',
      '-d', jsonMessage,
      webhookUrl,
    ]);
    if (result.exitCode == 0) {
      Logger.success('Feishu notification sent.');
    } else {
      Logger.error('Failed to send Feishu notification: ${result.stderr}');
    }
  }

  @override
  Future<void> uploadToGooglePlay(
    File aabFile, {
    required String packageName,
    required String jsonKeyPath,
  }) async {
    Logger.section('Uploading to Google Play');
    Logger.info('AAB: ${aabFile.path}');
    Logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw DeployException(
        'Google Play Service Account JSON not found at $jsonKeyPath',
      );
    }
    await _shellRunner.run('fastlane', [
      'supply',
      '--aab', aabFile.path,
      '--package_name', packageName,
      '--json_key', jsonKeyPath,
      '--track', 'internal',
      '--skip_upload_metadata',
      '--skip_upload_images',
      '--skip_upload_screenshots',
    ]);
    Logger.success('Google Play upload successful!');
  }

  @override
  Future<void> uploadToAppStore(
    File ipaFile, {
    required String issuerId,
    required String apiKeyId,
    required String apiKeyPath,
  }) async {
    Logger.section('Uploading to App Store');
    Logger.info('IPA: ${ipaFile.path}');
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
        '--ipa', ipaFile.path,
        '--api_key_path', apiKeyJsonFile.path,
        '--skip_waiting_for_build_processing',
      ]);
    } finally {
      apiKeyJsonFile.deleteSync();
    }
    Logger.success('App Store upload successful!');
  }
}
