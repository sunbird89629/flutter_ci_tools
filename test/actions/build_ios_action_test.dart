import 'dart:io';

import 'package:flutter_ci_tools/src/actions/build_ios_action.dart';
import 'package:flutter_ci_tools/src/builders/ios_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeIOSBuilder extends IOSBuilder {
  _FakeIOSBuilder() : super();
  String? receivedExport;
  String? receivedEnv;

  @override
  Future<File> buildIpa({
    required String buildName,
    required int buildNumber,
    required String envName,
    required String exportMethod,
  }) async {
    receivedExport = exportMethod;
    receivedEnv = envName;
    return File('build/ios/ipa/app.ipa');
  }
}

void main() {
  test('BuildIOSAction returns ipa and forwards export method + env', () async {
    final builder = _FakeIOSBuilder();
    final context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    )..buildNumber = 12001;

    final action = BuildIOSAction(
      envName: 'prod',
      exportMethod: 'app-store',
      iosBuilder: builder,
    );
    final file = await action.run(context);

    expect(action.name, 'Build iOS');
    expect(file.path, endsWith('.ipa'));
    expect(builder.receivedExport, 'app-store');
    expect(builder.receivedEnv, 'prod');
  });
}
