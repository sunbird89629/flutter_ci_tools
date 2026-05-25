import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class ProdPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      ExampleAppContext(platforms: platforms);

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
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());
    await runAction(CleanProjectAction());
    await writeBuildInfo(
      env: 'prod',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );

    if (context.platforms.contains(AppPlatform.android)) {
      final aab = await runAction(BuildAndroidAction(
        envName: 'prod',
        buildType: AndroidBuildType.appbundle,
      ));
      await runAction(GooglePlayUploadAction(
        artifact: aab,
        packageName: ProdCredentials.googlePlayPackageName,
        jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
      ));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ));
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      final ipa = await runAction(BuildIOSAction(
        envName: 'prod',
        exportMethod: 'app-store',
      ));
      await runAction(AppStoreUploadAction(
        artifact: ipa,
        issuerId: ProdCredentials.appStoreIssuerId,
        apiKeyId: ProdCredentials.appStoreApiKeyId,
        apiKeyPath: ProdCredentials.appStoreApiKeyPath,
      ));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ));
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
