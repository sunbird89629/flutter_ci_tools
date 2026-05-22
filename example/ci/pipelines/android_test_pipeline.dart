import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class AndroidTestPipeline extends BuildPipeline {
  AndroidTestPipeline() : super(exampleConfig);

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'development';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.apk;

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
  Future<void> deployAndroid(File apk) async {
    context.set<String>('artifact_path', apk.path);
    context.set<String>('pgyer_description', [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         $envName',
      'api_host:    $apiHost',
      'git_hash:    ${context.metadata.gitHash}',
      '',
      'recent commits:',
      context.metadata.recentCommits,
    ].join('\n'));

    await PgyerUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      downloadUrl: context.get<String>('pgyer_url'),
    ));
    await FeishuNotifyAction().run(context);
  }

  @override
  Future<void> deployIOS(File ipa) async {
    context.set<String>('artifact_path', ipa.path);
    context.set<String>('pgyer_description', [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         $envName',
      'api_host:    $apiHost',
      'git_hash:    ${context.metadata.gitHash}',
      '',
      'recent commits:',
      context.metadata.recentCommits,
    ].join('\n'));

    await PgyerUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.ios,
      target: DeployTarget.pgyer,
      downloadUrl: context.get<String>('pgyer_url'),
    ));
    await FeishuNotifyAction().run(context);
  }

  @override
  String get description => "android 测试环境版本构建，用于开发期间调试脚本的功能";

  @override
  String get help => "this is help text";

  @override
  String get name => "android_test";
}
