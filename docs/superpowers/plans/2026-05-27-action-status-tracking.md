# Action-Level Status Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured status tracking to each PipelineAction so pipelines can introspect execution results and display a summary table.

**Architecture:** ActionStatus enum lives in its own file. PipelineAction gains mutable status/duration/error fields. BuildPipeline.runAction handles timing and status recording. BuildPipeline.run auto-prints a summary table in its finally block.

**Tech Stack:** Dart 3.4+, package:test

**Spec:** `docs/superpowers/specs/2026-05-27-action-status-tracking-design.md`

---

### Task 1: ActionStatus enum

**Files:**
- Create: `lib/src/action_status.dart`
- Test: `test/action_status_test.dart`
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/action_status_test.dart
import 'package:flutter_ci_tools/src/action_status.dart';
import 'package:test/test.dart';

void main() {
  group('ActionStatus', () {
    test('has four values', () {
      expect(ActionStatus.values, hasLength(4));
    });

    test('contains success, failed, skipped, interrupted', () {
      expect(ActionStatus.values, containsAll([
        ActionStatus.success,
        ActionStatus.failed,
        ActionStatus.skipped,
        ActionStatus.interrupted,
      ]));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/action_status_test.dart`
Expected: FAIL — `action_status.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/action_status.dart
enum ActionStatus {
  success,
  failed,
  skipped,
  interrupted,
}
```

- [ ] **Step 4: Add barrel export**

Add to `lib/flutter_ci_tools.dart` (after the existing `export 'src/actions/pipeline_action.dart';` line):

```dart
export 'src/action_status.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dart test test/action_status_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/src/action_status.dart test/action_status_test.dart lib/flutter_ci_tools.dart
git commit -m "feat: add ActionStatus enum"
```

---

### Task 2: PipelineAction status fields

**Files:**
- Modify: `lib/src/actions/pipeline_action.dart`
- Test: `test/actions/pipeline_action_test.dart`

- [ ] **Step 1: Write the failing tests**

Read `test/actions/pipeline_action_test.dart` first to understand the existing test structure, then add new tests. The existing test file uses a `_TestAction` helper — follow the same pattern.

```dart
// Add to the existing group in test/actions/pipeline_action_test.dart

test('status is null before run', () {
  final action = _TestAction('test');
  expect(action.status, isNull);
  expect(action.hasRun, isFalse);
});

test('status can be set to success', () {
  final action = _TestAction('test');
  action.status = ActionStatus.success;
  action.duration = Duration(seconds: 5);
  expect(action.status, ActionStatus.success);
  expect(action.duration, Duration(seconds: 5));
  expect(action.hasRun, isTrue);
});

test('status can be set to failed with error', () {
  final action = _TestAction('test');
  final error = StateError('oops');
  action.status = ActionStatus.failed;
  action.duration = Duration(seconds: 2);
  action.error = error;
  action.stackTrace = StackTrace.current;
  expect(action.status, ActionStatus.failed);
  expect(action.error, same(error));
  expect(action.stackTrace, isNotNull);
});
```

Add the `ActionStatus` import at the top of the test file:

```dart
import 'package:flutter_ci_tools/src/action_status.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/pipeline_action_test.dart`
Expected: FAIL — `status`, `duration`, `error`, `stackTrace`, `hasRun` not found on PipelineAction.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/actions/pipeline_action.dart
import '../action_status.dart';
import '../pipeline_context.dart';

abstract class PipelineAction<R> {
  String get name;

  ActionStatus? status;
  Duration? duration;
  Object? error;
  StackTrace? stackTrace;

  bool get hasRun => status != null;

  Future<R> run(PipelineContext context);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/pipeline_action_test.dart`
Expected: PASS

- [ ] **Step 5: Run all tests to check for regressions**

Run: `dart test`
Expected: All 82+ tests pass. PipelineAction fields are additive — no existing code references them yet.

- [ ] **Step 6: Commit**

```bash
git add lib/src/actions/pipeline_action.dart test/actions/pipeline_action_test.dart
git commit -m "feat: add status/duration/error fields to PipelineAction"
```

---

### Task 3: Simplify runStep (remove timing)

**Files:**
- Modify: `lib/src/pipeline.dart:15-27`

- [ ] **Step 1: Read existing pipeline tests**

Read `test/pipeline_test.dart` to understand what the tests depend on from `runStep`. The tests call `pipeline.run()` which calls `runAction` which calls `runStep`. The tests verify execution order via log entries, not timing output.

- [ ] **Step 2: Simplify runStep**

Replace the `runStep` function in `lib/src/pipeline.dart`:

```dart
Future<T> runStep<T>(String name, Future<T> Function() action) async {
  Logger.section(name);
  try {
    final result = await action();
    Logger.success('Finished: $name');
    return result;
  } catch (e) {
    Logger.error('Failed: $name', e);
    rethrow;
  }
}
```

Changes:
- Remove `final startTime = DateTime.now();`
- Remove `final duration = DateTime.now().difference(startTime);`
- Change `Logger.success('Finished: $name (${duration.inSeconds}s)');` to `Logger.success('Finished: $name');`

- [ ] **Step 3: Run all tests**

Run: `dart test`
Expected: All tests pass. The existing tests don't assert on the timing string in Logger output.

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline.dart
git commit -m "refactor: remove timing from runStep (moved to runAction)"
```

---

### Task 4: BuildPipeline — timing, status recording, executedActions

**Files:**
- Modify: `lib/src/pipeline.dart`
- Test: `test/pipeline_test.dart`

- [ ] **Step 1: Write the failing tests**

Read `test/pipeline_test.dart` first. Then add a new group for status tracking. The existing `_TestPipeline` and `_RecordingAction` helpers can be reused. Add a new helper `_SimpleAction` for actions that return a value:

```dart
// Add to test/pipeline_test.dart

import 'package:flutter_ci_tools/src/action_status.dart';

class _SimpleAction extends PipelineAction<String> {
  _SimpleAction(this.label, {this.result = 'ok', this.willThrow = false});
  final String label;
  final String result;
  final bool willThrow;
  @override
  String get name => label;
  @override
  Future<String> run(PipelineContext context) async {
    if (willThrow) throw StateError('fail from $label');
    return result;
  }
}
```

Then add the test group:

```dart
group('action status tracking', () {
  test('records success status and duration on action', () async {
    final pipeline = _TestPipeline(log: []);
    await pipeline.run({AppPlatform.android});
    // The 'action-a' action ran successfully
    final actionA = pipeline.executedActions
        .firstWhere((a) => a.name == 'action-a');
    expect(actionA.status, ActionStatus.success);
    expect(actionA.duration, isNotNull);
    expect(actionA.duration!.inMilliseconds, greaterThanOrEqualTo(0));
    expect(actionA.error, isNull);
    expect(actionA.stackTrace, isNull);
  });

  test('records failed status with error on action', () async {
    final pipeline = _TestPipeline(log: [], bodyThrows: true);
    await expectLater(
      pipeline.run({AppPlatform.android}),
      throwsA(isA<StateError>()),
    );
    // after action ran (and succeeded) even though body threw
    final afterAction = pipeline.executedActions
        .firstWhere((a) => a.name == 'after');
    expect(afterAction.status, ActionStatus.success);
  });

  test('executedActions preserves execution order', () async {
    final log = <String>[];
    final pipeline = _TestPipeline(log: log);
    await pipeline.run({AppPlatform.android});
    expect(pipeline.executedActions.map((a) => a.name),
        ['action-a', 'after']);
  });

  test('allSucceeded returns true when all actions succeed', () async {
    final pipeline = _TestPipeline(log: []);
    await pipeline.run({AppPlatform.android});
    expect(pipeline.allSucceeded, isTrue);
    expect(pipeline.lastFailure, isNull);
  });

  test('allSucceeded returns false and lastFailure returns failed action',
      () async {
    final pipeline = _FailActionPipeline();
    await expectLater(
      pipeline.run({AppPlatform.android}),
      throwsA(isA<StateError>()),
    );
    expect(pipeline.allSucceeded, isFalse);
    expect(pipeline.lastFailure, isNotNull);
    expect(pipeline.lastFailure!.name, 'will-fail');
    expect(pipeline.lastFailure!.error, isA<StateError>());
    // The first action succeeded even though pipeline failed
    expect(pipeline.executedActions.first.name, 'ok-action');
    expect(pipeline.executedActions.first.status, ActionStatus.success);
  });

  test('runAction returns the action result', () async {
    final pipeline = _ValuePipeline();
    await pipeline.run({AppPlatform.android});
    expect(pipeline.returnValue, 'hello');
    expect(pipeline.executedActions.first.status, ActionStatus.success);
  });
});
```

Add a helper pipeline for testing return values:

```dart
class _ValuePipeline extends BuildPipeline {
  String? returnValue;
  @override
  String get name => 'value-test';
  @override
  String get description => 'test';
  @override
  String get help => 'help';
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
        platforms: platforms,
      );
  @override
  Future<void> body() async {
    returnValue = await runAction(_SimpleAction('s1', result: 'hello'));
  }
}

class _FailActionPipeline extends BuildPipeline {
  @override
  String get name => 'fail-test';
  @override
  String get description => 'test';
  @override
  String get help => 'help';
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
        platforms: platforms,
      );
  @override
  Future<void> body() async {
    await runAction(_SimpleAction('ok-action'));
    await runAction(_SimpleAction('will-fail', willThrow: true));
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/pipeline_test.dart`
Expected: FAIL — `executedActions`, `allSucceeded`, `lastFailure` not found on BuildPipeline.

- [ ] **Step 3: Write minimal implementation**

Modify `lib/src/pipeline.dart`. Add import and update BuildPipeline:

```dart
import 'action_status.dart';
import 'logger.dart';
import 'pipeline_context.dart';
import 'actions/pipeline_action.dart';
```

Add fields and methods to `BuildPipeline`:

```dart
abstract class BuildPipeline {
  late final PipelineContext context;

  /// Actions executed during this run, in execution order.
  final List<PipelineAction> executedActions = [];

  /// Whether all executed actions succeeded.
  bool get allSucceeded =>
      executedActions.every((a) => a.status == ActionStatus.success);

  /// The last failed action, or null if none failed.
  PipelineAction? get lastFailure {
    for (var i = executedActions.length - 1; i >= 0; i--) {
      if (executedActions[i].status == ActionStatus.failed) {
        return executedActions[i];
      }
    }
    return null;
  }

  // ... existing abstract members unchanged ...

  Future<void> run(Set<AppPlatform> platforms) async {
    context = createContext(platforms);
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e) {
        Logger.error('afterBuild failed', e);
      }
      _printSummary();
    }
  }

  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await runStep(action.name, () => action.run(context));
      stopwatch.stop();
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      action
        ..status = ActionStatus.failed
        ..duration = stopwatch.elapsed
        ..error = e
        ..stackTrace = stackTrace;
      rethrow;
    }
  }

  void _printSummary() {
    if (executedActions.isEmpty) return;
    const sep = '────────────────────────────────────';
    Logger.info(sep);
    Logger.info('执行摘要');
    Logger.info(sep);
    for (final action in executedActions) {
      final icon = switch (action.status!) {
        ActionStatus.success => '✅',
        ActionStatus.failed => '❌',
        ActionStatus.skipped => '⏭️',
        ActionStatus.interrupted => '🛑',
      };
      final time = '${action.duration!.inSeconds}s';
      Logger.info('$icon ${action.name} ($time)');
    }
    Logger.info(sep);
    final failure = lastFailure;
    if (failure != null) {
      Logger.error('失败: ${failure.name}', failure.error);
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/pipeline_test.dart`
Expected: PASS

- [ ] **Step 5: Run all tests**

Run: `dart test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/pipeline.dart test/pipeline_test.dart
git commit -m "feat: add action status tracking and summary table to BuildPipeline"
```

---

### Task 5: Final verification and cleanup

**Files:**
- None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `dart test`
Expected: All tests pass.

- [ ] **Step 2: Run dart analyze**

Run: `dart analyze`
Expected: No issues found.

- [ ] **Step 3: Verify barrel export**

Check that `ActionStatus` is accessible via the barrel:

```bash
dart -e "import 'package:flutter_ci_tools/flutter_ci_tools.dart'; print(ActionStatus.success);"
```

Expected: Prints `ActionStatus.success`.

- [ ] **Step 4: Final commit (if any cleanup needed)**

Only if analyze or tests found issues.
