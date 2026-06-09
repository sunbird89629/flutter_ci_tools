import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';

class ProdPipeline extends Pipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      ExampleAppContext(args: args);

  @override
  String get name => 'prod';
  @override
  String get description => '构建并部署到生产环境 (Google Play / App Store)';
  @override
  String get help => '''
Prod Pipeline
构建生产版本并上传到 Google Play 和 App Store。

Usage: dart run ci/build.dart prod
同时构建 Android 和 iOS 两个平台。''';

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());
    await runAction(CleanProjectAction());

    // Android
    await runAction(BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.appbundle,
    ));
    await runAction(GooglePlayUploadAction(
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: DeployTarget.googlePlay,
    ));

    // iOS
    await runAction(BuildIOSAction(
      envName: 'prod',
      exportMethod: 'app-store',
    ));
    await runAction(AppStoreUploadAction(
      issuerId: ProdCredentials.appStoreIssuerId,
      apiKeyId: ProdCredentials.appStoreApiKeyId,
      apiKeyPath: ProdCredentials.appStoreApiKeyPath,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: DeployTarget.appStore,
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
