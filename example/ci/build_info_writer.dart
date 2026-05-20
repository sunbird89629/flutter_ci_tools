import 'dart:convert';
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

Future<void> writeBuildInfo({
  required String env,
  required String buildName,
  required int buildNumber,
  required BuildMetadata metadata,
}) async {
  final json = {
    'env': env,
    'buildName': buildName,
    'buildNumber': buildNumber,
    'gitHash': metadata.gitHash,
    'branch': metadata.branch,
    'recentCommits': metadata.recentCommits,
  };
  await File('assets/build_info.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}
