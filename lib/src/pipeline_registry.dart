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

  Future<void> run(
    List<String> args, {
    String? Function()? readLine,
    void Function(int code)? onExit,
  }) async {
    final read = readLine ?? () => stdin.readLineSync();
    final exitFn = onExit ?? exit;

    if (args.isEmpty) {
      await _interactiveSelect(read, exitFn);
      return;
    }

    final pipelineName = args.first;
    final pipeline = _pipelines[pipelineName];
    if (pipeline == null) {
      stderr.writeln('Unknown pipeline: $pipelineName');
      stderr.writeln();
      _printUsage();
      exitFn(64);
      return;
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
      exitFn(64);
      return;
    }

    await pipeline.run();
  }

  Future<void> _interactiveSelect(
    String? Function() readLine,
    void Function(int code) exitFn,
  ) async {
    final list = _pipelines.values.toList();

    while (true) {
      stderr.writeln('Available pipelines:');
      for (var i = 0; i < list.length; i++) {
        stderr.writeln(
          '  ${i + 1}. ${list[i].name.padRight(20)} ${list[i].description}',
        );
      }
      stderr.writeln('  0. 退出');
      stderr.writeln();
      stderr.write('请输入序号选择 pipeline: ');

      final input = readLine();
      if (input == null) {
        exitFn(0);
        return;
      }

      final choice = int.tryParse(input.trim());
      if (choice == 0) {
        exitFn(0);
        return;
      }
      if (choice != null && choice >= 1 && choice <= list.length) {
        await list[choice - 1].run();
        return;
      }

      stderr.writeln('无效输入，请重新选择。');
      stderr.writeln();
    }
  }

  void _printUsage() {
    stderr.writeln(
      'Usage: dart run ci/build.dart <pipeline> [android|ios]',
    );
    stderr.writeln();
    stderr.writeln('Available pipelines:');
    final list = _pipelines.values.toList();
    for (var i = 0; i < list.length; i++) {
      stderr.writeln(
        '  ${i + 1}. ${list[i].name.padRight(20)} ${list[i].description}',
      );
    }
    stderr.writeln();
    stderr.writeln(
      'Run "dart run ci/build.dart <pipeline> --help" for pipeline-specific help.',
    );
  }
}
