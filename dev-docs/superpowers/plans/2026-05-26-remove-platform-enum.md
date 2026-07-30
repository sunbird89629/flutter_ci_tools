# Remove AppPlatform Enum & writeBuildInfo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `AppPlatform` enum, `PipelineContext.platforms`, `writeBuildInfo`, and `FeishuBuildNotifyAction.platform` to simplify the framework and improve extensibility.

**Architecture:** Pure refactoring — delete enum, change signatures from `Set<AppPlatform>` to no-arg, remove unused code. Each pipeline becomes responsible for its own platform logic.

**Tech Stack:** Dart, package:test

**Spec:** `docs/superpowers/specs/2026-05-26-remove-platform-enum-design.md`

---

### Task 1: Delete writeBuildInfo

**Files:**
- Delete: `example/ci/build_info_writer.dart`

- [ ] **Step 1: Delete the file**

```bash
rm example/ci/build_info_writer.dart
```

- [ ] **Step 2: Verify no remaining references**

```bash
grep -r "writeBuildInfo\|build_info_writer" --include="*.dart"
```

Expected: No output (references will be removed in Task 5 when we update pipelines).

- [ ] **Step 3: Commit**

```bash
git add -A example/ci/build_info_writer.dart
git commit -m "refactor: delete build_info_writer.dart"
```

---

### Task 2: Remove AppPlatform enum from pipeline.dart

**Files:**
- Modify: `lib/src/pipeline.dart:6-13` — delete `AppPlatform` enum
- Modify: `lib/src/pipeline.dart:36` — `createContext` signature
- Modify: `lib/src/pipeline.dart:51` — `run` signature

- [ ] **Step 1: Remove AppPlatform enum**

Delete lines 6-13 from `lib/src/pipeline.dart`:

```dart
// DELETE this entire block:
enum AppPlatform {
  android('Android'),
  ios('iOS');

  final String label;
  const AppPlatform(this.label);
}
```

- [ ] **Step 2: Change createContext signature**

In `lib/src/pipeline.dart`, change:

```dart
// Before
PipelineContext createContext(Set<AppPlatform> platforms);

// After
PipelineContext createContext();
```

- [ ] **Step 3: Change run signature**

In `lib/src/pipeline.dart`, change:

```dart
// Before
Future<void> run(Set<AppPlatform> platforms) async {
  context = createContext(platforms);

// After
Future<void> run() async {
  context = createContext();
```

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline.dart
git commit -m "refactor: remove AppPlatform enum, change BuildPipeline signatures"
```

---

### Task 3: Remove platforms from PipelineContext

**Files:**
- Modify: `lib/src/pipeline_context.dart:4` — remove import
- Modify: `lib/src/pipeline_context.dart:26-39` — remove platforms field

- [ ] **Step 1: Remove import**

In `lib/src/pipeline_context.dart`, delete:

```dart
import 'pipeline.dart' show AppPlatform;
```

- [ ] **Step 2: Remove platforms field and constructor parameter**

In `lib/src/pipeline_context.dart`, change:

```dart
// Before
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
  });

  final String appName;
  final int seedBuildNumber;
  final Set<AppPlatform> platforms;

// After
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
  });

  final String appName;
  final int seedBuildNumber;
```

- [ ] **Step 3: Commit**

```bash
git add lib/src/pipeline_context.dart
git commit -m "refactor: remove platforms from PipelineContext"
```

---

### Task 4: Remove platform from FeishuBuildNotifyAction

**Files:**
- Modify: `lib/src/actions/feishu_build_notify_action.dart:2` — remove import
- Modify: `lib/src/actions/feishu_build_notify_action.dart:40-52` — remove platform param
- Modify: `lib/src/actions/feishu_build_notify_action.dart:78` — update message format

- [ ] **Step 1: Remove import**

In `lib/src/actions/feishu_build_notify_action.dart`, delete:

```dart
import '../pipeline.dart' show AppPlatform;
```

- [ ] **Step 2: Remove platform from constructor and fields**

In `lib/src/actions/feishu_build_notify_action.dart`, change:

```dart
// Before
FeishuBuildNotifyAction({
  required this.webhookUrl,
  required this.platform,
  required this.target,
  this.downloadUrl,
  ShellRunner? shellRunner,
}) : _shellRunner = shellRunner ?? ShellRunnerImpl();

final String webhookUrl;
final AppPlatform platform;
final DeployTarget target;

// After
FeishuBuildNotifyAction({
  required this.webhookUrl,
  required this.target,
  this.downloadUrl,
  ShellRunner? shellRunner,
}) : _shellRunner = shellRunner ?? ShellRunnerImpl();

final String webhookUrl;
final DeployTarget target;
```

Also update the dartdoc constructor comment — remove the `[platform]` line.

- [ ] **Step 3: Update message format**

In `_formatMessage`, change:

```dart
// Before
'🚀 ${context.appName} 新版本 ${context.buildNumber} (${platform.label} · ${target.label})',

// After
'🚀 ${context.appName} 新版本 ${context.buildNumber} (${target.label})',
```

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/feishu_build_notify_action.dart
git commit -m "refactor: remove platform param from FeishuBuildNotifyAction"
```

---

### Task 5: Simplify PipelineRegistry

**Files:**
- Modify: `lib/src/pipeline_registry.dart:62-81` — remove _parsePlatforms, simplify run
- Modify: `lib/src/pipeline_registry.dart:112` — interactive selection

- [ ] **Step 1: Remove _parsePlatforms and platform dispatch logic**

In `lib/src/pipeline_registry.dart`, delete the `_parsePlatforms` method entirely (lines 71-81):

```dart
// DELETE:
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

- [ ] **Step 2: Simplify run() method**

Replace the platform parsing block (lines 62-68):

```dart
// Before
final platforms = _parsePlatforms(args);
if (platforms == null) {
  stderr.writeln('Unknown platform: ${args[1]}');
  exitFn(64);
  return;
}
await pipeline.run(platforms);

// After
await pipeline.run();
```

- [ ] **Step 3: Update interactive selection**

Change line 112:

```dart
// Before
await list[choice - 1].run(AppPlatform.values.toSet());

// After
await list[choice - 1].run();
```

- [ ] **Step 4: Remove unused import**

The file imports `pipeline.dart` which no longer exports `AppPlatform`. Verify the import is still needed for `BuildPipeline`. If so, keep it. The `AppPlatform` reference is gone so no issue.

- [ ] **Step 5: Commit**

```bash
git add lib/src/pipeline_registry.dart
git commit -m "refactor: remove platform parsing from PipelineRegistry"
```

---

### Task 6: Update example pipelines

**Files:**
- Modify: `example/ci/app_config.dart:12` — remove platforms from ExampleAppContext
- Modify: `example/ci/pipelines/test_pipeline.dart` — remove writeBuildInfo, hardcode platforms
- Modify: `example/ci/pipelines/prod_pipeline.dart` — remove writeBuildInfo, hardcode platforms
- Modify: `example/ci/pipelines/android_test_pipeline.dart` — remove writeBuildInfo, update context

- [ ] **Step 1: Update ExampleAppContext**

In `example/ci/app_config.dart`:

```dart
// Before
class ExampleAppContext extends PipelineContext {
  ExampleAppContext({required super.platforms})
      : super(
          appName: 'FlutterCIToolsExample',
          seedBuildNumber: 10000,
        );

// After
class ExampleAppContext extends PipelineContext {
  ExampleAppContext()
      : super(
          appName: 'FlutterCIToolsExample',
          seedBuildNumber: 10000,
        );
```

- [ ] **Step 2: Update TestPipeline**

In `example/ci/pipelines/test_pipeline.dart`:

```dart
// Before
import '../build_info_writer.dart';

class TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      ExampleAppContext(platforms: platforms);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());
    await writeBuildInfo(
      env: 'test',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );

    if (context.platforms.contains(AppPlatform.android)) {
      await runAction(BuildAndroidAction(
        envName: 'test',
        buildType: AndroidBuildType.apk,
      ));
      await _deployToPgyer(AppPlatform.android);
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      await runAction(BuildIOSAction(
        envName: 'test',
        exportMethod: 'development',
      ));
      await _deployToPgyer(AppPlatform.ios);
    }

    await runAction(PushBuildTagAction());
  }

  Future<void> _deployToPgyer(AppPlatform platform) async {
    final pgyerUrl = await runAction(PgyerUploadAction(
      apiKey: (context as ExampleAppContext).pgyerApiKey,
      description: _pgyerDescription(),
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      platform: platform,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }

// After
class TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext() => ExampleAppContext();

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

    await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    await _deployToPgyer();

    await runAction(BuildIOSAction(
      envName: 'test',
      exportMethod: 'development',
    ));
    await _deployToPgyer();

    await runAction(PushBuildTagAction());
  }

  Future<void> _deployToPgyer() async {
    final pgyerUrl = await runAction(PgyerUploadAction(
      apiKey: (context as ExampleAppContext).pgyerApiKey,
      description: _pgyerDescription(),
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }
```

Also remove the `import '../build_info_writer.dart';` line.

- [ ] **Step 3: Update ProdPipeline**

In `example/ci/pipelines/prod_pipeline.dart`:

```dart
// Before
import '../build_info_writer.dart';

class ProdPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      ExampleAppContext(platforms: platforms);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());
    await runAction(CleanProjectAction());
    await writeBuildInfo(
      env: 'prod',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );

    if (context.platforms.contains(AppPlatform.android)) {
      // ... android build + deploy
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      // ... ios build + deploy
    }

    await runAction(PushBuildTagAction());
  }

// After
class ProdPipeline extends BuildPipeline {
  @override
  PipelineContext createContext() => ExampleAppContext();

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());
    await runAction(CleanProjectAction());

    // Android
    await runAction(BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.appbundle,
    ));
    await runAction(GooglePlayUploadAction(
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: DeployTarget.googlePlay,
    ));

    // iOS
    await runAction(BuildIOSAction(
      envName: 'prod',
      exportMethod: 'app-store',
    ));
    await runAction(AppStoreUploadAction(
      issuerId: ProdCredentials.appStoreIssuerId,
      apiKeyId: ProdCredentials.appStoreApiKeyId,
      apiKeyPath: ProdCredentials.appStoreApiKeyPath,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: DeployTarget.appStore,
    ));

    await runAction(PushBuildTagAction());
  }
```

Remove the `import '../build_info_writer.dart';` line.

- [ ] **Step 4: Update AndroidTestPipeline**

In `example/ci/pipelines/android_test_pipeline.dart`:

```dart
// Before
class AndroidTestContext extends PipelineContext {
  AndroidTestContext({required super.platforms})
      : super(
          appName: 'testAppName',
          seedBuildNumber: 10000,
        );

class AndroidTestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      AndroidTestContext(platforms: platforms);

  @override
  Future<void> body() async {
    // ...
    await writeBuildInfo(
      env: 'test',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
    // ...
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: ctx.feishuWebhookUrl,
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }

// After
class AndroidTestContext extends PipelineContext {
  AndroidTestContext()
      : super(
          appName: 'testAppName',
          seedBuildNumber: 10000,
        );

class AndroidTestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext() => AndroidTestContext();

  @override
  Future<void> body() async {
    // ...
    // (writeBuildInfo removed)
    // ...
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: ctx.feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
  }
```

Remove the `import '../build_info_writer.dart';` line.

- [ ] **Step 5: Commit**

```bash
git add example/
git commit -m "refactor: update example pipelines — remove platforms, hardcode builds"
```

---

### Task 7: Update all tests

**Files:**
- Modify: `test/pipeline_test.dart` — remove AppPlatform usage
- Modify: `test/pipeline_registry_test.dart` — remove platform dispatch tests
- Modify: `test/pipeline_context_test.dart` — remove platforms from context construction
- Modify: `test/actions/feishu_build_notify_action_test.dart` — remove platform param
- Modify: `test/actions/feishu_notify_action_test.dart` — remove platforms from context
- Modify: `test/actions/pgyer_upload_action_test.dart` — remove platforms from context
- Modify: `test/actions/pgyer_upload_v2_action_test.dart` — remove platforms from context
- Modify: `test/actions/build_android_action_test.dart` — remove platforms from context
- Modify: `test/actions/build_ios_action_test.dart` — remove platforms from context
- Modify: `test/actions/resolve_build_version_action_test.dart` — remove platforms from context
- Modify: `test/actions/clean_project_action_test.dart` — remove platforms from context
- Modify: `test/actions/collect_metadata_action_test.dart` — remove platforms from context
- Modify: `test/actions/check_git_status_action_test.dart` — remove platforms from context
- Modify: `test/actions/restore_workspace_action_test.dart` — remove platforms from context
- Modify: `test/actions/push_build_tag_action_test.dart` — remove platforms from context
- Modify: `test/actions/google_play_action_test.dart` — remove platforms from context
- Modify: `test/actions/app_store_action_test.dart` — remove platforms from context
- Modify: `test/actions/pipeline_action_test.dart` — remove platforms from context
- Modify: `test/actions/swap_info_plist_action_test.dart` — remove platforms from context

- [ ] **Step 1: Update pipeline_test.dart**

```dart
// Before
import 'package:flutter_ci_tools/src/pipeline.dart';

class _TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
        platforms: platforms,
      );
  // ...
}

// In tests:
await pipeline.run({AppPlatform.android});
expect(pipeline.context.platforms, {AppPlatform.android});
await pipeline.run({AppPlatform.android, AppPlatform.ios});

// After
class _TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext() => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
      );
  // ...
}

// In tests:
await pipeline.run();
// Remove: expect(pipeline.context.platforms, ...);
await pipeline.run();
```

- [ ] **Step 2: Update pipeline_registry_test.dart**

Remove `receivedPlatforms` field and all platform-related assertions. The tests for "dispatches with android-only", "dispatches with ios-only", "exits 64 for invalid platform" should be deleted. Remaining tests just verify `run()` is called:

```dart
// Before
class _StubPipeline extends BuildPipeline {
  Set<AppPlatform>? receivedPlatforms;
  @override
  PipelineContext createContext(Set<AppPlatform> platforms) => PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 10000,
        platforms: platforms,
      );
  @override
  Future<void> body() async {
    receivedPlatforms = context.platforms;
  }
}

// After
class _StubPipeline extends BuildPipeline {
  bool wasRun = false;
  @override
  PipelineContext createContext() => PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 10000,
      );
  @override
  Future<void> body() async {
    wasRun = true;
  }
}
```

Update assertions: `expect(pipeline.receivedPlatforms, ...)` → `expect(pipeline.wasRun, isTrue)`

Delete these tests:
- 'run dispatches with all platforms when no platform arg'
- 'run dispatches with android-only set for "android" arg'
- 'run dispatches with ios-only set for "ios" arg'
- 'run exits 64 and prints "Unknown platform" for invalid platform arg'

Update 'run interactive selects pipeline by number with all platforms' → just verify `wasRun`.

- [ ] **Step 3: Update pipeline_context_test.dart**

Remove the `platforms` test and all `platforms:` constructor args:

```dart
// Before
ctx = PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 12000,
  platforms: <AppPlatform>{},
);

test('exposes platforms passed to constructor', () {
  final context = PipelineContext(
    appName: 'A',
    seedBuildNumber: 10000,
    platforms: {AppPlatform.android},
  );
  expect(context.platforms, {AppPlatform.android});
});

// After
ctx = PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 12000,
);

// Delete the 'exposes platforms' test entirely
```

- [ ] **Step 4: Update feishu_build_notify_action_test.dart**

```dart
// Before
final context = PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 12000,
  platforms: <AppPlatform>{},
);
final action = FeishuBuildNotifyAction(
  webhookUrl: 'https://open.feishu.cn/hook',
  platform: AppPlatform.android,
  target: DeployTarget.pgyer,
  downloadUrl: 'https://example.com/dl',
  shellRunner: shell,
);
expect(shell.lastJson, contains('Android'));

// After
final context = PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 12000,
);
final action = FeishuBuildNotifyAction(
  webhookUrl: 'https://open.feishu.cn/hook',
  target: DeployTarget.pgyer,
  downloadUrl: 'https://example.com/dl',
  shellRunner: shell,
);
// Remove: expect(shell.lastJson, contains('Android'));
```

Remove the `AppPlatform` import.

- [ ] **Step 5: Update all remaining test files**

For each of these files, remove `platforms: <AppPlatform>{}` (or `platforms: {AppPlatform.xxx}`) from `PipelineContext` constructor calls, and remove the `import '...pipeline.dart' show AppPlatform;` line:

- `test/actions/feishu_notify_action_test.dart`
- `test/actions/pgyer_upload_action_test.dart`
- `test/actions/pgyer_upload_v2_action_test.dart`
- `test/actions/build_android_action_test.dart`
- `test/actions/build_ios_action_test.dart`
- `test/actions/resolve_build_version_action_test.dart`
- `test/actions/clean_project_action_test.dart`
- `test/actions/collect_metadata_action_test.dart`
- `test/actions/check_git_status_action_test.dart`
- `test/actions/restore_workspace_action_test.dart`
- `test/actions/push_build_tag_action_test.dart`
- `test/actions/google_play_action_test.dart`
- `test/actions/app_store_action_test.dart`
- `test/actions/pipeline_action_test.dart`
- `test/actions/swap_info_plist_action_test.dart`

Pattern for each file:

```dart
// Before
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
// ...
final context = PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 12000,
  platforms: <AppPlatform>{},
);

// After
// (remove the import line)
// ...
final context = PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 12000,
);
```

- [ ] **Step 6: Run all tests**

```bash
dart test
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add test/
git commit -m "refactor: update tests — remove AppPlatform usage"
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run all tests**

```bash
dart test
```

Expected: All tests pass.

- [ ] **Step 2: Verify no remaining AppPlatform references**

```bash
grep -r "AppPlatform" --include="*.dart"
```

Expected: No output.

- [ ] **Step 3: Verify no remaining writeBuildInfo references**

```bash
grep -r "writeBuildInfo\|build_info_writer" --include="*.dart"
```

Expected: No output.

- [ ] **Step 4: Verify no remaining platforms: in PipelineContext constructors**

```bash
grep -r "platforms:" --include="*.dart" | grep -v "test/" | grep -v "docs/"
```

Expected: No output.

- [ ] **Step 5: Final commit if needed**

If any straggler changes were needed:

```bash
git add -A
git commit -m "refactor: cleanup remaining AppPlatform references"
```
