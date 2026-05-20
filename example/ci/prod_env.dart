import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class ProdEnvBuilder extends EnvBuilder {
  ProdEnvBuilder() : super(exampleConfig);

  @override
  String get envName => 'prod';

  @override
  String get iosExportMethod => 'app-store';

  @override
  String get apiHost => 'https://api.example.com';

  @override
  Future<File> buildAndroid() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
    final result = await Process.run('fvm', [
      'flutter',
      'build',
      'appbundle',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    if (result.exitCode != 0) {
      throw StateError('flutter build appbundle failed: ${result.stderr}');
    }
    return File('build/app/outputs/bundle/release/app-release.aab');
  }

  @override
  Future<void> processArtifacts(File aab, File ipa) async {
    await DeployService.instance.uploadToGooglePlay(
      aab,
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    );
    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ),
    );

    await DeployService.instance.uploadToAppStore(
      ipa,
      issuerId: ProdCredentials.appStoreIssuerId,
      apiKeyId: ProdCredentials.appStoreApiKeyId,
      apiKeyPath: ProdCredentials.appStoreApiKeyPath,
    );
    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ),
    );
  }
}
