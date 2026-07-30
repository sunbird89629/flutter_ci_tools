# Interactive Pipeline Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add numbered pipeline list and interactive selection prompt when no CLI args provided.

**Architecture:** `PipelineRegistry` gets a `readLine` callback (defaults to `stdin.readLineSync`) for testability. `_printUsage()` gains numbered indices. `run()` shows interactive prompt on empty args instead of exiting.

**Tech Stack:** Dart, package:test

**Spec:** `docs/superpowers/specs/2026-05-21-interactive-pipeline-selection-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/src/pipeline_registry.dart` | Modify | Add numbered output, interactive prompt, injectable `readLine` |
| `test/pipeline_registry_test.dart` | Modify | Add tests for interactive selection |

---

### Task 1: Add interactive pipeline selection

**Files:**
- Modify: `lib/src/pipeline_registry.dart`
- Modify: `test/pipeline_registry_test.dart`

- [ ] **Step 1: Add tests for interactive selection**

In `test/pipeline_registry_test.dart`, add the following tests inside the existing `group('PipelineRegistry', () { ... })` block, after the last test:

```dart
    test('run shows interactive prompt and selects pipeline by number',
        () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run([], readLine: () => '1');
      expect(pipeline.didRun, isTrue);
    });

    test('run interactive exits on 0', () async {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));

      var exitCode = -1;
      await registry.run([], readLine: () => '0',
          onExit: (code) => exitCode = code);
      expect(exitCode, 0);
    });

    test('run interactive re-prompts on invalid input', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      var callCount = 0;
      await registry.run([], readLine: () {
        callCount++;
        if (callCount == 1) return 'invalid';
        return '1';
      });
      expect(pipeline.didRun, isTrue);
      expect(callCount, 2);
    });

    test('run interactive re-prompts on out-of-range number', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      var callCount = 0;
      await registry.run([], readLine: () {
        callCount++;
        if (callCount == 1) return '99';
        return '1';
      });
      expect(pipeline.didRun, isTrue);
      expect(callCount, 2);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/pipeline_registry_test.dart`
Expected: FAIL — `readLine` and `onExit` parameters don't exist yet

- [ ] **Step 3: Update PipelineRegistry**

Replace the entire contents of `lib/src/pipeline_registry.dart` with:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/pipeline_registry_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Run all tests**

Run: `dart test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/src/pipeline_registry.dart test/pipeline_registry_test.dart
git commit -m "feat: add interactive pipeline selection with numbered list"
```
