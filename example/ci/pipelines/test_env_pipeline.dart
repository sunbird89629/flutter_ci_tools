import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';

final String pgyerApiKey = '1540c89d7f12ade530a14ac4adf9caa2';
// MessageBus Bot Webhook
final String feishuWebhookUrl =
    'https://open.feishu.cn/open-apis/bot/v2/hook/82ab0b57-f8c9-493f-a69d-575271f12bfd';

class TestEnvPipeline extends Pipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      ExampleAppContext(args: args);

  @override
  String get description => '构建并部署到测试环境 (Pgyer)';
  @override
  String get help => '''
Test Pipeline
构建测试版本并上传到蒲公英。

Usage: dart run ci/build.dart test
同时构建 Android 和 iOS 两个平台。''';

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

    // 构建，显式拿到两个文件
    final androidFile = await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    final iosFile = await runAction(BuildIOSAction(
      envName: 'test',
      exportMethod: 'development',
    ));

    // 并行上传
    final urls = await runParallel([
      PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: androidFile),
      PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: iosFile),
    ]);

    // 一条通知包含两个链接
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrls: urls,
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
