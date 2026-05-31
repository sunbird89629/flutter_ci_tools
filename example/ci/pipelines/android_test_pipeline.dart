import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

/// Standalone context for the android_test pipeline — uses its own dev-only
/// credentials separate from the main app config.
class AndroidTestContext extends PipelineContext {
  AndroidTestContext({List<String> args = const []})
      : super(
          appName: 'testAppName',
          seedBuildNumber: 10000,
          rawArgs: args,
        );

  String get pgyerApiKey => Platform.environment['PGYER_API_KEY'] ?? '';
  String get feishuWebhookUrl =>
      Platform.environment['FEISHU_WEBHOOK_URL'] ?? '';
}

class AndroidTestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(List<String> args) => AndroidTestContext(args: args);

  @override
  String get name => 'android_test';
  @override
  String get description => 'android 测试环境版本构建，用于开发期间调试脚本的功能';
  @override
  String get help => 'android-only test pipeline';

  @override
  Future<void> body() async {
    final ctx = context as AndroidTestContext;

    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

    await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    final pgyerUrl = await runAction(PgyerUploadAction(
      apiKey: ctx.pgyerApiKey,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: ctx.feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
