import 'dart:io';

import 'package:flutter_ci_tools/src/actions/build_android_action.dart';
import 'package:flutter_ci_tools/src/builders/android_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeAndroidBuilder extends AndroidBuilder {
  _FakeAndroidBuilder() : super();
  final List<String> calls = [];

  @override
  Future<File> buildApk({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    calls.add('apk buildName=$buildName buildNumber=$buildNumber envName=$envName');
    return File('build/app-release.apk');
  }

  @override
  Future<File> buildAppBundle({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    calls.add('aab buildName=$buildName buildNumber=$buildNumber envName=$envName');
    return File('build/app-release.aab');
  }
}

void main() {
  late PipelineContext context;
  late _FakeAndroidBuilder builder;

  setUp(() {
    builder = _FakeAndroidBuilder();
    context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
      platforms: <AppPlatform>{},
    )..buildNumber = 12001;
  });

  test('BuildAndroidAction(apk) returns apk file and forwards build args', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.apk,
      androidBuilder: builder,
    );

    final file = await action.run(context);

    expect(action.name, 'Build Android');
    expect(file.path, endsWith('.apk'));
    expect(builder.calls, [
      'apk buildName=1.2.0 buildNumber=12001 envName=prod',
    ]);
  });

  test('BuildAndroidAction(appbundle) returns aab file', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.appbundle,
      androidBuilder: builder,
    );

    final file = await action.run(context);

    expect(file.path, endsWith('.aab'));
    expect(builder.calls, [
      'aab buildName=1.2.0 buildNumber=12001 envName=prod',
    ]);
  });
}
