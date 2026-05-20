import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'prod_env.dart';
import 'test_env.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run ci/build.dart <test|prod> [android|ios]');
    exit(64);
  }

  final BuildPipeline pipeline = switch (args.first) {
    'test' => TestPipeline(),
    'prod' => ProdPipeline(),
    _ => throw ArgumentError('Unknown env: ${args.first}'),
  };

  if (args.length > 1) {
    final platform = args[1];
    if (platform == 'android') {
      await pipeline.runAndroidOnly();
      return;
    }
    if (platform == 'ios') {
      await pipeline.runIOSOnly();
      return;
    }
    throw ArgumentError('Unknown platform: $platform');
  }

  await pipeline.run();
}
