import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class ProdPipeline extends BuildPipeline {
  ProdPipeline() : super(exampleConfig);

  @override
  String get name => 'prod';

  @override
  String get description => '构建并部署到生产环境 (Google Play / App Store)';

  @override
  String get help => '''
Prod Pipeline
构建生产版本并上传到 Google Play 和 App Store。

Usage: dart run ci/build.dart prod [android|ios]
  android    仅构建 Android
  ios        仅构建 iOS
不指定平台时同时构建两个平台。''';

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
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> deployAndroid(File aab) async {
    context.set<String>('artifact_path', aab.path);
    context.set<String>('google_play_package_name', ProdCredentials.googlePlayPackageName);
    context.set<String>('google_play_json_key_path', ProdCredentials.googlePlayJsonKeyPath);

    await GooglePlayUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.android,
      target: DeployTarget.googlePlay,
    ));
    await FeishuNotifyAction().run(context);
  }

  @override
  Future<void> deployIOS(File ipa) async {
    context.set<String>('artifact_path', ipa.path);
    context.set<String>('app_store_issuer_id', ProdCredentials.appStoreIssuerId);
    context.set<String>('app_store_api_key_id', ProdCredentials.appStoreApiKeyId);
    context.set<String>('app_store_api_key_path', ProdCredentials.appStoreApiKeyPath);

    await AppStoreUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.ios,
      target: DeployTarget.appStore,
    ));
    await FeishuNotifyAction().run(context);
  }
}
