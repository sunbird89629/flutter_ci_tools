import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';

class TestPipeline extends Pipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      ExampleAppContext(args: args);

  @override
  String get name => 'test';
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

    await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    await _deployToPgyer();

    await runAction(BuildIOSAction(
      envName: 'test',
      exportMethod: 'development',
    ));
    await _deployToPgyer();

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());

  Future<void> _deployToPgyer() async {
    final pgyerUrl = await runAction(PgyerUploadAction(
      apiKey: (context as ExampleAppContext).pgyerApiKey,
      description: await _pgyerDescription(),
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }

  Future<String> _pgyerDescription() async {
    final git = context.git;
    final gitHash = await git.getShortHash();
    final recentCommits = await git.getRecentCommits(count: 15);
    return [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         test',
      'git_hash:    $gitHash',
      '',
      'recent commits:',
      recentCommits,
    ].join('\n');
  }
}
