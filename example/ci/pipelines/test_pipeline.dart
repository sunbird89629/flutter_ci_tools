import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      ExampleAppContext(platforms: platforms);

  @override
  String get name => 'test';
  @override
  String get description => '构建并部署到测试环境 (Pgyer)';
  @override
  String get help => '''
Test Pipeline
构建测试版本并上传到蒲公英。

Usage: dart run ci/build.dart test [android|ios]
  android    仅构建 Android
  ios        仅构建 iOS
不指定平台时同时构建两个平台。''';

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

    if (context.platforms.contains(AppPlatform.android)) {
      await runAction(BuildAndroidAction(
        envName: 'test',
        buildType: AndroidBuildType.apk,
      ));
      await _deployToPgyer(AppPlatform.android);
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      await runAction(BuildIOSAction(
        envName: 'test',
        exportMethod: 'development',
      ));
      await _deployToPgyer(AppPlatform.ios);
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());

  Future<void> _deployToPgyer(AppPlatform platform) async {
    final pgyerUrl = await runAction(PgyerUploadAction(
      apiKey: (context as ExampleAppContext).pgyerApiKey,
      description: _pgyerDescription(),
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      platform: platform,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }

  String _pgyerDescription() {
    final m = context.metadata;
    return [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         test',
      'git_hash:    ${m.gitHash}',
      '',
      'recent commits:',
      m.recentCommits,
    ].join('\n');
  }
}
