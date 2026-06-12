import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';

const String pgyerApiKey = '1540c89d7f12ade530a14ac4adf9caa2';
// MessageBus Bot Webhook
const String feishuWebhookUrl =
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

    // 构建，分别从 context 取出两个产物
    await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    final androidFile = context.get<File>(ContextKeys.buildArtifact);
    await runAction(BuildIOSAction(
      envName: 'test',
      exportMethod: 'development',
    ));
    final iosFile = context.get<File>(ContextKeys.buildArtifact);

    const androidUrlKey = 'pgyerAndroidUrl';
    const iosUrlKey = 'pgyerIosUrl';

    // 并行上传（各写入不同 key，避免覆盖）
    await runParallelActions([
      PgyerUploadV2Action(
          apiKey: pgyerApiKey, artifact: androidFile, resultKey: androidUrlKey),
      PgyerUploadV2Action(
          apiKey: pgyerApiKey, artifact: iosFile, resultKey: iosUrlKey),
    ]);

    // 一条通知包含两个链接
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrlKeys: [androidUrlKey, iosUrlKey],
    ));

    await runAction(PushBuildTagAction());
  }
}
