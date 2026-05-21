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
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
  }

  @override
  Future<void> deployAndroid(File apk) async =>
      uploadToPgyerAndNotify(AppPlatform.android, apk);

  @override
  Future<void> deployIOS(File ipa) async =>
      uploadToPgyerAndNotify(AppPlatform.ios, ipa);

  @override
  String get description => "android 测试环境版本构建，用于测试脚本的功能";

  @override
  String get help => "this is help text";

  @override
  String get name => "android_test";
}
