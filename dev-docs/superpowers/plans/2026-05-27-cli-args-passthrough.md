# CLI Args Pass-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pass raw CLI args through `PipelineRegistry` → `BuildPipeline` → `PipelineContext` so each pipeline can interpret them independently.

**Architecture:** `PipelineRegistry.run(args)` forwards the full args list to `pipeline.run(args)`, which passes them to `createContext(args)`. `PipelineContext` stores `rawArgs` and exposes a lazy `ArgsParser` helper. Each pipeline decides how to interpret args in its `body()`.

**Tech Stack:** Dart, `package:test`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/src/utils/args_parser.dart` | Create | `ArgsParser` utility class |
| `lib/src/pipeline_context.dart` | Modify | Add `rawArgs` field and `args` getter |
| `lib/src/pipeline.dart` | Modify | `run()` and `createContext()` accept `List<String>` |
| `lib/src/pipeline_registry.dart` | Modify | Forward args to `pipeline.run()` |
| `lib/flutter_ci_tools.dart` | Modify | Export `ArgsParser` |
| `example/ci/app_config.dart` | Modify | `ExampleAppContext` accepts args |
| `example/ci/pipelines/test_pipeline.dart` | Modify | Forward args to context |
| `example/ci/pipelines/prod_pipeline.dart` | Modify | Forward args to context |
| `example/ci/pipelines/android_test_pipeline.dart` | Modify | Forward args to context |
| `test/utils/args_parser_test.dart` | Create | `ArgsParser` unit tests |
| `test/pipeline_context_test.dart` | Modify | Test `rawArgs` and `args` |
| `test/pipeline_test.dart` | Modify | Adapt to new `run(args)` signature |
| `test/pipeline_registry_test.dart` | Modify | Test args pass-through |
| `test/actions/*_test.dart` (16 files) | Modify | Add `rawArgs: []` to `PipelineContext` constructors |

---

### Task 1: Create ArgsParser with TDD

**Files:**
- Create: `test/utils/args_parser_test.dart`
- Create: `lib/src/utils/args_parser.dart`

- [ ] **Step 1: Write failing tests for ArgsParser**

```dart
// test/utils/args_parser_test.dart
import 'package:flutter_ci_tools/src/utils/args_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ArgsParser', () {
    group('has()', () {
      test('returns true when arg is present', () {
        final parser = ArgsParser(['android', '--debug']);
        expect(parser.has('android'), isTrue);
        expect(parser.has('--debug'), isTrue);
      });

      test('returns false when arg is absent', () {
        final parser = ArgsParser(['android']);
        expect(parser.has('ios'), isFalse);
      });

      test('returns false for empty args', () {
        expect(ArgsParser([]).has('anything'), isFalse);
      });
    });

    group('getOption()', () {
      test('returns value for --key=value', () {
        final parser = ArgsParser(['--env=test', '--flavor=prod']);
        expect(parser.getOption('env'), 'test');
        expect(parser.getOption('flavor'), 'prod');
      });

      test('returns null when key not found', () {
        final parser = ArgsParser(['--env=test']);
        expect(parser.getOption('flavor'), isNull);
      });

      test('returns empty string for --key=', () {
        final parser = ArgsParser(['--env=']);
        expect(parser.getOption('env'), '');
      });

      test('returns null for empty args', () {
        expect(ArgsParser([]).getOption('env'), isNull);
      });
    });

    group('positional', () {
      test('returns first non -- arg', () {
        final parser = ArgsParser(['android', '--debug']);
        expect(parser.positional, 'android');
      });

      test('skips -- args to find positional', () {
        final parser = ArgsParser(['--debug', 'android']);
        expect(parser.positional, 'android');
      });

      test('returns null when all args start with --', () {
        final parser = ArgsParser(['--debug', '--verbose']);
        expect(parser.positional, isNull);
      });

      test('returns null for empty args', () {
        expect(ArgsParser([]).positional, isNull);
      });
    });

    group('positionalArgs', () {
      test('returns all non -- args', () {
        final parser = ArgsParser(['android', 'ios', '--debug']);
        expect(parser.positionalArgs, ['android', 'ios']);
      });

      test('returns empty list when all args start with --', () {
        final parser = ArgsParser(['--debug', '--verbose']);
        expect(parser.positionalArgs, isEmpty);
      });

      test('returns empty list for empty args', () {
        expect(ArgsParser([]).positionalArgs, isEmpty);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/utils/args_parser_test.dart`
Expected: FAIL — `args_parser.dart` does not exist.

- [ ] **Step 3: Implement ArgsParser**

```dart
// lib/src/utils/args_parser.dart

/// Simple CLI argument parser.
///
/// Provides helpers for common arg patterns without imposing a full
/// arg-parsing framework. Pipelines interpret args however they like.
class ArgsParser {
  ArgsParser(this.args);

  /// Raw argument list.
  final List<String> args;

  /// Whether [arg] is present (exact match).
  bool has(String arg) => args.contains(arg);

  /// Returns the value from `--key=value`, or `null` if not found.
  String? getOption(String key) {
    final prefix = '$key=';
    for (final arg in args) {
      if (arg.startsWith(prefix)) return arg.substring(prefix.length);
    }
    return null;
  }

  /// First positional (non `--`) argument, or `null`.
  String? get positional {
    for (final arg in args) {
      if (!arg.startsWith('--')) return arg;
    }
    return null;
  }

  /// All positional (non `--`) arguments.
  List<String> get positionalArgs =>
      args.where((a) => !a.startsWith('--')).toList();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/utils/args_parser_test.dart`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add test/utils/args_parser_test.dart lib/src/utils/args_parser.dart
git commit -m "feat: add ArgsParser utility class"
```

---

### Task 2: Add rawArgs to PipelineContext

**Files:**
- Modify: `test/pipeline_context_test.dart:9-16`
- Modify: `lib/src/pipeline_context.dart:24-28`

- [ ] **Step 1: Add failing test for rawArgs and args**

Add to the existing `test/pipeline_context_test.dart` inside the `construction` group:

```dart
    group('rawArgs', () {
      test('exposes raw args list', () {
        final ctx = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 10000,
          rawArgs: ['android', '--debug'],
        );
        expect(ctx.rawArgs, ['android', '--debug']);
      });

      test('args getter returns ArgsParser wrapping rawArgs', () {
        final ctx = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 10000,
          rawArgs: ['android', '--env=test'],
        );
        expect(ctx.args.has('android'), isTrue);
        expect(ctx.args.getOption('env'), 'test');
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/pipeline_context_test.dart`
Expected: FAIL — `PipelineContext` constructor doesn't accept `rawArgs`.

- [ ] **Step 3: Update PipelineContext**

In `lib/src/pipeline_context.dart`:

1. Add import at top:
```dart
import 'utils/args_parser.dart';
```

2. Add `rawArgs` to constructor and class body (after `seedBuildNumber`):
```dart
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    this.rawArgs = const [],
  });

  // ... existing fields ...

  /// Raw CLI arguments passed through from the registry.
  final List<String> rawArgs;

  /// Convenience argument parser built from [rawArgs].
  late final ArgsParser args = ArgsParser(rawArgs);
```

- [ ] **Step 4: Run all PipelineContext tests**

Run: `dart test test/pipeline_context_test.dart`
Expected: All PASS (existing tests use default `rawArgs: []`).

- [ ] **Step 5: Commit**

```bash
git add test/pipeline_context_test.dart lib/src/pipeline_context.dart
git commit -m "feat: add rawArgs field to PipelineContext"
```

---

### Task 3: Change BuildPipeline.run() and createContext() to accept args

**Files:**
- Modify: `lib/src/pipeline.dart:41,57`
- Modify: `test/pipeline_test.dart:36-38,61-63,70,80`

- [ ] **Step 1: Update pipeline.dart signatures**

In `lib/src/pipeline.dart`, change `createContext` and `run`:

```dart
  /// Builds the [PipelineContext] for this run, receiving the raw CLI args.
  PipelineContext createContext(List<String> args);

  // ...

  /// Entry point. Builds the [PipelineContext] via [createContext], then runs
  /// `beforeBuild → body → afterBuild`.
  Future<void> run(List<String> args) async {
    context = createContext(args);
    // ... rest unchanged
  }
```

- [ ] **Step 2: Update test pipeline stubs to accept args**

In `test/pipeline_test.dart`, update `_TestPipeline.createContext()`:

```dart
  @override
  PipelineContext createContext(List<String> args) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
        rawArgs: args,
      );
```

And update all `pipeline.run()` calls to `pipeline.run([])`:

```dart
    test('runs beforeBuild → body → afterBuild in order', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log);
      await pipeline.run([]);
      expect(log, ['before', 'body-start', 'action-a', 'after']);
    });

    test('runs afterBuild even when body throws, and rethrows the body error',
        () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log, bodyThrows: true);
      await expectLater(
        pipeline.run([]),
        throwsA(isA<StateError>()),
      );
      expect(log, ['before', 'body-start', 'after']);
    });

    test(
        'afterBuild errors are swallowed (logged) so they do not mask body errors',
        () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log, afterThrows: true);
      await pipeline.run([]);
      expect(log, containsAll(['before', 'body-start', 'action-a', 'after']));
    });
```

- [ ] **Step 3: Run tests**

Run: `dart test test/pipeline_test.dart`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline.dart test/pipeline_test.dart
git commit -m "refactor: add args parameter to BuildPipeline.run() and createContext()"
```

---

### Task 4: Update PipelineRegistry to pass args through

**Files:**
- Modify: `lib/src/pipeline_registry.dart:60,92`
- Modify: `test/pipeline_registry_test.dart:22-25,65,85`

- [ ] **Step 1: Update PipelineRegistry.run() to forward args**

In `lib/src/pipeline_registry.dart`, change line 60:

```dart
    await pipeline.run(args.sublist(1)); // strip pipeline name, forward rest
```

And line 92 (interactive select):

```dart
        await list[choice - 1].run([]);
```

- [ ] **Step 2: Update test stubs and add pass-through test**

In `test/pipeline_registry_test.dart`:

1. Update `_StubPipeline.createContext()`:
```dart
  List<String>? receivedArgs;

  @override
  PipelineContext createContext(List<String> args) {
    receivedArgs = args;
    return PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 10000,
      rawArgs: args,
    );
  }
```

2. Update `pipeline.run()` calls in tests to verify args:
```dart
    test('run dispatches to pipeline with remaining args', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'android', '--debug']);
      expect(pipeline.wasRun, isTrue);
      expect(pipeline.receivedArgs, ['android', '--debug']);
    });

    test('run interactive passes empty args', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run([], readLine: () => '1');
      expect(pipeline.wasRun, isTrue);
      expect(pipeline.receivedArgs, isEmpty);
    });
```

3. Keep existing tests but update them — the `run(['test'])` call now forwards `args.sublist(1)` which is `[]`.

- [ ] **Step 3: Run tests**

Run: `dart test test/pipeline_registry_test.dart`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline_registry.dart test/pipeline_registry_test.dart
git commit -m "feat: forward CLI args from PipelineRegistry to pipeline"
```

---

### Task 5: Update example pipelines

**Files:**
- Modify: `example/ci/app_config.dart:11-16`
- Modify: `example/ci/pipelines/test_pipeline.dart:8`
- Modify: `example/ci/pipelines/prod_pipeline.dart:8`
- Modify: `example/ci/pipelines/android_test_pipeline.dart:7-14,19`

- [ ] **Step 1: Update ExampleAppContext to accept args**

In `example/ci/app_config.dart`:

```dart
class ExampleAppContext extends PipelineContext {
  ExampleAppContext({List<String> args = const []})
      : super(
          appName: 'FlutterCIToolsExample',
          seedBuildNumber: 10000,
          rawArgs: args,
        );

  // ... rest unchanged
}
```

- [ ] **Step 2: Update AndroidTestContext to accept args**

In `example/ci/pipelines/android_test_pipeline.dart`:

```dart
class AndroidTestContext extends PipelineContext {
  AndroidTestContext({List<String> args = const []})
      : super(
          appName: 'testAppName',
          seedBuildNumber: 10000,
          rawArgs: args,
        );

  // ... rest unchanged
}
```

- [ ] **Step 3: Update all pipeline createContext methods**

In `test_pipeline.dart`, `prod_pipeline.dart`, `android_test_pipeline.dart`:

```dart
  @override
  PipelineContext createContext(List<String> args) => ExampleAppContext(args: args);
  // or for android_test:
  PipelineContext createContext(List<String> args) => AndroidTestContext(args: args);
```

- [ ] **Step 4: Verify no compile errors**

Run: `dart analyze`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add example/
git commit -m "refactor: update example pipelines for args pass-through"
```

---

### Task 6: Update all action tests

**Files:**
- Modify: `test/actions/*_test.dart` (16 files)

Each action test creates `PipelineContext(appName: ..., seedBuildNumber: ...)`. Since `rawArgs` defaults to `const []`, no changes are needed unless tests explicitly construct `PipelineContext` without the default. Verify this by running all tests.

- [ ] **Step 1: Run all tests to check for failures**

Run: `dart test`
Expected: All PASS (default `rawArgs: []` means existing constructors still work).

- [ ] **Step 2: Fix any failures**

If any test fails due to the signature change, add `rawArgs: []` to those `PipelineContext` constructors.

- [ ] **Step 3: Commit if changes were needed**

```bash
git add test/
git commit -m "test: adapt action tests for PipelineContext rawArgs default"
```

---

### Task 7: Add ArgsParser to barrel export

**Files:**
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Add export**

Add after the existing utils exports:

```dart
export 'src/utils/args_parser.dart';
```

- [ ] **Step 2: Verify**

Run: `dart analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/flutter_ci_tools.dart
git commit -m "feat: export ArgsParser from barrel file"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

Run: `dart test`
Expected: All PASS.

- [ ] **Step 2: Run analyzer**

Run: `dart analyze`
Expected: No issues.

- [ ] **Step 3: Verify example builds**

Run: `cd example && dart analyze`
Expected: No issues.
