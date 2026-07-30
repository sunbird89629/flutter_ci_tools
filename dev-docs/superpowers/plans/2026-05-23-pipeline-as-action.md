# BuildPipeline as Pure Lifecycle Container — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip `BuildPipeline` down to a pure lifecycle container (`beforeBuild / body / afterBuild` + `runAction` helper) and convert every concrete build / deploy / notification step into a typed `PipelineAction<R>`, mirroring the shape already used for upload and notify actions.

**Architecture:** Two phases of additive work (generic `PipelineAction<R>` foundation, then nine new build-lifecycle Actions and one new notification Action) followed by a coordinated rip-and-replace that reshapes the existing Actions to typed constructor params, removes the string-keyed store from `PipelineContext`, slims `BuildPipeline` to lifecycle hooks only, and migrates the three example pipelines and the registry.

**Tech Stack:** Dart 3 (no Flutter dependency in the library itself), `package:test` for unit tests, no codegen.

**Spec:** `docs/superpowers/specs/2026-05-23-pipeline-as-action-design.md`

---

## File layout (created or modified)

**Created (10 new Action files + their tests):**

- `lib/src/actions/resolve_build_version_action.dart`
- `lib/src/actions/collect_metadata_action.dart`
- `lib/src/actions/check_git_status_action.dart`
- `lib/src/actions/swap_info_plist_action.dart`
- `lib/src/actions/clean_project_action.dart`
- `lib/src/actions/build_android_action.dart` (also exports `AndroidBuildType` enum)
- `lib/src/actions/build_ios_action.dart`
- `lib/src/actions/push_build_tag_action.dart`
- `lib/src/actions/restore_workspace_action.dart`
- `lib/src/actions/feishu_build_notify_action.dart` (also exports `DeployTarget` enum)
- plus one matching `test/actions/<name>_test.dart` per Action

**Modified:**

- `lib/src/actions/pipeline_action.dart` — `PipelineAction` becomes `PipelineAction<R>`
- `lib/src/actions/pgyer_upload_action.dart` — typed constructor params, returns `String` (URL)
- `lib/src/actions/google_play_action.dart` — typed constructor params
- `lib/src/actions/app_store_action.dart` — typed constructor params
- `lib/src/actions/feishu_notify_action.dart` — `message` becomes a constructor param
- `lib/src/pipeline_context.dart` — add `platforms`; remove `set / get / tryGet / has / remove / _store`
- `lib/src/pipeline.dart` — removes service deps, old getters, old hooks, three `run*` methods, `_buildAndroid / _buildIOS / cleanProject / buildPrepare / buildFeishuMessage`; adds `body() / afterBuild() / run(Set<AppPlatform>) / runAction<R>`; `AndroidBuildType` and `DeployTarget` enums leave this file
- `lib/src/pipeline_registry.dart` — calls `pipeline.run(Set<AppPlatform>)` instead of `run() / runAndroidOnly() / runIOSOnly()`
- `lib/flutter_ci_tools.dart` — exports the 10 new Action files
- `test/pipeline_test.dart` — rewritten for new base shape
- `test/pipeline_context_test.dart` — adjusted for new constructor + removed APIs
- `test/actions/pgyer_upload_action_test.dart`, `test/actions/google_play_action_test.dart`, `test/actions/app_store_action_test.dart`, `test/actions/feishu_notify_action_test.dart`, `test/actions/pipeline_action_test.dart` — adjusted for typed-param constructors and `<R>` return type
- `example/ci/pipelines/test_pipeline.dart`, `example/ci/pipelines/prod_pipeline.dart`, `example/ci/pipelines/android_test_pipeline.dart` — rewritten to override `body()` instead of old getters / hooks

Each new Action file holds one Action class plus an in-file enum if applicable. Tests live mirror-style under `test/actions/`. No subdirectory inside `actions/` — keeps consistency with the existing flat layout.

---

## Phase 1: Foundation

### Task 1: Make `PipelineAction` generic on its return type

**Files:**
- Modify: `lib/src/actions/pipeline_action.dart`
- Modify: `lib/src/actions/pgyer_upload_action.dart:14`
- Modify: `lib/src/actions/google_play_action.dart:14`
- Modify: `lib/src/actions/app_store_action.dart:15`
- Modify: `lib/src/actions/feishu_notify_action.dart:12`
- Modify: `test/actions/pipeline_action_test.dart`

- [ ] **Step 1: Update the abstract class**

Replace `lib/src/actions/pipeline_action.dart` with:

```dart
import '../pipeline_context.dart';

/// A single deploy/notification step in a pipeline.
///
/// Actions receive a [PipelineContext] and produce a typed [R] result.
/// Use [R] = `void` when the action has no return value.
abstract class PipelineAction<R> {
  /// Human-readable name; used as the log section header by `BuildPipeline.runAction`.
  String get name;

  /// Executes this action against [context] and returns its result.
  Future<R> run(PipelineContext context);
}
```

- [ ] **Step 2: Update existing concrete actions to `PipelineAction<void>`**

Change four `extends PipelineAction` to `extends PipelineAction<void>`:

- `pgyer_upload_action.dart:14` → `class PgyerUploadAction extends PipelineAction<void> {`
- `google_play_action.dart:14` → `class GooglePlayUploadAction extends PipelineAction<void> {`
- `app_store_action.dart:15` → `class AppStoreUploadAction extends PipelineAction<void> {`
- `feishu_notify_action.dart:12` → `class FeishuNotifyAction extends PipelineAction<void> {`

- [ ] **Step 3: Adjust `test/actions/pipeline_action_test.dart` for the generic shape**

If the existing test instantiates a fake subclass of `PipelineAction`, update it to `PipelineAction<void>`. Read the file first, then add `<void>` to every direct `PipelineAction` reference. No test logic changes.

- [ ] **Step 4: Run the full test suite**

Run: `dart test`
Expected: PASS — all existing tests still green; only annotation changed.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/pipeline_action.dart \
        lib/src/actions/pgyer_upload_action.dart \
        lib/src/actions/google_play_action.dart \
        lib/src/actions/app_store_action.dart \
        lib/src/actions/feishu_notify_action.dart \
        test/actions/pipeline_action_test.dart
git commit -m "refactor: make PipelineAction generic on return type"
```

---

## Phase 2: New build-lifecycle Actions (additive, TDD)

Each task in this phase follows the same pattern: write a failing test against a fake service, implement the Action as a thin wrapper that reads from `PipelineContext` and delegates to the existing service, run tests, commit. The old `BuildPipeline` flow keeps working unchanged because nothing yet depends on these new Actions.

### Task 2: `ResolveBuildVersionAction`

Wraps `VersionManager.computeNextBuildNumber` and writes `context.buildNumber`.

**Files:**
- Create: `lib/src/actions/resolve_build_version_action.dart`
- Create: `test/actions/resolve_build_version_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/resolve_build_version_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/resolve_build_version_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  int nextBuildNumber = 12345;
  int? receivedSeed;

  @override
  Future<int?> fetchLatestBuildNumber() async => null;

  @override
  Future<int> computeNextBuildNumber(int seed) async {
    receivedSeed = seed;
    return nextBuildNumber;
  }

  @override
  Future<void> pushNewBuildTag(int buildNumber) async {}

  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

void main() {
  test('ResolveBuildVersionAction sets context.buildNumber from VersionManager', () async {
    final version = _FakeVersionManager()..nextBuildNumber = 12001;
    final action = ResolveBuildVersionAction(versionManager: version);
    final context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    );

    await action.run(context);

    expect(action.name, 'Resolve Build Version');
    expect(version.receivedSeed, 12000);
    expect(context.buildNumber, 12001);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/resolve_build_version_action_test.dart`
Expected: FAIL — `ResolveBuildVersionAction` not defined.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/resolve_build_version_action.dart`:

```dart
import '../logger.dart';
import '../pipeline_context.dart';
import '../version_manager.dart';
import 'pipeline_action.dart';

/// Computes the next build number via [VersionManager] and writes it to
/// [PipelineContext.buildNumber].
class ResolveBuildVersionAction extends PipelineAction<void> {
  ResolveBuildVersionAction({VersionManager? versionManager})
      : _versionManager = versionManager ?? DefaultVersionManager();

  final VersionManager _versionManager;

  @override
  String get name => 'Resolve Build Version';

  @override
  Future<void> run(PipelineContext context) async {
    final number = await _versionManager.computeNextBuildNumber(
      context.config.seedBuildNumber,
    );
    context.buildNumber = number;
    Logger.info(
      'Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}',
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/resolve_build_version_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/resolve_build_version_action.dart \
        test/actions/resolve_build_version_action_test.dart
git commit -m "feat: add ResolveBuildVersionAction"
```

---

### Task 3: `CollectMetadataAction`

Wraps `BuildMetadata.collect(gitManager)` and writes `context.metadata`.

**Files:**
- Create: `lib/src/actions/collect_metadata_action.dart`
- Create: `test/actions/collect_metadata_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/collect_metadata_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/collect_metadata_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeGitManager implements GitManager {
  @override Future<void> checkClean() async {}
  @override Future<void> resetHard() async {}
  @override Future<void> clean() async {}
  @override Future<void> restoreWorkspace() async {}
  @override Future<String> getShortHash() async => 'abc1234';
  @override Future<String> getRecentCommits({int count = 10}) async => 'log';
  @override Future<String> getBranch() async => 'main';
  @override Future<String> getCurrentUser() async => 'Alice';
  @override Future<String> getLatestCommitBody() async => 'body';
}

void main() {
  test('CollectMetadataAction populates context.metadata via GitManager', () async {
    final action = CollectMetadataAction(gitManager: _FakeGitManager());
    final context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    );

    await action.run(context);

    expect(action.name, 'Collect Build Metadata');
    expect(context.metadata.branch, 'main');
    expect(context.metadata.gitUser, 'Alice');
    expect(context.metadata.gitHash, 'abc1234');
    expect(context.metadata.commitBody, 'body');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/collect_metadata_action_test.dart`
Expected: FAIL — `CollectMetadataAction` not defined.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/collect_metadata_action.dart`:

```dart
import '../build_metadata.dart';
import '../git_manager.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Collects git/build metadata via [GitManager] and writes it to
/// [PipelineContext.metadata].
class CollectMetadataAction extends PipelineAction<void> {
  CollectMetadataAction({GitManager? gitManager})
      : _gitManager = gitManager ?? DefaultGitManager();

  final GitManager _gitManager;

  @override
  String get name => 'Collect Build Metadata';

  @override
  Future<void> run(PipelineContext context) async {
    context.metadata = await BuildMetadata.collect(_gitManager);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/collect_metadata_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/collect_metadata_action.dart \
        test/actions/collect_metadata_action_test.dart
git commit -m "feat: add CollectMetadataAction"
```

---

### Task 4: `CheckGitStatusAction`

Thin wrapper around `GitManager.checkClean()`.

**Files:**
- Create: `lib/src/actions/check_git_status_action.dart`
- Create: `test/actions/check_git_status_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/check_git_status_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/check_git_status_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeGitManager implements GitManager {
  bool isClean = true;
  bool checkCalled = false;

  @override
  Future<void> checkClean() async {
    checkCalled = true;
    if (!isClean) throw GitException('dirty', 1);
  }

  @override Future<void> resetHard() async {}
  @override Future<void> clean() async {}
  @override Future<void> restoreWorkspace() async {}
  @override Future<String> getShortHash() async => '';
  @override Future<String> getRecentCommits({int count = 10}) async => '';
  @override Future<String> getBranch() async => '';
  @override Future<String> getCurrentUser() async => '';
  @override Future<String> getLatestCommitBody() async => '';
}

void main() {
  late _FakeGitManager git;
  late PipelineContext context;

  setUp(() {
    git = _FakeGitManager();
    context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    );
  });

  test('CheckGitStatusAction delegates to GitManager.checkClean', () async {
    final action = CheckGitStatusAction(gitManager: git);
    await action.run(context);
    expect(action.name, 'Check Git Status');
    expect(git.checkCalled, isTrue);
  });

  test('CheckGitStatusAction rethrows GitException on dirty tree', () async {
    git.isClean = false;
    final action = CheckGitStatusAction(gitManager: git);
    expect(() => action.run(context), throwsA(isA<GitException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/check_git_status_action_test.dart`
Expected: FAIL — `CheckGitStatusAction` not defined.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/check_git_status_action.dart`:

```dart
import '../git_manager.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Aborts the pipeline if the working tree has uncommitted changes.
class CheckGitStatusAction extends PipelineAction<void> {
  CheckGitStatusAction({GitManager? gitManager})
      : _gitManager = gitManager ?? DefaultGitManager();

  final GitManager _gitManager;

  @override
  String get name => 'Check Git Status';

  @override
  Future<void> run(PipelineContext context) => _gitManager.checkClean();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/check_git_status_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/check_git_status_action.dart \
        test/actions/check_git_status_action_test.dart
git commit -m "feat: add CheckGitStatusAction"
```

---

### Task 5: `SwapInfoPlistAction`

Renames `ios/Runner/Info.plist` ↔ `ios/Runner/Info.plist.product`. Replaces the old `buildPrepare()` branch.

**Files:**
- Create: `lib/src/actions/swap_info_plist_action.dart`
- Create: `test/actions/swap_info_plist_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/swap_info_plist_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/swap_info_plist_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('swap_info_plist_test_');
    final ios = Directory('${tmp.path}/ios/Runner')..createSync(recursive: true);
    File('${ios.path}/Info.plist').writeAsStringSync('original');
    File('${ios.path}/Info.plist.product').writeAsStringSync('product');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('SwapInfoPlistAction renames Info.plist ↔ Info.plist.product', () async {
    final cwd = Directory.current;
    Directory.current = tmp;
    try {
      final action = SwapInfoPlistAction();
      await action.run(PipelineContext(
        config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
      ));

      expect(action.name, 'Swap Info.plist for Product Variant');
      expect(File('ios/Runner/Info.plist').readAsStringSync(), 'product');
      expect(File('ios/Runner/Info.plist.backup').readAsStringSync(), 'original');
    } finally {
      Directory.current = cwd;
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/swap_info_plist_action_test.dart`
Expected: FAIL — `SwapInfoPlistAction` not defined.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/swap_info_plist_action.dart`:

```dart
import 'dart:io';

import '../logger.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Swaps `ios/Runner/Info.plist` with `ios/Runner/Info.plist.product`,
/// backing up the original to `Info.plist.backup`.
///
/// Used by pipelines that build a "product" variant of the iOS app.
/// Pair with `RestoreWorkspaceAction` in `afterBuild` to undo the swap.
class SwapInfoPlistAction extends PipelineAction<void> {
  @override
  String get name => 'Swap Info.plist for Product Variant';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('Swapping Info.plist for product environment');
    File('ios/Runner/Info.plist').renameSync('ios/Runner/Info.plist.backup');
    File('ios/Runner/Info.plist.product').renameSync('ios/Runner/Info.plist');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/swap_info_plist_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/swap_info_plist_action.dart \
        test/actions/swap_info_plist_action_test.dart
git commit -m "feat: add SwapInfoPlistAction"
```

---

### Task 6: `CleanProjectAction`

Runs `fvm flutter clean` + `fvm flutter pub get`.

**Files:**
- Create: `lib/src/actions/clean_project_action.dart`
- Create: `test/actions/clean_project_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/clean_project_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/clean_project_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> calls = [];
  @override
  Future<void> run(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
  }
  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  test('CleanProjectAction runs flutter clean then pub get', () async {
    final shell = _FakeShellRunner();
    final action = CleanProjectAction(shellRunner: shell);

    await action.run(PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    ));

    expect(action.name, 'Clean Project');
    expect(shell.calls, [
      'fvm flutter clean',
      'fvm flutter pub get',
    ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/clean_project_action_test.dart`
Expected: FAIL — `CleanProjectAction` not defined.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/clean_project_action.dart`:

```dart
import '../default_shell_runner.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Runs `fvm flutter clean` followed by `fvm flutter pub get`.
class CleanProjectAction extends PipelineAction<void> {
  CleanProjectAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Clean Project';

  @override
  Future<void> run(PipelineContext context) async {
    await _shellRunner.run('fvm', ['flutter', 'clean']);
    await _shellRunner.run('fvm', ['flutter', 'pub', 'get']);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/clean_project_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/clean_project_action.dart \
        test/actions/clean_project_action_test.dart
git commit -m "feat: add CleanProjectAction"
```

---

### Task 7: `BuildAndroidAction` (also relocates `AndroidBuildType` enum)

Wraps `AndroidBuilder.buildApk / buildAppBundle`. Returns the built `File`.

**Files:**
- Create: `lib/src/actions/build_android_action.dart` (contains `AndroidBuildType` enum)
- Create: `test/actions/build_android_action_test.dart`

`AndroidBuildType` currently lives in `lib/src/pipeline.dart`. It is **not** deleted there yet — it stays in both files temporarily to keep `BuildPipeline` compiling. The old declaration is removed in Phase 4 (Task 13).

- [ ] **Step 1: Write the failing test**

Create `test/actions/build_android_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/build_android_action.dart';
import 'package:flutter_ci_tools/src/builders/android_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeAndroidBuilder extends AndroidBuilder {
  _FakeAndroidBuilder() : super();
  final List<String> calls = [];

  @override
  Future<File> buildApk({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    calls.add('apk buildName=$buildName buildNumber=$buildNumber envName=$envName');
    return File('build/app-release.apk');
  }

  @override
  Future<File> buildAppBundle({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    calls.add('aab buildName=$buildName buildNumber=$buildNumber envName=$envName');
    return File('build/app-release.aab');
  }
}

void main() {
  late PipelineContext context;
  late _FakeAndroidBuilder builder;

  setUp(() {
    builder = _FakeAndroidBuilder();
    context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    )..buildNumber = 12001;
  });

  test('BuildAndroidAction(apk) returns apk file and forwards build args', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.apk,
      androidBuilder: builder,
    );

    final file = await action.run(context);

    expect(action.name, 'Build Android');
    expect(file.path, endsWith('.apk'));
    expect(builder.calls, [
      'apk buildName=1.2.0 buildNumber=12001 envName=prod',
    ]);
  });

  test('BuildAndroidAction(appbundle) returns aab file', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.appbundle,
      androidBuilder: builder,
    );

    final file = await action.run(context);

    expect(file.path, endsWith('.aab'));
    expect(builder.calls, [
      'aab buildName=1.2.0 buildNumber=12001 envName=prod',
    ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/build_android_action_test.dart`
Expected: FAIL — `BuildAndroidAction` / `AndroidBuildType` not defined in `actions/build_android_action.dart`.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/build_android_action.dart`:

```dart
import 'dart:io';

import '../builders/android_builder.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Android build output format.
enum AndroidBuildType {
  /// Standard APK package.
  apk,

  /// Android App Bundle for Play Store upload.
  appbundle,
}

/// Builds an Android artifact (APK or AAB) and returns the output file.
class BuildAndroidAction extends PipelineAction<File> {
  BuildAndroidAction({
    required this.envName,
    required this.buildType,
    AndroidBuilder? androidBuilder,
  }) : _androidBuilder = androidBuilder ?? AndroidBuilder();

  final String envName;
  final AndroidBuildType buildType;
  final AndroidBuilder _androidBuilder;

  @override
  String get name => 'Build Android';

  @override
  Future<File> run(PipelineContext context) async {
    switch (buildType) {
      case AndroidBuildType.apk:
        return _androidBuilder.buildApk(
          buildName: context.buildName,
          buildNumber: context.buildNumber,
          envName: envName,
        );
      case AndroidBuildType.appbundle:
        return _androidBuilder.buildAppBundle(
          buildName: context.buildName,
          buildNumber: context.buildNumber,
          envName: envName,
        );
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/build_android_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/build_android_action.dart \
        test/actions/build_android_action_test.dart
git commit -m "feat: add BuildAndroidAction (with AndroidBuildType enum)"
```

---

### Task 8: `BuildIOSAction`

Wraps `IOSBuilder.buildIpa`. Returns the built `File`.

**Files:**
- Create: `lib/src/actions/build_ios_action.dart`
- Create: `test/actions/build_ios_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/build_ios_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/build_ios_action.dart';
import 'package:flutter_ci_tools/src/builders/ios_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeIOSBuilder extends IOSBuilder {
  _FakeIOSBuilder() : super();
  String? receivedExport;
  String? receivedEnv;

  @override
  Future<File> buildIpa({
    required String buildName,
    required int buildNumber,
    required String envName,
    required String exportMethod,
  }) async {
    receivedExport = exportMethod;
    receivedEnv = envName;
    return File('build/ios/ipa/app.ipa');
  }
}

void main() {
  test('BuildIOSAction returns ipa and forwards export method + env', () async {
    final builder = _FakeIOSBuilder();
    final context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    )..buildNumber = 12001;

    final action = BuildIOSAction(
      envName: 'prod',
      exportMethod: 'app-store',
      iosBuilder: builder,
    );
    final file = await action.run(context);

    expect(action.name, 'Build iOS');
    expect(file.path, endsWith('.ipa'));
    expect(builder.receivedExport, 'app-store');
    expect(builder.receivedEnv, 'prod');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/build_ios_action_test.dart`
Expected: FAIL — `BuildIOSAction` not defined.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/build_ios_action.dart`:

```dart
import 'dart:io';

import '../builders/ios_builder.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Builds an iOS IPA and returns the output file.
class BuildIOSAction extends PipelineAction<File> {
  BuildIOSAction({
    required this.envName,
    required this.exportMethod,
    IOSBuilder? iosBuilder,
  }) : _iosBuilder = iosBuilder ?? IOSBuilder();

  final String envName;
  final String exportMethod;
  final IOSBuilder _iosBuilder;

  @override
  String get name => 'Build iOS';

  @override
  Future<File> run(PipelineContext context) {
    return _iosBuilder.buildIpa(
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      envName: envName,
      exportMethod: exportMethod,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/build_ios_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/build_ios_action.dart \
        test/actions/build_ios_action_test.dart
git commit -m "feat: add BuildIOSAction"
```

---

### Task 9: `PushBuildTagAction`

Wraps `VersionManager.pushNewBuildTag(context.buildNumber)`.

**Files:**
- Create: `lib/src/actions/push_build_tag_action.dart`
- Create: `test/actions/push_build_tag_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/push_build_tag_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/push_build_tag_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  final List<int> pushed = [];

  @override Future<int?> fetchLatestBuildNumber() async => null;
  @override Future<int> computeNextBuildNumber(int seed) async => seed;
  @override Future<void> pushNewBuildTag(int buildNumber) async { pushed.add(buildNumber); }
  @override Future<void> interactiveBumpAndPush(int seed) async {}
}

void main() {
  test('PushBuildTagAction delegates buildNumber to VersionManager.pushNewBuildTag', () async {
    final version = _FakeVersionManager();
    final context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    )..buildNumber = 12042;

    final action = PushBuildTagAction(versionManager: version);
    await action.run(context);

    expect(action.name, 'Push Build Tag');
    expect(version.pushed, [12042]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/push_build_tag_action_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/push_build_tag_action.dart`:

```dart
import '../pipeline_context.dart';
import '../version_manager.dart';
import 'pipeline_action.dart';

/// Creates and force-pushes a `builds/<buildNumber>` tag for this build.
class PushBuildTagAction extends PipelineAction<void> {
  PushBuildTagAction({VersionManager? versionManager})
      : _versionManager = versionManager ?? DefaultVersionManager();

  final VersionManager _versionManager;

  @override
  String get name => 'Push Build Tag';

  @override
  Future<void> run(PipelineContext context) =>
      _versionManager.pushNewBuildTag(context.buildNumber);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/push_build_tag_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/push_build_tag_action.dart \
        test/actions/push_build_tag_action_test.dart
git commit -m "feat: add PushBuildTagAction"
```

---

### Task 10: `RestoreWorkspaceAction`

Wraps `GitManager.restoreWorkspace()`. Intended to be returned from `afterBuild()`.

**Files:**
- Create: `lib/src/actions/restore_workspace_action.dart`
- Create: `test/actions/restore_workspace_action_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/actions/restore_workspace_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/restore_workspace_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeGitManager implements GitManager {
  bool restored = false;

  @override Future<void> checkClean() async {}
  @override Future<void> resetHard() async {}
  @override Future<void> clean() async {}
  @override Future<void> restoreWorkspace() async { restored = true; }
  @override Future<String> getShortHash() async => '';
  @override Future<String> getRecentCommits({int count = 10}) async => '';
  @override Future<String> getBranch() async => '';
  @override Future<String> getCurrentUser() async => '';
  @override Future<String> getLatestCommitBody() async => '';
}

void main() {
  test('RestoreWorkspaceAction delegates to GitManager.restoreWorkspace', () async {
    final git = _FakeGitManager();
    final action = RestoreWorkspaceAction(gitManager: git);
    await action.run(PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    ));

    expect(action.name, 'Restore Workspace');
    expect(git.restored, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/restore_workspace_action_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/restore_workspace_action.dart`:

```dart
import '../git_manager.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Runs `git reset --hard HEAD` + `git clean -fd` to restore a clean tree.
///
/// Typically returned from `BuildPipeline.afterBuild()` so it runs regardless
/// of whether the main body succeeded.
class RestoreWorkspaceAction extends PipelineAction<void> {
  RestoreWorkspaceAction({GitManager? gitManager})
      : _gitManager = gitManager ?? DefaultGitManager();

  final GitManager _gitManager;

  @override
  String get name => 'Restore Workspace';

  @override
  Future<void> run(PipelineContext context) => _gitManager.restoreWorkspace();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/restore_workspace_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/restore_workspace_action.dart \
        test/actions/restore_workspace_action_test.dart
git commit -m "feat: add RestoreWorkspaceAction"
```

---

## Phase 3: New `FeishuBuildNotifyAction`

### Task 11: `FeishuBuildNotifyAction` (also relocates `DeployTarget` enum)

High-level notify action that formats the standard build-notification text and delegates to the low-level `FeishuNotifyAction`.

**Files:**
- Create: `lib/src/actions/feishu_build_notify_action.dart` (contains `DeployTarget` enum)
- Create: `test/actions/feishu_build_notify_action_test.dart`

`DeployTarget` currently lives in `lib/src/pipeline.dart`. It is **not** deleted there yet — it stays in both files temporarily to keep `BuildPipeline.buildFeishuMessage` compiling. The old declaration is removed in Phase 4 (Task 13).

At this point `FeishuNotifyAction` still reads `notification_message` from `context.get<String>(...)` — that is fine, the new high-level action will populate `context` exactly as the old call sites do. (`FeishuNotifyAction` itself is reshaped to a typed `message` param in Task 14.)

- [ ] **Step 1: Write the failing test**

Create `test/actions/feishu_build_notify_action_test.dart`:

```dart
import 'package:flutter_ci_tools/src/actions/feishu_build_notify_action.dart';
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  String? lastJson;
  @override Future<void> run(String exe, List<String> args) async {}
  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final dIdx = args.indexOf('-d');
    if (dIdx >= 0 && dIdx + 1 < args.length) lastJson = args[dIdx + 1];
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('FeishuBuildNotifyAction sends formatted build message via webhook', () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      config: const CIToolsConfig(
        appName: 'TestApp',
        seedBuildNumber: 12000,
        feishuWebhookUrl: 'https://open.feishu.cn/hook',
      ),
    )
      ..buildNumber = 12042
      ..metadata = BuildMetadata(
        branch: 'main',
        gitUser: 'Alice',
        gitHash: 'abc1234',
        recentCommits: 'commit1\ncommit2',
        commitBody: 'release notes',
      );

    final action = FeishuBuildNotifyAction(
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      downloadUrl: 'https://example.com/dl',
      shellRunner: shell,
    );
    await action.run(context);

    expect(action.name, 'Send Feishu Build Notification');
    expect(shell.lastJson, contains('TestApp'));
    expect(shell.lastJson, contains('12042'));
    expect(shell.lastJson, contains('Android'));
    expect(shell.lastJson, contains('Pgyer'));
    expect(shell.lastJson, contains('https://example.com/dl'));
    expect(shell.lastJson, contains('release notes'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/actions/feishu_build_notify_action_test.dart`
Expected: FAIL — `FeishuBuildNotifyAction` / `DeployTarget` not defined in the new file.

- [ ] **Step 3: Implement the Action**

Create `lib/src/actions/feishu_build_notify_action.dart`:

```dart
import 'dart:convert';

import '../default_shell_runner.dart';
import '../logger.dart';
import '../pipeline.dart' show AppPlatform;
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Destination where a build artifact will be uploaded.
///
/// Used to label the standard Feishu build-notification message.
enum DeployTarget {
  pgyer('Pgyer'),
  googlePlay('Google Play'),
  appStore('App Store');

  final String label;
  const DeployTarget(this.label);
}

/// Sends the standard "new build" message to Feishu.
///
/// Reads `config.feishuWebhookUrl` and uses `config.appName`, `buildNumber`,
/// and `metadata` from [PipelineContext] to format the message text.
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({
    required this.platform,
    required this.target,
    this.downloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final AppPlatform platform;
  final DeployTarget target;
  final String? downloadUrl;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final message = _formatMessage(context);
    final webhookUrl = context.config.feishuWebhookUrl!;
    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });
    Logger.info('Sending Feishu notification...');
    final result = await _shellRunner.runAndCapture('curl', [
      '-X', 'POST',
      '-H', 'Content-Type: application/json',
      '-d', jsonMessage,
      webhookUrl,
    ]);
    if (result.exitCode == 0) {
      Logger.success('Feishu notification sent.');
    } else {
      Logger.error('Failed to send Feishu notification: ${result.stderr}');
    }
  }

  String _formatMessage(PipelineContext context) {
    const sep = '──────────────────────────';
    final m = context.metadata;
    final lines = <String>[
      '🚀 ${context.config.appName} 新版本 ${context.buildNumber} (${platform.label} · ${target.label})',
      'branch: ${m.branch}  by: ${m.gitUser}',
      sep,
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'git_hash:    ${m.gitHash}',
    ];
    if (downloadUrl != null) {
      lines..add(sep)..add('🔗 下载: $downloadUrl');
    }
    lines..add(sep)..add('最近提交:')..add(m.recentCommits);
    if (m.commitBody.isNotEmpty) {
      lines..add(sep)..add('版本说明:')..add(m.commitBody);
    }
    return lines.join('\n');
  }
}
```

> The formatted message above intentionally drops the `env` and `api_host` lines that the old `BuildPipeline.buildFeishuMessage` printed — those values lived on the deleted `envName / apiHost` getters and have no equivalent on the new context. Subclasses that need env-specific text can use the low-level `FeishuNotifyAction(message: ...)` instead.

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/actions/feishu_build_notify_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/feishu_build_notify_action.dart \
        test/actions/feishu_build_notify_action_test.dart
git commit -m "feat: add FeishuBuildNotifyAction (with DeployTarget enum)"
```

---

## Phase 4: The big switch

This phase removes the old surface and switches the existing upload / notify Actions to typed params + return values. Each task touches multiple files because the changes are interdependent. The order is chosen so that after each task the project still compiles and `dart test` passes (example pipelines under `example/` are updated last; until then they will not compile, but the library and its tests do).

### Task 12: Reshape `PipelineContext`

Add `platforms`; remove the string-keyed store and the `late buildName` getter stays.

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Modify: `test/pipeline_context_test.dart`
- Modify: each existing action and action test that uses `context.set / get / tryGet / has / remove` — these calls disappear in Task 14, so for this task replace them with TODO-free workarounds (see Step 4 below).

- [ ] **Step 1: Inspect tests and call sites**

Run: `grep -rn 'context\.\(set\|get\|tryGet\|has\|remove\)' lib test`
Note every match — they will all be removed in this task or Task 14.

- [ ] **Step 2: Update `PipelineContext`**

Replace `lib/src/pipeline_context.dart` with:

```dart
import 'build_metadata.dart';
import 'config.dart';
import 'pipeline.dart' show AppPlatform;

/// Shared, read-only context passed through all pipeline steps.
///
/// Holds the config and the platform filter (set at pipeline launch), plus
/// build-time fields populated by lifecycle actions.
class PipelineContext {
  PipelineContext({required this.config, required this.platforms});

  /// Application-level configuration (name, API keys, seed build number).
  final CIToolsConfig config;

  /// Platforms this pipeline run targets (e.g. `{android}`, `{android, ios}`).
  final Set<AppPlatform> platforms;

  /// Git and build metadata, populated by `CollectMetadataAction`.
  late BuildMetadata metadata;

  /// Resolved build number, populated by `ResolveBuildVersionAction`.
  late int buildNumber;

  /// Human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }
}
```

- [ ] **Step 3: Rewrite `test/pipeline_context_test.dart`**

Replace the file with tests that exercise only the surviving API:

```dart
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

void main() {
  group('PipelineContext', () {
    test('exposes config and platforms', () {
      final context = PipelineContext(
        config: const CIToolsConfig(appName: 'A', seedBuildNumber: 10000),
        platforms: {AppPlatform.android},
      );
      expect(context.config.appName, 'A');
      expect(context.platforms, {AppPlatform.android});
    });

    test('buildName formats buildNumber as 1.2.3', () {
      final context = PipelineContext(
        config: const CIToolsConfig(appName: 'A', seedBuildNumber: 10000),
        platforms: {},
      )..buildNumber = 12001;
      expect(context.buildName, '1.2.0');
    });
  });
}
```

- [ ] **Step 4: Update every existing-action test to supply `platforms` and not call removed APIs**

The four upload/notify action tests and `pipeline_action_test.dart` test the *old* shape of those actions (string-keyed `context.set`/`get`). They will be fully rewritten in Task 14. For this task: add a file-level `@Skip` annotation so they don't run, and delete any `context.set/get/tryGet/has/remove` lines so the file still parses cleanly.

For each of `test/actions/pgyer_upload_action_test.dart`, `test/actions/google_play_action_test.dart`, `test/actions/app_store_action_test.dart`, `test/actions/feishu_notify_action_test.dart`, `test/actions/pipeline_action_test.dart`:

1. Add the skip annotation at the top of the file (see below).
2. Delete every `context.set / get / tryGet / has / remove` call from the test bodies — the surrounding test still parses but is skipped anyway.

The skip annotation:

```dart
@Skip('Reshape in task 14: typed Action constructor params')
library;
```

(`library;` is required for file-level annotations in Dart 3.)

Also: the existing `test/pipeline_test.dart` exercises the old `BuildPipeline` shape (`runAndroidOnly`, `_TestPipeline` with `envName`/`deployAndroid`/etc.). It is rewritten from scratch in Task 13. For this task, delete the file entirely — Task 13 will create the new one.

```bash
rm test/pipeline_test.dart
```

- [ ] **Step 5: Run the test suite**

Run: `dart test`
Expected: PASS — new Action tests (Phases 1-3) green; reshaped tests above skipped; old broken tests no longer run.

- [ ] **Step 6: Commit**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart test/actions test/pipeline_test.dart
git commit -m "refactor: reshape PipelineContext (add platforms, remove string store)"
```

---

### Task 13: Reshape `BuildPipeline` + `PipelineRegistry`

Slim the base class to lifecycle hooks; have the registry call `run(Set<AppPlatform>)`.

**Files:**
- Modify: `lib/src/pipeline.dart`
- Modify: `lib/src/pipeline_registry.dart`
- Modify: `test/pipeline_test.dart`
- Modify: `test/pipeline_registry_test.dart` (only if it constructs pipelines or asserts on per-platform methods)

- [ ] **Step 1: Write the new `BuildPipeline` test**

Replace `test/pipeline_test.dart` with:

```dart
import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _RecordingAction extends PipelineAction<void> {
  _RecordingAction(this.label, this.log, {this.willThrow = false});
  final String label;
  final List<String> log;
  final bool willThrow;
  @override String get name => label;
  @override
  Future<void> run(PipelineContext context) async {
    log.add(label);
    if (willThrow) throw StateError('boom from $label');
  }
}

class _TestPipeline extends BuildPipeline {
  _TestPipeline(super.config, {required this.log, this.bodyThrows = false, this.afterThrows = false});

  final List<String> log;
  final bool bodyThrows;
  final bool afterThrows;

  @override String get name => 'test';
  @override String get description => 'test pipeline';
  @override String get help => 'help';

  @override
  Future<void> beforeBuild() async => log.add('before');

  @override
  Future<void> body() async {
    log.add('body-start');
    if (bodyThrows) throw StateError('body-failed');
    await runAction(_RecordingAction('action-a', log));
  }

  @override
  Future<void> afterBuild() => runAction(
    _RecordingAction('after', log, willThrow: afterThrows),
  );
}

void main() {
  group('BuildPipeline lifecycle', () {
    test('runs beforeBuild → body → afterBuild in order', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(
        const CIToolsConfig(appName: 'A', seedBuildNumber: 10000),
        log: log,
      );
      await pipeline.run({AppPlatform.android});
      expect(log, ['before', 'body-start', 'action-a', 'after']);
      expect(pipeline.context.platforms, {AppPlatform.android});
    });

    test('runs afterBuild even when body throws, and rethrows the body error', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(
        const CIToolsConfig(appName: 'A', seedBuildNumber: 10000),
        log: log,
        bodyThrows: true,
      );
      await expectLater(
        pipeline.run({AppPlatform.android, AppPlatform.ios}),
        throwsA(isA<StateError>()),
      );
      expect(log, ['before', 'body-start', 'after']);
    });

    test('afterBuild errors are swallowed (logged) so they do not mask body errors', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(
        const CIToolsConfig(appName: 'A', seedBuildNumber: 10000),
        log: log,
        afterThrows: true,
      );
      await pipeline.run({AppPlatform.android}); // should NOT throw
      expect(log, containsAll(['before', 'body-start', 'action-a', 'after']));
    });
  });
}
```

- [ ] **Step 2: Run new test to verify it fails**

Run: `dart test test/pipeline_test.dart`
Expected: FAIL — new `BuildPipeline` shape not implemented yet.

- [ ] **Step 3: Reshape `lib/src/pipeline.dart`**

Replace the file with:

```dart
import 'config.dart';
import 'logger.dart';
import 'pipeline_context.dart';
import 'actions/pipeline_action.dart';

/// Target platform for a build run.
enum AppPlatform {
  android('Android'),
  ios('iOS');

  final String label;
  const AppPlatform(this.label);
}

/// Executes [action] with standardized section logging and error handling.
Future<T> runStep<T>(String name, Future<T> Function() action) async {
  final startTime = DateTime.now();
  Logger.section(name);
  try {
    final result = await action();
    final duration = DateTime.now().difference(startTime);
    Logger.success('Finished: $name (${duration.inSeconds}s)');
    return result;
  } catch (e) {
    Logger.error('Failed: $name', e);
    rethrow;
  }
}

/// Base class for CI build pipelines.
///
/// Subclasses implement [body] to compose [PipelineAction]s; the base class
/// provides only the execution shell ([beforeBuild] → [body] → [afterBuild])
/// with try/finally semantics guaranteeing [afterBuild] runs even on failure.
abstract class BuildPipeline {
  BuildPipeline(this._config);

  final CIToolsConfig _config;

  /// Populated by [run]; do not access before then.
  late final PipelineContext context;

  /// Unique identifier (e.g. `"prod"`).
  String get name;

  /// Short description shown in the interactive selector.
  String get description;

  /// Extended help text printed when the user passes `--help`.
  String get help;

  /// Optional preparation hook. Default no-op.
  Future<void> beforeBuild() async {}

  /// Main pipeline body. Subclasses compose actions here via [runAction].
  Future<void> body();

  /// Optional cleanup hook; always runs even if [body] throws.
  ///
  /// Errors from this hook are logged but not rethrown, so they cannot
  /// mask the original [body] failure.
  Future<void> afterBuild() async {}

  /// Entry point. Constructs the [PipelineContext] with the given [platforms],
  /// then runs `beforeBuild → body → afterBuild`.
  Future<void> run(Set<AppPlatform> platforms) async {
    context = PipelineContext(config: _config, platforms: platforms);
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e, st) {
        Logger.error('afterBuild failed', e, st);
      }
    }
  }

  /// Runs [action] wrapped in [runStep] using [PipelineAction.name] as the
  /// log section header. Returns the action's typed result.
  Future<R> runAction<R>(PipelineAction<R> action) =>
      runStep(action.name, () => action.run(context));
}
```

- [ ] **Step 4: Update `lib/src/pipeline_registry.dart`**

Locate the per-platform dispatch (currently around lines 62-78 calling `runAndroidOnly() / runIOSOnly() / run()`) and replace it with:

```dart
import 'pipeline.dart';
// ... (other imports unchanged)

// ... inside `run(args, ...)`:
    final platforms = _parsePlatforms(args);
    if (platforms == null) {
      stderr.writeln('Unknown platform: ${args[1]}');
      exitFn(64);
      return;
    }
    await pipeline.run(platforms);
```

And add a helper method to the class:

```dart
  /// Parses the optional second CLI argument into a platform set.
  /// Returns `null` if the second arg is present but unrecognized.
  Set<AppPlatform>? _parsePlatforms(List<String> args) {
    if (args.length <= 1) return AppPlatform.values.toSet();
    switch (args[1]) {
      case 'android':
        return {AppPlatform.android};
      case 'ios':
        return {AppPlatform.ios};
      default:
        return null;
    }
  }
```

Also update the interactive selector branch (currently `await list[choice - 1].run();`) to `await list[choice - 1].run(AppPlatform.values.toSet());`.

- [ ] **Step 5: Run new `BuildPipeline` test to verify it passes**

Run: `dart test test/pipeline_test.dart`
Expected: PASS.

- [ ] **Step 6: Update `test/pipeline_registry_test.dart` for the new dispatch**

Read the file, then for any test that expected `runAndroidOnly` / `runIOSOnly` calls, change the expectation to `run({android})` / `run({ios})`. Constructor calls for fake pipelines may need to override `body()` instead of the old getters. Use the `_RecordingAction` / `_TestPipeline` shape from Step 1 as a template.

- [ ] **Step 7: Run the full test suite**

Run: `dart test`
Expected: PASS — `BuildPipeline`, `PipelineRegistry`, and `PipelineContext` tests all green; existing-action tests still skipped from Task 12.

- [ ] **Step 8: Commit**

```bash
git add lib/src/pipeline.dart lib/src/pipeline_registry.dart \
        test/pipeline_test.dart test/pipeline_registry_test.dart
git commit -m "refactor: slim BuildPipeline to lifecycle container; registry dispatches via Set<AppPlatform>"
```

---

### Task 14: Reshape existing upload + notify Actions to typed params + return values

Drop string-key context coupling from `PgyerUploadAction`, `GooglePlayUploadAction`, `AppStoreUploadAction`, `FeishuNotifyAction`. Un-skip and rewrite their tests.

**Files:**
- Modify: `lib/src/actions/pgyer_upload_action.dart`
- Modify: `lib/src/actions/google_play_action.dart`
- Modify: `lib/src/actions/app_store_action.dart`
- Modify: `lib/src/actions/feishu_notify_action.dart`
- Modify: `test/actions/pgyer_upload_action_test.dart` (un-skip + rewrite)
- Modify: `test/actions/google_play_action_test.dart` (un-skip + rewrite)
- Modify: `test/actions/app_store_action_test.dart` (un-skip + rewrite)
- Modify: `test/actions/feishu_notify_action_test.dart` (un-skip + rewrite)

- [ ] **Step 1: Rewrite `PgyerUploadAction`**

Replace `lib/src/actions/pgyer_upload_action.dart` with (only the bits that change shown — keep curl logic and retry intact):

```dart
import 'dart:convert';
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads a build artifact to Pgyer and returns the download URL.
class PgyerUploadAction extends PipelineAction<String> {
  PgyerUploadAction({
    required this.artifact,
    required this.apiKey,
    this.description,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final File artifact;
  final String apiKey;
  final String? description;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<String> run(PipelineContext context) async {
    final filePath = artifact.path;
    Logger.info('Uploading $filePath ...');
    const maxAttempts = 3;
    ShellResult? result;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        Logger.info('Retrying upload (attempt $attempt/$maxAttempts)...');
        await Future.delayed(const Duration(seconds: 5));
      }
      result = await _shellRunner.runAndCapture('curl', [
        '--http1.1',
        '-F', 'file=@$filePath',
        '-F', '_api_key=$apiKey',
        if (description != null) ...[
          '-F', 'buildUpdateDescription=$description',
        ],
        'https://www.pgyer.com/apiv2/app/upload',
      ]);
      if (result.exitCode == 0) break;
      Logger.error('Upload attempt $attempt failed: ${result.stderr}');
    }
    if (result!.exitCode != 0) {
      throw DeployException('Upload failed after $maxAttempts attempts');
    }
    try {
      final response = jsonDecode(result.stdout);
      if (response['code'] == 0) {
        final url = 'https://www.pgyer.com/${response['data']['buildKey']}';
        Logger.success('Upload successful! Download URL: $url');
        return url;
      }
      throw DeployException(
        'Upload failed with API error: ${response['message']}',
      );
    } catch (e) {
      if (e is DeployException) rethrow;
      throw DeployException('Failed to parse upload response: $e');
    }
  }
}
```

- [ ] **Step 2: Rewrite `GooglePlayUploadAction`**

Replace `lib/src/actions/google_play_action.dart` with:

```dart
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an AAB file to Google Play via Fastlane Supply.
class GooglePlayUploadAction extends PipelineAction<void> {
  GooglePlayUploadAction({
    required this.artifact,
    required this.packageName,
    required this.jsonKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final File artifact;
  final String packageName;
  final String jsonKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Google Play';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('AAB: ${artifact.path}');
    Logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw DeployException(
        'Google Play Service Account JSON not found at $jsonKeyPath',
      );
    }
    await _shellRunner.run('fastlane', [
      'supply',
      '--aab', artifact.path,
      '--package_name', packageName,
      '--json_key', jsonKeyPath,
      '--track', 'internal',
      '--skip_upload_metadata',
      '--skip_upload_images',
      '--skip_upload_screenshots',
    ]);
    Logger.success('Google Play upload successful!');
  }
}
```

- [ ] **Step 3: Rewrite `AppStoreUploadAction`**

Replace `lib/src/actions/app_store_action.dart` with:

```dart
import 'dart:convert';
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
class AppStoreUploadAction extends PipelineAction<void> {
  AppStoreUploadAction({
    required this.artifact,
    required this.issuerId,
    required this.apiKeyId,
    required this.apiKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final File artifact;
  final String issuerId;
  final String apiKeyId;
  final String apiKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('IPA: ${artifact.path}');
    Logger.info('API Key: $apiKeyId');
    if (!File(apiKeyPath).existsSync()) {
      throw DeployException(
        'App Store API Key (.p8) not found at $apiKeyPath',
      );
    }
    final p8Content = File(apiKeyPath).readAsStringSync().trim();
    final apiKeyJson = jsonEncode({
      'key_id': apiKeyId,
      'issuer_id': issuerId,
      'key': p8Content,
      'in_house': false,
    });
    final apiKeyJsonFile = File('ci/api_key_tmp.json');
    apiKeyJsonFile.writeAsStringSync(apiKeyJson);
    try {
      await _shellRunner.run('fastlane', [
        'pilot', 'upload',
        '--ipa', artifact.path,
        '--api_key_path', apiKeyJsonFile.path,
        '--skip_waiting_for_build_processing',
      ]);
    } finally {
      apiKeyJsonFile.deleteSync();
    }
    Logger.success('App Store upload successful!');
  }
}
```

- [ ] **Step 4: Rewrite `FeishuNotifyAction`**

Replace `lib/src/actions/feishu_notify_action.dart` with:

```dart
import 'dart:convert';

import '../default_shell_runner.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Sends an arbitrary text message to a Feishu (Lark) webhook.
///
/// For standard build notifications prefer [FeishuBuildNotifyAction].
class FeishuNotifyAction extends PipelineAction<void> {
  FeishuNotifyAction({
    required this.message,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String message;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final webhookUrl = context.config.feishuWebhookUrl!;
    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });
    final result = await _shellRunner.runAndCapture('curl', [
      '-X', 'POST',
      '-H', 'Content-Type: application/json',
      '-d', jsonMessage,
      webhookUrl,
    ]);
    if (result.exitCode == 0) {
      Logger.success('Feishu notification sent.');
    } else {
      Logger.error('Failed to send Feishu notification: ${result.stderr}');
    }
  }
}
```

- [ ] **Step 5: Update `FeishuBuildNotifyAction` to call the new typed `FeishuNotifyAction`**

In `lib/src/actions/feishu_build_notify_action.dart`, replace the body of `run(...)` so that the curl call goes through `FeishuNotifyAction` instead of being inlined:

```dart
  @override
  Future<void> run(PipelineContext context) async {
    final message = _formatMessage(context);
    await FeishuNotifyAction(message: message, shellRunner: _shellRunner)
        .run(context);
  }
```

Drop the inline `jsonEncode` / `_shellRunner.runAndCapture('curl', ...)` block from this file (it now lives only in `FeishuNotifyAction`). Keep `_formatMessage` and the `_shellRunner` field (passed through to the inner action).

Remove the unused `import 'dart:convert';` if Dart analyzer flags it.

- [ ] **Step 6: Un-skip and rewrite the four existing-action tests**

For each test file, remove the `@Skip(...)` annotation added in Task 12 and rewrite the test body to use the new typed constructors. Sample for `test/actions/pgyer_upload_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/pgyer_upload_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final Map<String, ShellResult> _responses = {};
  ShellResult? _fallback;
  final List<String> runCalls = [];

  void stub(String exe, List<String> args, ShellResult r) =>
      _responses['$exe ${args.join(' ')}'] = r;
  void stubAny(ShellResult r) => _fallback = r;

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final key = '$exe ${args.join(' ')}';
    runCalls.add(key);
    return _responses[key] ?? _fallback ??
        ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  PipelineContext ctx() => PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          pgyerApiKey: 'unused',
        ),
        platforms: {AppPlatform.android},
      );

  test('returns download URL on success', () async {
    final shell = _FakeShellRunner()
      ..stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":0,"data":{"buildKey":"abc123"}}',
        stderr: '',
      ));
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'test_api_key',
      shellRunner: shell,
    );

    final url = await action.run(ctx());
    expect(url, 'https://www.pgyer.com/abc123');
  });

  test('includes description when provided', () async {
    final shell = _FakeShellRunner()
      ..stub(
        'curl',
        [
          '--http1.1',
          '-F', 'file=@test.apk',
          '-F', '_api_key=k',
          '-F', 'buildUpdateDescription=notes',
          'https://www.pgyer.com/apiv2/app/upload',
        ],
        ShellResult(
          exitCode: 0,
          stdout: '{"code":0,"data":{"buildKey":"xyz"}}',
          stderr: '',
        ),
      );
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'k',
      description: 'notes',
      shellRunner: shell,
    );
    final url = await action.run(ctx());
    expect(url, 'https://www.pgyer.com/xyz');
  });

  test('throws DeployException on API error', () async {
    final shell = _FakeShellRunner()
      ..stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":1,"message":"bad key"}',
        stderr: '',
      ));
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'k',
      shellRunner: shell,
    );
    expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
  });
}
```

Apply the analogous reshape to the other three test files: drop `@Skip(...)`, drop `context.set(...)` calls, construct the Action via typed params, and read the return value (for `PgyerUploadAction`) or rely on `_FakeShellRunner.runCalls` for side-effect checks.

- [ ] **Step 7: Run the full test suite**

Run: `dart test`
Expected: PASS — all action tests reshape-and-green; library + pipeline + registry + context tests still green.

- [ ] **Step 8: Commit**

```bash
git add lib/src/actions test/actions
git commit -m "refactor: existing upload/notify actions take typed params; PgyerUploadAction returns URL"
```

---

### Task 15: Migrate the three example pipelines

Rewrite `TestPipeline`, `ProdPipeline`, `AndroidTestPipeline` to the new shape.

**Files:**
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`
- Modify: `example/ci/pipelines/android_test_pipeline.dart`

- [ ] **Step 1: Rewrite `ProdPipeline`**

Replace `example/ci/pipelines/prod_pipeline.dart` with:

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class ProdPipeline extends BuildPipeline {
  ProdPipeline() : super(exampleConfig);

  @override
  String get name => 'prod';
  @override
  String get description => '构建并部署到生产环境 (Google Play / App Store)';
  @override
  String get help => '''
Prod Pipeline
构建生产版本并上传到 Google Play 和 App Store。

Usage: dart run ci/build.dart prod [android|ios]
  android    仅构建 Android
  ios        仅构建 iOS
不指定平台时同时构建两个平台。''';

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: 'prod',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());
    await runAction(CleanProjectAction());

    if (context.platforms.contains(AppPlatform.android)) {
      final aab = await runAction(BuildAndroidAction(
        envName: 'prod',
        buildType: AndroidBuildType.appbundle,
      ));
      await runAction(GooglePlayUploadAction(
        artifact: aab,
        packageName: ProdCredentials.googlePlayPackageName,
        jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
      ));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ));
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      final ipa = await runAction(BuildIOSAction(
        envName: 'prod',
        exportMethod: 'app-store',
      ));
      await runAction(AppStoreUploadAction(
        artifact: ipa,
        issuerId: ProdCredentials.appStoreIssuerId,
        apiKeyId: ProdCredentials.appStoreApiKeyId,
        apiKeyPath: ProdCredentials.appStoreApiKeyPath,
      ));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ));
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

- [ ] **Step 2: Rewrite `TestPipeline`**

Replace `example/ci/pipelines/test_pipeline.dart` with:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class TestPipeline extends BuildPipeline {
  TestPipeline() : super(exampleConfig);

  @override String get name => 'test';
  @override String get description => '构建并部署到测试环境 (Pgyer)';
  @override String get help => '''
Test Pipeline
构建测试版本并上传到蒲公英。

Usage: dart run ci/build.dart test [android|ios]
  android    仅构建 Android
  ios        仅构建 iOS
不指定平台时同时构建两个平台。''';

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: 'test',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

    if (context.platforms.contains(AppPlatform.android)) {
      final apk = await runAction(BuildAndroidAction(
        envName: 'test',
        buildType: AndroidBuildType.apk,
      ));
      await _deployToPgyer(AppPlatform.android, apk);
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      final ipa = await runAction(BuildIOSAction(
        envName: 'test',
        exportMethod: 'development',
      ));
      await _deployToPgyer(AppPlatform.ios, ipa);
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());

  Future<void> _deployToPgyer(AppPlatform platform, File artifact) async {
    final pgyerUrl = await runAction(PgyerUploadAction(
      artifact: artifact,
      apiKey: context.config.pgyerApiKey!,
      description: _pgyerDescription(),
    ));
    await runAction(FeishuBuildNotifyAction(
      platform: platform,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }

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
}
```

- [ ] **Step 3: Rewrite `AndroidTestPipeline`**

Replace `example/ci/pipelines/android_test_pipeline.dart` with a near-clone of `TestPipeline` minus the iOS branch — kept as a separate pipeline because it's intentionally android-only for fast iteration:

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class AndroidTestPipeline extends BuildPipeline {
  AndroidTestPipeline() : super(exampleConfig);

  @override String get name => 'android_test';
  @override String get description => 'android 测试环境版本构建，用于开发期间调试脚本的功能';
  @override String get help => 'android-only test pipeline';

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: 'test',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

    final apk = await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    final pgyerUrl = await runAction(PgyerUploadAction(
      artifact: apk,
      apiKey: context.config.pgyerApiKey!,
    ));
    await runAction(FeishuBuildNotifyAction(
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

- [ ] **Step 4: Smoke-compile the example app**

Run: `cd example && dart pub get && dart analyze ci/`
Expected: 0 errors, 0 warnings (info-level lints unrelated to this change are acceptable).

`cd` back: `cd ..`

- [ ] **Step 5: Commit**

```bash
git add example/ci/pipelines/
git commit -m "refactor(example): migrate Test/Prod/AndroidTest pipelines to body() shape"
```

---

### Task 16: Update library exports + remove obsolete enums from `pipeline.dart`

`AndroidBuildType` and `DeployTarget` now live in their consumer Action files. Remove the duplicates in `pipeline.dart` and add the new files to the library exports.

**Files:**
- Modify: `lib/src/pipeline.dart`
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Strip duplicate enums from `lib/src/pipeline.dart`**

Open the file and delete the `enum AndroidBuildType { ... }` and `enum DeployTarget { ... }` blocks. After this step `pipeline.dart` contains only:
- top-level `runStep<T>` function
- `enum AppPlatform { android, ios }`
- `abstract class BuildPipeline { ... }`

Run: `grep -n 'AndroidBuildType\|DeployTarget' lib/src/pipeline.dart`
Expected: no matches.

- [ ] **Step 2: Update `lib/flutter_ci_tools.dart` exports**

Replace the file with:

```dart
export 'src/actions/app_store_action.dart';
export 'src/actions/build_android_action.dart';
export 'src/actions/build_ios_action.dart';
export 'src/actions/check_git_status_action.dart';
export 'src/actions/clean_project_action.dart';
export 'src/actions/collect_metadata_action.dart';
export 'src/actions/feishu_build_notify_action.dart';
export 'src/actions/feishu_notify_action.dart';
export 'src/actions/google_play_action.dart';
export 'src/actions/pgyer_upload_action.dart';
export 'src/actions/pipeline_action.dart';
export 'src/actions/push_build_tag_action.dart';
export 'src/actions/resolve_build_version_action.dart';
export 'src/actions/restore_workspace_action.dart';
export 'src/actions/swap_info_plist_action.dart';
export 'src/build_metadata.dart';
export 'src/builders/android_builder.dart';
export 'src/builders/ios_builder.dart';
export 'src/config.dart';
export 'src/default_shell_runner.dart';
export 'src/exceptions.dart';
export 'src/git_manager.dart';
export 'src/logger.dart';
export 'src/pipeline.dart';
export 'src/pipeline_context.dart';
export 'src/pipeline_registry.dart';
export 'src/shell_runner.dart';
export 'src/version_manager.dart';
```

- [ ] **Step 3: Run the full test suite**

Run: `dart test`
Expected: PASS — all tests green.

- [ ] **Step 4: Run static analysis**

Run: `dart analyze`
Expected: 0 issues.

If `dart analyze` complains about `AndroidBuildType` or `DeployTarget` being imported from `pipeline.dart` somewhere (e.g. inside `feishu_build_notify_action.dart` for `AppPlatform`), confirm the imports point to the new files for the enums and to `pipeline.dart` only for `AppPlatform`.

- [ ] **Step 5: Re-analyze the example app**

Run: `cd example && dart analyze ci/ && cd ..`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/src/pipeline.dart lib/flutter_ci_tools.dart
git commit -m "refactor: remove obsolete enums from pipeline.dart; export new actions"
```

---

## Phase 5: Verification

### Task 17: End-to-end sanity check + dead-code sweep

- [ ] **Step 1: Re-confirm no dangling references to removed APIs**

Run: `grep -rn 'runAndroidOnly\|runIOSOnly\|buildFeishuMessage\|shouldSwapInfoPlist\|deployAndroid\|deployIOS\|context\.\(set\|get\|tryGet\|has\|remove\)' lib test example`
Expected: no matches.

- [ ] **Step 2: Re-confirm old base-class fields are gone**

Run: `grep -n '_versionManager\|_gitManager\|_shellRunner\|_androidBuilder\|_iosBuilder\|_buildAndroid\|_buildIOS\|cleanProject\|buildPrepare\|envName\|apiHost\|iosExportMethod\|androidBuildType' lib/src/pipeline.dart`
Expected: no matches.

- [ ] **Step 3: Full test + analyze**

Run: `dart test && dart analyze && cd example && dart analyze ci/ && cd ..`
Expected: tests pass, both analyzes return 0 issues.

- [ ] **Step 4: Manual scan of `lib/src/pipeline.dart` for size**

Run: `wc -l lib/src/pipeline.dart`
Expected: roughly 60-80 lines (down from 318).

- [ ] **Step 5: Commit only if any sweep produced changes**

If steps 1-2 surfaced dead code and you removed it:

```bash
git add -p
git commit -m "chore: final cleanup of obsolete BuildPipeline surface"
```

If nothing changed, skip this commit.

---

## Done

After Task 17, the refactor is complete:

- `BuildPipeline` is a lifecycle container (~70 lines).
- 14 `PipelineAction<R>` subclasses cover every build / deploy / notify step.
- The three example pipelines override `body()` only; CLI behaviour unchanged.
- Every commit can be reverted independently.
