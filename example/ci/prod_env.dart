import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class ProdPipeline extends BuildPipeline {
  ProdPipeline() : super(exampleConfig);

  @override
  String get envName => 'prod';

  @override
  String get iosExportMethod => 'app-store';

  @override
  String get apiHost => 'https://api.example.com';

  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.appbundle;

  @override
  bool get shouldSwapInfoPlist => true;

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
  }

  @override
  Future<void> deployAndroid(File aab) async {
    await deployService.uploadToGooglePlay(
      aab,
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    );
    await deployService.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ),
    );
  }

  @override
  Future<void> deployIOS(File ipa) async {
    await deployService.uploadToAppStore(
      ipa,
      issuerId: ProdCredentials.appStoreIssuerId,
      apiKeyId: ProdCredentials.appStoreApiKeyId,
      apiKeyPath: ProdCredentials.appStoreApiKeyPath,
    );
    await deployService.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ),
    );
  }
}
