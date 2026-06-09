import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'pipelines/android_test_pipeline.dart';
import 'pipelines/prod_pipeline.dart';
import 'pipelines/test_env_pipeline.dart';

Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(TestEnvPipeline())
    ..register(ProdPipeline())
    ..register(AndroidTestPipeline());
  await registry.run(args);
}
