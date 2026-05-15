import 'dart:convert';
import 'dart:io';

import 'logger.dart';
import 'shell_runner.dart';

class DeployService {
  DeployService._();

  static Future<String?> uploadToPgyer(
    String filePath,
    String apiKey, {
    String? updateDescription,
  }) async {
    Logger.info('Uploading $filePath ...');
    const maxAttempts = 3;
    ProcessResult? result;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        Logger.info('Retrying upload (attempt $attempt/$maxAttempts)...');
        await Future.delayed(const Duration(seconds: 5));
      }
      result = await ShellRunner.runAndCapture('curl', [
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
      Logger.error('Upload failed after $maxAttempts attempts');
      return null;
    }

    try {
      final response = jsonDecode(result.stdout.toString());
      if (response['code'] == 0) {
        final buildKey = response['data']['buildKey'];
        final fullUrl = 'https://www.pgyer.com/$buildKey';
        Logger.success('Upload successful! Download URL: $fullUrl');
        return fullUrl;
      } else {
        Logger.error('Upload failed with API error: ${response['message']}');
        return null;
      }
    } catch (e) {
      Logger.error('Failed to parse upload response', e);
      Logger.info('Raw response: ${result.stdout}');
      return null;
    }
  }

  static Future<void> sendFeishuNotification(
    String webhookUrl,
    String text,
  ) async {
    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      "msg_type": "text",
      "content": {"text": text},
    });
    final result = await ShellRunner.runAndCapture('curl', [
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

  static Future<void> uploadToGooglePlay(
    File aabFile, {
    required String packageName,
    required String jsonKeyPath,
  }) async {
    Logger.section('Uploading to Google Play');
    Logger.info('AAB: ${aabFile.path}');
    Logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw 'Google Play Service Account JSON not found at $jsonKeyPath';
    }
    await ShellRunner.run('fastlane', [
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

  static Future<void> uploadToAppStore(
    File ipaFile, {
    required String issuerId,
    required String apiKeyId,
    required String apiKeyPath,
  }) async {
    Logger.section('Uploading to App Store');
    Logger.info('IPA: ${ipaFile.path}');
    Logger.info('API Key: $apiKeyId');
    if (!File(apiKeyPath).existsSync()) {
      throw 'App Store API Key (.p8) not found at $apiKeyPath';
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
      await ShellRunner.run('fastlane', [
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
