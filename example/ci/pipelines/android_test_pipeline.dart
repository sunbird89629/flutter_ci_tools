import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../build_info_writer.dart';

final buildConfig = CIToolsConfig(
  appName: "testAppName",
  seedBuildNumber: 10000,
  pgyerApiKey: "1540c89d7f12ade530a14ac4adf9caa2",
  feishuWebhookUrl:
      "https://open.feishu.cn/open-apis/bot/v2/hook/82ab0b57-f8c9-493f-a69d-575271f12bfd",
);

class AndroidTestPipeline extends BuildPipeline {
  AndroidTestPipeline() : super(buildConfig);

  @override
  String get name => 'android_test';
  @override
  String get description => 'android 测试环境版本构建，用于开发期间调试脚本的功能';
  @override
  String get help => 'android-only test pipeline';

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());
    await writeBuildInfo(
      env: 'test',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );

    final apk = await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    final pgyerUrl = await runAction(PgyerUploadAction(
      artifact: apk,
      apiKey: context.config.pgyerApiKey!,
    ));
    await runAction(FeishuBuildNotifyAction(
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
