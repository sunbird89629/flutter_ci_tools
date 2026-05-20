import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'prod_env.dart';
import 'test_env.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run ci/build.dart <test|prod>');
    exit(64);
  }
  final EnvBuilder builder = switch (args.first) {
    'test' => TestEnvBuilder(),
    'prod' => ProdEnvBuilder(),
    _ => throw ArgumentError('Unknown env: ${args.first}'),
  };
  await builder.run();
}
