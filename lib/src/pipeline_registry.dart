import 'dart:io';

import 'pipeline.dart';

/// Manages a collection of named pipelines and handles CLI routing.
///
/// Supports two invocation styles:
/// - `dart run ci/build.dart <name>` — run a specific pipeline
/// - `dart run ci/build.dart` — interactive selection menu
class PipelineRegistry {
  final Map<String, BuildPipeline> _pipelines = {};

  /// All registered pipelines in registration order.
  List<BuildPipeline> get pipelines => _pipelines.values.toList();

  /// Registers a [pipeline]. Throws [ArgumentError] if a pipeline with the same name exists.
  void register(BuildPipeline pipeline) {
    if (_pipelines.containsKey(pipeline.name)) {
      throw ArgumentError(
        'Pipeline "${pipeline.name}" is already registered',
      );
    }
    _pipelines[pipeline.name] = pipeline;
  }

  /// Parses [args] and runs the appropriate pipeline.
  ///
  /// - No args: interactive selection
  /// - `--help` / `-h`: print pipeline help
  ///
  /// [readLine] and [onExit] are injectable for testing.
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
      'Usage: dart run ci/build.dart <pipeline>',
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
