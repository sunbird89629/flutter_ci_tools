import 'dart:io';

import 'pipeline.dart';

class PipelineRegistry {
  final Map<String, BuildPipeline> _pipelines = {};

  List<BuildPipeline> get pipelines => _pipelines.values.toList();

  void register(BuildPipeline pipeline) {
    if (_pipelines.containsKey(pipeline.name)) {
      throw ArgumentError(
        'Pipeline "${pipeline.name}" is already registered',
      );
    }
    _pipelines[pipeline.name] = pipeline;
  }

  Future<void> run(List<String> args) async {
    if (args.isEmpty) {
      _printUsage();
      exit(64);
    }

    final pipelineName = args.first;
    final pipeline = _pipelines[pipelineName];
    if (pipeline == null) {
      stderr.writeln('Unknown pipeline: $pipelineName');
      stderr.writeln();
      _printUsage();
      exit(64);
    }

    if (args.contains('--help') || args.contains('-h')) {
      stdout.writeln(pipeline.help);
      return;
    }

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
      stderr.writeln('Unknown platform: $platform');
      exit(64);
    }

    await pipeline.run();
  }

  void _printUsage() {
    stderr.writeln(
      'Usage: dart run ci/build.dart <pipeline> [android|ios]',
    );
    stderr.writeln();
    stderr.writeln('Available pipelines:');
    for (final pipeline in _pipelines.values) {
      stderr.writeln(
        '  ${pipeline.name.padRight(20)} ${pipeline.description}',
      );
    }
    stderr.writeln();
    stderr.writeln(
      'Run "dart run ci/build.dart <pipeline> --help" for pipeline-specific help.',
    );
  }
}
