import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class AndroidTestPipeline extends BuildPipeline {
  AndroidTestPipeline() : super(exampleConfig);

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
