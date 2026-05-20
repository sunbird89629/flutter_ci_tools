import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class BuildInfo {
  final String env;
  final String buildName;
  final int buildNumber;
  final String gitHash;
  final String branch;
  final String recentCommits;

  const BuildInfo({
    required this.env,
    required this.buildName,
    required this.buildNumber,
    required this.gitHash,
    required this.branch,
    required this.recentCommits,
  });

  factory BuildInfo.fromJson(Map<String, dynamic> json) => BuildInfo(
        env: json['env'] as String,
        buildName: json['buildName'] as String,
        buildNumber: json['buildNumber'] as int,
        gitHash: json['gitHash'] as String,
        branch: json['branch'] as String,
        recentCommits: json['recentCommits'] as String,
      );

  static Future<BuildInfo> load() async {
    final raw = await rootBundle.loadString('assets/build_info.json');
    return BuildInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
