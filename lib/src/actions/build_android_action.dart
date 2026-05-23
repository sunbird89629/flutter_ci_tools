import 'dart:io';

import '../builders/android_builder.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Android build output format.
enum AndroidBuildType {
  /// Standard APK package.
  apk,

  /// Android App Bundle for Play Store upload.
  appbundle,
}

/// Builds an Android artifact (APK or AAB) and returns the output file.
class BuildAndroidAction extends PipelineAction<File> {
  BuildAndroidAction({
    required this.envName,
    required this.buildType,
    AndroidBuilder? androidBuilder,
  }) : _androidBuilder = androidBuilder ?? AndroidBuilder();

  final String envName;
  final AndroidBuildType buildType;
  final AndroidBuilder _androidBuilder;

  @override
  String get name => 'Build Android';

  @override
  Future<File> run(PipelineContext context) async {
    switch (buildType) {
      case AndroidBuildType.apk:
        return _androidBuilder.buildApk(
          buildName: context.buildName,
          buildNumber: context.buildNumber,
          envName: envName,
        );
      case AndroidBuildType.appbundle:
        return _androidBuilder.buildAppBundle(
          buildName: context.buildName,
          buildNumber: context.buildNumber,
          envName: envName,
        );
    }
  }
}
