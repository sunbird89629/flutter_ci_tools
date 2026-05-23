import 'dart:io';

import '../builders/ios_builder.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Builds an iOS IPA and returns the output file.
class BuildIOSAction extends PipelineAction<File> {
  BuildIOSAction({
    required this.envName,
    required this.exportMethod,
    IOSBuilder? iosBuilder,
  }) : _iosBuilder = iosBuilder ?? IOSBuilder();

  final String envName;
  final String exportMethod;
  final IOSBuilder _iosBuilder;

  @override
  String get name => 'Build iOS';

  @override
  Future<File> run(PipelineContext context) {
    return _iosBuilder.buildIpa(
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      envName: envName,
      exportMethod: exportMethod,
    );
  }
}
