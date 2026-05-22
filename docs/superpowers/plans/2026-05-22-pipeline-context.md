# PipelineContext Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract scattered pipeline state (`config`, `buildNumber`, `metadata`) into a dedicated `PipelineContext` class with a generic key-value store for inter-step data passing.

**Architecture:** PipelineContext is a standalone class holding immutable config, mutable build state, and a `Map<String, dynamic>` store with typed get/set. BuildPipeline delegates state access to `context`. Subclasses and tests update references to use `context.` prefix.

**Tech Stack:** Dart 3.4+, `package:test`, zero external dependencies

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/src/pipeline_context.dart` | Create | PipelineContext class |
| `test/pipeline_context_test.dart` | Create | PipelineContext unit tests |
| `lib/src/pipeline.dart` | Modify | Remove 3 fields, add `context`, update all refs |
| `lib/flutter_ci_tools.dart` | Modify | Add `export 'src/pipeline_context.dart'` |
| `example/ci/pipelines/test_pipeline.dart` | Modify | `buildName`/`buildNumber`/`metadata`/`config` -> `context.` |
| `example/ci/pipelines/prod_pipeline.dart` | Modify | Same prefix changes |
| `example/ci/pipelines/android_test_pipeline.dart` | Modify | Same prefix changes |
| `test/pipeline_test.dart` | Modify | Update field access to use `context` |

---

### Task 1: Write PipelineContext tests (TDD - failing tests)

**Files:**
- Create: `test/pipeline_context_test.dart`

- [ ] **Step 1: Write the test file**

```dart
// test/pipeline_context_test.dart
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

void main() {
  group('PipelineContext', () {
    late PipelineContext ctx;
    late CIToolsConfig config;

    setUp(() {
      config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000);
      ctx = PipelineContext(config: config);
    });

    group('construction', () {
      test('config is accessible', () {
        expect(ctx.config, same(config));
        expect(ctx.config.appName, 'TestApp');
      });
    });

    group('buildNumber and buildName', () {
      test('buildName formats buildNumber correctly', () {
        ctx.buildNumber = 12001;
        expect(ctx.buildName, '1.2.0');
      });

      test('buildName handles zeros', () {
        ctx.buildNumber = 10000;
        expect(ctx.buildName, '1.0.0');
      });

      test('buildName handles triple digits', () {
        ctx.buildNumber = 12345;
        expect(ctx.buildName, '1.2.3');
      });
    });

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

    group('store', () {
      test('set and get with correct type', () {
        ctx.set<String>('key', 'value');
        expect(ctx.get<String>('key'), 'value');
      });

      test('set and get with different types', () {
        ctx.set<int>('count', 42);
        ctx.set<bool>('flag', true);
        expect(ctx.get<int>('count'), 42);
        expect(ctx.get<bool>('flag'), true);
      });

      test('get throws on missing key', () {
        expect(() => ctx.get<String>('missing'), throwsA(isA<TypeError>()));
      });

      test('tryGet returns value when key exists', () {
        ctx.set<String>('key', 'value');
        expect(ctx.tryGet<String>('key'), 'value');
      });

      test('tryGet returns null when key missing', () {
        expect(ctx.tryGet<String>('missing'), isNull);
      });

      test('has returns true when key exists', () {
        ctx.set<String>('key', 'value');
        expect(ctx.has('key'), isTrue);
      });

      test('has returns false when key missing', () {
        expect(ctx.has('key'), isFalse);
      });

      test('set overwrites existing key', () {
        ctx.set<String>('key', 'first');
        ctx.set<String>('key', 'second');
        expect(ctx.get<String>('key'), 'second');
      });

      test('remove returns value and deletes key', () {
        ctx.set<String>('key', 'value');
        final removed = ctx.remove<String>('key');
        expect(removed, 'value');
        expect(ctx.has('key'), isFalse);
      });

      test('remove returns null for missing key', () {
        expect(ctx.remove<String>('missing'), isNull);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/pipeline_context_test.dart`
Expected: FAIL — `pipeline_context.dart` does not exist yet.

- [ ] **Step 3: Commit the failing tests**

```bash
git add test/pipeline_context_test.dart
git commit -m "test: add PipelineContext tests (TDD red phase)"
```

---

### Task 2: Implement PipelineContext class

**Files:**
- Create: `lib/src/pipeline_context.dart`

- [ ] **Step 1: Write the implementation**

```dart
import 'build_metadata.dart';
import 'config.dart';

/// Shared context passed through all pipeline steps.
///
/// Holds immutable configuration, mutable build state, and a generic
/// key-value store for inter-step data passing.
class PipelineContext {
  /// Creates a context with the given [config].
  PipelineContext({required this.config});

  /// Application-level configuration (name, API keys, seed build number).
  final CIToolsConfig config;

  /// Git and build metadata collected at the start of the pipeline run.
  late BuildMetadata metadata;

  /// The resolved build number, set during pipeline execution.
  late int buildNumber;

  /// The human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  final Map<String, dynamic> _store = {};

  /// Stores [value] under [key]. Overwrites if key already exists.
  void set<T>(String key, T value) => _store[key] = value;

  /// Retrieves value by [key], cast to [T].
  ///
  /// Throws if the key does not exist or the value is not of type [T].
  T get<T>(String key) => _store[key] as T;

  /// Retrieves value by [key], cast to [T]. Returns null if missing.
  T? tryGet<T>(String key) => _store[key] as T?;

  /// Whether [key] exists in the store.
  bool has(String key) => _store.containsKey(key);

  /// Removes [key] from the store. Returns the removed value, or null.
  T? remove<T>(String key) => _store.remove(key) as T?;
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `dart test test/pipeline_context_test.dart`
Expected: All 13 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart
git commit -m "feat: implement PipelineContext class with typed store"
```

---

### Task 3: Update BuildPipeline to use PipelineContext

**Files:**
- Modify: `lib/src/pipeline.dart`

- [ ] **Step 1: Add import and update constructor**

In `lib/src/pipeline.dart`, add import at top:
```dart
import 'pipeline_context.dart';
```

Replace the constructor and field declarations. Change from:
```dart
abstract class BuildPipeline {
  BuildPipeline(
    this.config, {
    VersionManager? versionManager,
    GitManager? gitManager,
    DeployService? deployService,
    ShellRunner? shellRunner,
    AndroidBuilder? androidBuilder,
    IOSBuilder? iosBuilder,
  })  : _versionManager = versionManager ?? DefaultVersionManager(),
        _gitManager = gitManager ?? DefaultGitManager(),
        _deployService = deployService ?? DefaultDeployService(),
        _shellRunner = shellRunner ?? DefaultShellRunner(),
        _androidBuilder = androidBuilder ?? AndroidBuilder(),
        _iosBuilder = iosBuilder ?? IOSBuilder();

  final CIToolsConfig config;
  final VersionManager _versionManager;
  final GitManager _gitManager;
  final DeployService _deployService;
  final ShellRunner _shellRunner;
  final AndroidBuilder _androidBuilder;
  final IOSBuilder _iosBuilder;

  DeployService get deployService => _deployService;

  late int buildNumber;

  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  late final BuildMetadata metadata;
```

To:
```dart
abstract class BuildPipeline {
  BuildPipeline(
    CIToolsConfig config, {
    VersionManager? versionManager,
    GitManager? gitManager,
    DeployService? deployService,
    ShellRunner? shellRunner,
    AndroidBuilder? androidBuilder,
    IOSBuilder? iosBuilder,
  })  : context = PipelineContext(config: config),
        _versionManager = versionManager ?? DefaultVersionManager(),
        _gitManager = gitManager ?? DefaultGitManager(),
        _deployService = deployService ?? DefaultDeployService(),
        _shellRunner = shellRunner ?? DefaultShellRunner(),
        _androidBuilder = androidBuilder ?? AndroidBuilder(),
        _iosBuilder = iosBuilder ?? IOSBuilder();

  /// Shared context holding config, build state, and inter-step store.
  final PipelineContext context;

  final VersionManager _versionManager;
  final GitManager _gitManager;
  final DeployService _deployService;
  final ShellRunner _shellRunner;
  final AndroidBuilder _androidBuilder;
  final IOSBuilder _iosBuilder;

  DeployService get deployService => _deployService;

  String get buildName => context.buildName;
```

- [ ] **Step 2: Update all internal references in pipeline.dart**

Replace every `config.` with `context.config.`:
- `_coreInfoLines()` line with `apiHost` (already uses the getter, no change needed)
- `uploadToPgyerAndNotify` line: `config.pgyerApiKey!` -> `context.config.pgyerApiKey!`
- `uploadToPgyerAndNotify` line: `config.feishuWebhookUrl!` -> `context.config.feishuWebhookUrl!`
- `buildFeishuMessage` line: `config.appName` -> `context.config.appName`

Replace every `buildNumber` (bare field access, not constructor param) with `context.buildNumber`:
- `run()` step 1: `buildNumber = await _versionManager.computeNextBuildNumber(config.seedBuildNumber)` -> `context.buildNumber = await _versionManager.computeNextBuildNumber(context.config.seedBuildNumber)`
- `run()` Logger line: `buildNumber=$buildNumber` -> `buildNumber=${context.buildNumber}`
- `runAndroidOnly()` step 1: same pattern
- `runIOSOnly()` step 1: same pattern
- `_coreInfoLines()`: `$buildName` -> `${context.buildName}`, `$buildNumber` -> `${context.buildNumber}`
- `buildFeishuMessage()`: `$buildNumber` -> `${context.buildNumber}`

Replace every `metadata` with `context.metadata`:
- `run()`: `metadata = await runStep(...)` -> `context.metadata = await runStep(...)`
- `runAndroidOnly()`: same
- `runIOSOnly()`: same
- `uploadToPgyerAndNotify`: `metadata.recentCommits` -> `context.metadata.recentCommits`
- `buildFeishuMessage`: `metadata.branch`, `metadata.gitUser`, `metadata.gitHash`, `metadata.recentCommits`, `metadata.commitBody` -> add `context.` prefix

- [ ] **Step 3: Run existing pipeline tests**

Run: `dart test test/pipeline_test.dart`
Expected: Some tests will fail because `pipeline_test.dart` still accesses `pipeline.buildNumber` and `pipeline.metadata` directly. This is fixed in Task 5.

- [ ] **Step 4: Run all tests to see scope of breakage**

Run: `dart test`
Expected: `pipeline_test.dart` fails, `pipeline_registry_test.dart` may pass (it overrides `run()`), `pipeline_context_test.dart` passes.

- [ ] **Step 5: Do NOT commit yet** — fixes in Task 4 and 5 will complete this.

---

### Task 4: Add barrel export

**Files:**
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Add the export**

Add alphabetically between existing exports:
```dart
export 'src/pipeline_context.dart';
```

This goes after `export 'src/pipeline.dart';` (line 10) — actually, alphabetically it goes before `pipeline.dart`:
```dart
export 'src/pipeline.dart';
export 'src/pipeline_context.dart';
export 'src/pipeline_registry.dart';
```

- [ ] **Step 2: Verify analysis passes**

Run: `dart analyze lib/`
Expected: No errors (may have warnings about unused imports in pipeline.dart if any remain).

- [ ] **Step 3: Commit pipeline.dart + barrel export together**

```bash
git add lib/src/pipeline.dart lib/flutter_ci_tools.dart
git commit -m "refactor: migrate BuildPipeline state to PipelineContext"
```

---

### Task 5: Update example pipeline subclasses

**Files:**
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`
- Modify: `example/ci/pipelines/android_test_pipeline.dart`

- [ ] **Step 1: Update test_pipeline.dart**

In `beforeBuild()`, change:
```dart
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
```
To:
```dart
      env: envName,
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
```

- [ ] **Step 2: Update prod_pipeline.dart**

Same `beforeBuild()` change as above.

In `deployAndroid()`, change:
```dart
      config.feishuWebhookUrl!,
```
To:
```dart
      context.config.feishuWebhookUrl!,
```

In `deployIOS()`, change:
```dart
      config.feishuWebhookUrl!,
```
To:
```dart
      context.config.feishuWebhookUrl!,
```

- [ ] **Step 3: Update android_test_pipeline.dart**

Same `beforeBuild()` change as test_pipeline.dart.

- [ ] **Step 4: Run analyze on example**

Run: `dart analyze example/`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add example/ci/pipelines/
git commit -m "refactor: update example pipelines to use PipelineContext"
```

---

### Task 6: Update pipeline tests

**Files:**
- Modify: `test/pipeline_test.dart`

- [ ] **Step 1: Update buildName tests**

Change:
```dart
    test('buildName formats buildNumber correctly', () {
      final pipeline = createPipeline();
      pipeline.buildNumber = 12001;
      expect(pipeline.buildName, '1.2.0');
    });

    test('buildName handles zeros', () {
      final pipeline = createPipeline();
      pipeline.buildNumber = 10000;
      expect(pipeline.buildName, '1.0.0');
    });
```
To:
```dart
    test('buildName formats buildNumber correctly', () {
      final pipeline = createPipeline();
      pipeline.context.buildNumber = 12001;
      expect(pipeline.buildName, '1.2.0');
    });

    test('buildName handles zeros', () {
      final pipeline = createPipeline();
      pipeline.context.buildNumber = 10000;
      expect(pipeline.buildName, '1.0.0');
    });
```

- [ ] **Step 2: Update run test**

Change:
```dart
      expect(pipeline.buildNumber, 12001);
```
To:
```dart
      expect(pipeline.context.buildNumber, 12001);
```

- [ ] **Step 3: Update buildFeishuMessage test**

Change:
```dart
      pipeline.buildNumber = 12001;
      pipeline.metadata = BuildMetadata(
```
To:
```dart
      pipeline.context.buildNumber = 12001;
      pipeline.context.metadata = BuildMetadata(
```

- [ ] **Step 4: Update runAndroidOnly and runIOSOnly tests**

Change `expect(pipeline.buildNumber, 12001)` to `expect(pipeline.context.buildNumber, 12001)` in both tests.

- [ ] **Step 5: Run all tests**

Run: `dart test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add test/pipeline_test.dart
git commit -m "test: update pipeline tests to use PipelineContext"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full test suite**

Run: `dart test`
Expected: All tests PASS.

- [ ] **Step 2: Run static analysis**

Run: `dart analyze`
Expected: No errors.

- [ ] **Step 3: Verify no dead references**

Run: `grep -rn 'pipeline\.buildNumber\b' lib/ test/ example/` (should find 0 matches outside of `context.buildNumber`)
Run: `grep -rn 'pipeline\.metadata\b' lib/ test/ example/` (should find 0 matches outside of `context.metadata`)
Run: `grep -rn '\bconfig\.' lib/src/pipeline.dart` (should only find `context.config.` references)
Expected: No stale references.

- [ ] **Step 4: Commit any fixes if needed, otherwise done.**
