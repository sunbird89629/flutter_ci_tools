import 'package:flutter_ci_tools/flutter_ci_tools.dart'
    hide AndroidBuildType, DeployTarget;
import 'package:flutter_ci_tools/src/actions/build_android_action.dart'
    show AndroidBuildType, BuildAndroidAction;
import 'package:flutter_ci_tools/src/actions/check_git_status_action.dart'
    show CheckGitStatusAction;
import 'package:flutter_ci_tools/src/actions/clean_project_action.dart'
    show CleanProjectAction;
import 'package:flutter_ci_tools/src/actions/collect_metadata_action.dart'
    show CollectMetadataAction;
import 'package:flutter_ci_tools/src/actions/feishu_build_notify_action.dart'
    show DeployTarget, FeishuBuildNotifyAction;
import 'package:flutter_ci_tools/src/actions/push_build_tag_action.dart'
    show PushBuildTagAction;
import 'package:flutter_ci_tools/src/actions/resolve_build_version_action.dart'
    show ResolveBuildVersionAction;
import 'package:flutter_ci_tools/src/actions/restore_workspace_action.dart'
    show RestoreWorkspaceAction;

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
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: 'test',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

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
