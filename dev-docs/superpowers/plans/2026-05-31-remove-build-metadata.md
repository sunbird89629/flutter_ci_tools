# Remove BuildMetadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the anemic `BuildMetadata` value object and `CollectMetadataAction`, exposing a `GitManager` directly on `PipelineContext` so consumers read git data on-demand.

**Architecture:** `PipelineContext` gains an injectable `git` field (defaulting to `GitManager.instance`) and loses its `metadata` field. The sole library consumer, `FeishuBuildNotifyAction`, reads git data via `await context.git.*` instead of `context.metadata.*`. `BuildMetadata`, `CollectMetadataAction`, and their tests are deleted. Example pipelines drop the `CollectMetadataAction()` call and read git on-demand.

**Tech Stack:** Dart, `package:test`, hand-written `_Fake*` classes (project convention — no mocks).

**Spec:** `docs/superpowers/specs/2026-05-31-remove-build-metadata-design.md`

---

## Task ordering note

Tasks are ordered so `dart test` stays green after each one. `git` is added to the context *additively* first (Task 1), consumers migrate while `metadata` still exists (Tasks 2–3), and only then are `metadata` + `BuildMetadata` + `CollectMetadataAction` deleted (Task 4).

---

### Task 1: Add injectable `git` to `PipelineContext`

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Test: `test/pipeline_context_test.dart`

- [ ] **Step 1: Write the failing test**

Add this test inside the existing top-level `group('PipelineContext', ...)` in `test/pipeline_context_test.dart`, immediately after the closing `});` of the `group('metadata', ...)` block (around line 113). Also add the import and fake at the top of the file.

Add import (after the existing `pipeline_context.dart` import near line 4):

```dart
import 'package:flutter_ci_tools/src/utils/git_manager.dart';
```

Add this fake at the top of the file, before `void main() {`:

```dart
class _FakeGitManager implements GitManager {
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> resetHard() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<void> restoreWorkspace() async {}
  @override
  Future<String> getShortHash() async => 'abc1234';
  @override
  Future<String> getRecentCommits({int count = 10}) async => 'log';
  @override
  Future<String> getBranch() async => 'main';
  @override
  Future<String> getCurrentUser() async => 'Alice';
  @override
  Future<String> getLatestCommitBody() async => 'body';
}
```

Add this test group (after the `group('metadata', ...)` block):

```dart
    group('git', () {
      test('exposes the injected GitManager', () async {
        final git = _FakeGitManager();
        final c = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 12000,
          git: git,
        );
        expect(identical(c.git, git), isTrue);
        expect(await c.git.getBranch(), 'main');
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/pipeline_context_test.dart -n "exposes the injected GitManager"`
Expected: FAIL — `PipelineContext` has no named parameter `git` / no getter `git`.

- [ ] **Step 3: Add the `git` field to `PipelineContext`**

In `lib/src/pipeline_context.dart`, add the import at the top (after the existing `import 'build_metadata.dart';`):

```dart
import 'utils/git_manager.dart';
```

Change the constructor and add the field. Replace:

```dart
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    this.rawArgs = const [],
  });
```

with:

```dart
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    this.rawArgs = const [],
    GitManager? git,
  }) : git = git ?? GitManager.instance;

  /// Git accessor shared across all pipeline actions.
  final GitManager git;
```

Leave the existing `late BuildMetadata metadata;` field untouched for now (removed in Task 4).

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/pipeline_context_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart
git commit -m "feat: expose injectable GitManager on PipelineContext"
```

---

### Task 2: Migrate `FeishuBuildNotifyAction` to `context.git`

**Files:**
- Modify: `lib/src/actions/feishu_build_notify_action.dart`
- Test: `test/actions/feishu_build_notify_action_test.dart`

- [ ] **Step 1: Update the test to inject git instead of setting metadata**

In `test/actions/feishu_build_notify_action_test.dart`:

Replace the import line:

```dart
import 'package:flutter_ci_tools/src/build_metadata.dart';
```

with:

```dart
import 'package:flutter_ci_tools/src/utils/git_manager.dart';
```

Add this fake class after the `_FakeShellRunner` class (before `void main() {`):

```dart
class _FakeGitManager implements GitManager {
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> resetHard() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<void> restoreWorkspace() async {}
  @override
  Future<String> getShortHash() async => 'abc1234';
  @override
  Future<String> getRecentCommits({int count = 10}) async => 'commit1\ncommit2';
  @override
  Future<String> getBranch() async => 'main';
  @override
  Future<String> getCurrentUser() async => 'Alice';
  @override
  Future<String> getLatestCommitBody() async => 'release notes';
}
```

Replace the context construction block:

```dart
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
    )
      ..resolveBuildVersion(12042)
      ..metadata = BuildMetadata(
        branch: 'main',
        gitUser: 'Alice',
        gitHash: 'abc1234',
        recentCommits: 'commit1\ncommit2',
        commitBody: 'release notes',
      );
```

with:

```dart
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )..resolveBuildVersion(12042);
```

Add two assertions at the end of the test (after the existing `expect(shell.lastJson, contains('release notes'));`):

```dart
    expect(shell.lastJson, contains('main'));
    expect(shell.lastJson, contains('abc1234'));
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/feishu_build_notify_action_test.dart`
Expected: FAIL — the action still reads `context.metadata`, which is now never set, throwing `LateInitializationError`.

- [ ] **Step 3: Make `_formatMessage` async and read from `context.git`**

In `lib/src/actions/feishu_build_notify_action.dart`:

In the `run` method, change:

```dart
    final message = _formatMessage(context);
```

to:

```dart
    final message = await _formatMessage(context);
```

Replace the entire `_formatMessage` method:

```dart
  String _formatMessage(PipelineContext context) {
    const sep = '──────────────────────────';
    final m = context.metadata;
    final lines = <String>[
      '🚀 ${context.appName} 新版本 ${context.buildNumber} (${target.label})',
      'branch: ${m.branch}  by: ${m.gitUser}',
      sep,
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'git_hash:    ${m.gitHash}',
    ];
    if (downloadUrl != null) {
      lines
        ..add(sep)
        ..add('🔗 下载: $downloadUrl');
    }
    lines
      ..add(sep)
      ..add('最近提交:')
      ..add(m.recentCommits);
    if (m.commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(m.commitBody);
    }
    return lines.join('\n');
  }
```

with:

```dart
  Future<String> _formatMessage(PipelineContext context) async {
    const sep = '──────────────────────────';
    final git = context.git;
    final branch = await git.getBranch();
    final gitUser = await git.getCurrentUser();
    final gitHash = await git.getShortHash();
    final recentCommits = await git.getRecentCommits(count: 15);
    final commitBody = await git.getLatestCommitBody();
    final lines = <String>[
      '🚀 ${context.appName} 新版本 ${context.buildNumber} (${target.label})',
      'branch: $branch  by: $gitUser',
      sep,
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'git_hash:    $gitHash',
    ];
    if (downloadUrl != null) {
      lines
        ..add(sep)
        ..add('🔗 下载: $downloadUrl');
    }
    lines
      ..add(sep)
      ..add('最近提交:')
      ..add(recentCommits);
    if (commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(commitBody);
    }
    return lines.join('\n');
  }
```

Update the class doc comment. Replace:

```dart
/// Reads `context.buildName`, `context.buildNumber`,
/// and `context.metadata` to format the message text. Requires
/// `ResolveBuildVersionAction` and `CollectMetadataAction` earlier in the
/// pipeline body.
```

with:

```dart
/// Reads `context.buildName`, `context.buildNumber`, and `context.git` to
/// format the message text. Requires `ResolveBuildVersionAction` earlier in
/// the pipeline body.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/feishu_build_notify_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/feishu_build_notify_action.dart test/actions/feishu_build_notify_action_test.dart
git commit -m "refactor: read git data from context.git in FeishuBuildNotifyAction"
```

---

### Task 3: Migrate example pipelines off `metadata`

**Files:**
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`
- Modify: `example/ci/pipelines/android_test_pipeline.dart`

No automated test covers the example pipelines; verification is a static analyze.

- [ ] **Step 1: Remove the `CollectMetadataAction()` calls**

In each of the three files, delete the line:

```dart
    await runAction(CollectMetadataAction());
```

(`test_pipeline.dart:24`, `prod_pipeline.dart:24`, `android_test_pipeline.dart:36`).

- [ ] **Step 2: Make `_pgyerDescription` read from `context.git`**

Only `test_pipeline.dart` uses `context.metadata` (in `_pgyerDescription`). Replace:

```dart
  String _pgyerDescription() {
    final m = context.metadata;
    return [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         test',
      'git_hash:    ${m.gitHash}',
      '',
      'recent commits:',
      m.recentCommits,
    ].join('\n');
  }
```

with:

```dart
  Future<String> _pgyerDescription() async {
    final git = context.git;
    final gitHash = await git.getShortHash();
    final recentCommits = await git.getRecentCommits(count: 15);
    return [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         test',
      'git_hash:    $gitHash',
      '',
      'recent commits:',
      recentCommits,
    ].join('\n');
  }
```

- [ ] **Step 3: Await the new async `_pgyerDescription` at its call site**

In `test_pipeline.dart`, the call is at line 49 inside `_deployToPgyer()` (already `async`):

```dart
      description: _pgyerDescription(),
```

Change it to:

```dart
      description: await _pgyerDescription(),
```

- [ ] **Step 4: Verify the example analyzes cleanly**

Run: `cd example && dart analyze ci && cd ..`
Expected: No issues. (No remaining references to `context.metadata` or `CollectMetadataAction`.)

- [ ] **Step 5: Commit**

```bash
git add example/ci/pipelines/test_pipeline.dart example/ci/pipelines/prod_pipeline.dart example/ci/pipelines/android_test_pipeline.dart
git commit -m "refactor: migrate example pipelines off context.metadata"
```

---

### Task 4: Delete `BuildMetadata`, `CollectMetadataAction`, `metadata` field, and dead tests

**Files:**
- Delete: `lib/src/build_metadata.dart`
- Delete: `lib/src/actions/collect_metadata_action.dart`
- Delete: `test/build_metadata_test.dart`
- Delete: `test/actions/collect_metadata_action_test.dart`
- Modify: `lib/flutter_ci_tools.dart` (remove two exports)
- Modify: `lib/src/pipeline_context.dart` (remove `metadata` field + import)
- Modify: `test/pipeline_context_test.dart` (remove the `metadata` group + import)

- [ ] **Step 1: Remove the `metadata` group from the context test**

In `test/pipeline_context_test.dart`, delete the entire block:

```dart
    group('metadata', () {
      test('metadata can be set and read', () {
        final meta = BuildMetadata(
          branch: 'main',
          gitUser: 'Alice',
          gitHash: 'abc1234',
          recentCommits: 'commits',
          commitBody: 'body',
        );
        ctx.metadata = meta;
        expect(ctx.metadata.branch, 'main');
        expect(ctx.metadata.gitHash, 'abc1234');
      });
    });
```

Also delete the now-unused import:

```dart
import 'package:flutter_ci_tools/src/build_metadata.dart';
```

- [ ] **Step 2: Remove the `metadata` field from `PipelineContext`**

In `lib/src/pipeline_context.dart`, delete the field and its doc comment:

```dart
  /// Git and build metadata, populated by `CollectMetadataAction`.
  late BuildMetadata metadata;
```

Delete the now-unused import:

```dart
import 'build_metadata.dart';
```

- [ ] **Step 3: Remove the barrel exports**

In `lib/flutter_ci_tools.dart`, delete these two lines:

```dart
export 'src/actions/collect_metadata_action.dart';
```
```dart
export 'src/build_metadata.dart';
```

- [ ] **Step 4: Delete the source and test files**

```bash
git rm lib/src/build_metadata.dart lib/src/actions/collect_metadata_action.dart test/build_metadata_test.dart test/actions/collect_metadata_action_test.dart
```

- [ ] **Step 5: Verify the whole suite passes and nothing references the deleted symbols**

Run: `dart test`
Expected: PASS, no compile errors.

Run: `grep -rn "BuildMetadata\|CollectMetadataAction\|context.metadata\|\.metadata =" lib test example/ci`
Expected: No output (zero remaining references).

Run: `dart analyze`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: delete BuildMetadata and CollectMetadataAction"
```

---

## Final verification

- [ ] Run full suite: `dart test` — all green.
- [ ] Run `dart analyze` (root) and `cd example && dart analyze && cd ..` — no issues.
- [ ] Confirm `grep -rn "BuildMetadata" .` returns only matches inside `docs/` (spec/plan), not in `lib/`, `test/`, or `example/`.
