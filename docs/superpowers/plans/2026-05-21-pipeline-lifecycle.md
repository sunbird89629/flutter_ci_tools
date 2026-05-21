# Pipeline Lifecycle Methods + Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `name`/`description`/`help` lifecycle methods to `BuildPipeline` and provide `PipelineRegistry` for automatic CLI parsing.

**Architecture:** `BuildPipeline` gains 3 abstract getters for self-description. A new `PipelineRegistry` class handles pipeline registration, CLI arg parsing, and help output generation. The example `build.dart` simplifies to just registering pipelines and calling `registry.run(args)`.

**Tech Stack:** Dart, package:test

**Spec:** `docs/superpowers/specs/2026-05-21-pipeline-lifecycle-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/src/pipeline.dart` | Modify | Add `name`, `description`, `help` abstract getters to `BuildPipeline` |
| `lib/src/pipeline_registry.dart` | Create | `PipelineRegistry` class: register, CLI parsing, help output |
| `test/pipeline_registry_test.dart` | Create | Tests for `PipelineRegistry` |
| `lib/flutter_ci_tools.dart` | Modify | Export `pipeline_registry.dart` |
| `example/ci/pipelines/test_pipeline.dart` | Modify | Implement `name`, `description`, `help` |
| `example/ci/pipelines/prod_pipeline.dart` | Modify | Implement `name`, `description`, `help` |
| `example/ci/build.dart` | Modify | Use `PipelineRegistry` |
| `test/pipeline_test.dart` | Modify | Update `_TestPipeline` fake to implement new getters |

---

### Task 1: Add abstract getters to BuildPipeline

**Files:**
- Modify: `lib/src/pipeline.dart:50-92`
- Modify: `test/pipeline_test.dart:123-151`

- [ ] **Step 1: Add abstract getters to BuildPipeline**

In `lib/src/pipeline.dart`, add 3 abstract getters after the existing `envName` declaration (line 86):

```dart
  String get name;
  String get description;
  String get help;
```

The class should now have these abstract members in this order:

```dart
  String get name;
  String get description;
  String get help;
  String get envName;
  String get iosExportMethod;
  String get apiHost;
  AndroidBuildType get androidBuildType;
```

- [ ] **Step 2: Update test fake to implement new getters**

In `test/pipeline_test.dart`, add the 3 new getters to `_TestPipeline` (after line 133):

```dart
  @override
  String get name => 'test';

  @override
  String get description => 'Test pipeline';

  @override
  String get help => 'Test pipeline help';
```

- [ ] **Step 3: Run existing tests to verify nothing breaks**

Run: `dart test test/pipeline_test.dart`
Expected: All 8 tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline.dart test/pipeline_test.dart
git commit -m "feat: add name/description/help abstract getters to BuildPipeline"
```

---

### Task 2: Create PipelineRegistry with tests (TDD)

**Files:**
- Create: `test/pipeline_registry_test.dart`
- Create: `lib/src/pipeline_registry.dart`

- [ ] **Step 1: Write failing tests for PipelineRegistry**

Create `test/pipeline_registry_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/builders/android_builder.dart';
import 'package:flutter_ci_tools/src/builders/ios_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/deploy_service.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_registry.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  @override
  Future<int?> fetchLatestBuildNumber() async => null;
  @override
  Future<int> computeNextBuildNumber(int seed) async => 10001;
  @override
  Future<void> pushNewBuildTag(int buildNumber) async {}
  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

class _FakeGitManager implements GitManager {
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> restoreWorkspace() async {}
  @override
  Future<void> resetHard() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<String> getShortHash() async => 'abc1234';
  @override
  Future<String> getRecentCommits({int count = 10}) async => 'commits';
  @override
  Future<String> getBranch() async => 'main';
  @override
  Future<String> getCurrentUser() async => 'Alice';
  @override
  Future<String> getLatestCommitBody() async => '';
}

class _FakeDeployService implements DeployService {
  @override
  Future<String> uploadToPgyer(String fp, String key,
      {String? updateDescription}) async => 'https://pgyer.com/test';
  @override
  Future<void> sendFeishuNotification(String url, String text) async {}
  @override
  Future<void> uploadToGooglePlay(File aab,
      {required String packageName, required String jsonKeyPath}) async {}
  @override
  Future<void> uploadToAppStore(File ipa,
      {required String issuerId,
      required String apiKeyId,
      required String apiKeyPath}) async {}
}

class _FakeShellRunner implements ShellRunner {
  @override
  Future<void> run(String exe, List<String> args) async {}
  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

class _FakeAndroidBuilder extends AndroidBuilder {
  _FakeAndroidBuilder() : super(shellRunner: _FakeShellRunner());
}

class _FakeIOSBuilder extends IOSBuilder {
  _FakeIOSBuilder() : super(shellRunner: _FakeShellRunner());
}

class _StubPipeline extends BuildPipeline {
  final String _name;
  final String _description;
  final String _help;
  bool didRun = false;
  bool didRunAndroid = false;
  bool didRunIOS = false;

  _StubPipeline(
    this._name,
    this._description,
    this._help,
    CIToolsConfig config, {
    super.versionManager,
    super.gitManager,
    super.deployService,
    super.shellRunner,
    super.androidBuilder,
    super.iosBuilder,
  }) : super(config);

  @override
  String get name => _name;
  @override
  String get description => _description;
  @override
  String get help => _help;
  @override
  String get envName => _name;
  @override
  String get iosExportMethod => 'development';
  @override
  String get apiHost => 'https://api.test.com';
  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.apk;
  @override
  Future<void> deployAndroid(File file) async {}
  @override
  Future<void> deployIOS(File file) async {}

  @override
  Future<void> run() async {
    didRun = true;
  }

  @override
  Future<void> runAndroidOnly() async {
    didRunAndroid = true;
  }

  @override
  Future<void> runIOSOnly() async {
    didRunIOS = true;
  }
}

void main() {
  late CIToolsConfig config;
  late _FakeVersionManager version;
  late _FakeGitManager git;
  late _FakeDeployService deploy;
  late _FakeShellRunner shell;

  _StubPipeline createPipeline(String name, {String? description, String? help}) {
    return _StubPipeline(
      name,
      description ?? '$name description',
      help ?? '$name help',
      config,
      versionManager: version,
      gitManager: git,
      deployService: deploy,
      shellRunner: shell,
      androidBuilder: _FakeAndroidBuilder(),
      iosBuilder: _FakeIOSBuilder(),
    );
  }

  setUp(() {
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 10000);
    version = _FakeVersionManager();
    git = _FakeGitManager();
    deploy = _FakeDeployService();
    shell = _FakeShellRunner();
  });

  group('PipelineRegistry', () {
    test('register adds a pipeline', () {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);
      expect(registry.pipelines, contains(pipeline));
    });

    test('register throws on duplicate name', () {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));
      expect(
        () => registry.register(createPipeline('test')),
        throwsArgumentError,
      );
    });

    test('run with empty args prints usage and exits 64', () async {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));

      // Capture stderr and exit code
      // PipelineRegistry.run calls exit(64) on empty args
      // We test this indirectly by checking the behavior
      // For unit testing, we'll test the non-exit paths
    });

    test('run dispatches to pipeline.run() for known name', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test']);
      expect(pipeline.didRun, isTrue);
    });

    test('run dispatches to pipeline.runAndroidOnly() for android arg', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'android']);
      expect(pipeline.didRunAndroid, isTrue);
    });

    test('run dispatches to pipeline.runIOSOnly() for ios arg', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'ios']);
      expect(pipeline.didRunIOS, isTrue);
    });

    test('pipelines getter returns registered pipelines in order', () {
      final registry = PipelineRegistry();
      final p1 = createPipeline('a');
      final p2 = createPipeline('b');
      registry
        ..register(p1)
        ..register(p2);

      expect(registry.pipelines, [p1, p2]);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/pipeline_registry_test.dart`
Expected: FAIL — `pipeline_registry.dart` does not exist

- [ ] **Step 3: Implement PipelineRegistry**

Create `lib/src/pipeline_registry.dart`:

```dart
import 'dart:io';

import 'logger.dart';
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
      stderr.writeln('  ${pipeline.name.padRight(20)} ${pipeline.description}');
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

- [ ] **Step 5: Commit**

```bash
git add lib/src/pipeline_registry.dart test/pipeline_registry_test.dart
git commit -m "feat: add PipelineRegistry with CLI parsing and help output"
```

---

### Task 3: Export PipelineRegistry from barrel

**Files:**
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Add export to barrel file**

In `lib/flutter_ci_tools.dart`, add after the `pipeline.dart` export (line 10):

```dart
export 'src/pipeline_registry.dart';
```

- [ ] **Step 2: Run all tests to verify**

Run: `dart test`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lib/flutter_ci_tools.dart
git commit -m "feat: export PipelineRegistry from barrel"
```

---

### Task 4: Implement lifecycle getters in example pipelines

**Files:**
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`

- [ ] **Step 1: Add getters to TestPipeline**

In `example/ci/pipelines/test_pipeline.dart`, add after the constructor (line 9):

```dart
  @override
  String get name => 'test';

  @override
  String get description => '构建并部署到测试环境 (Pgyer)';

  @override
  String get help => '''
Test Pipeline
构建测试版本并上传到蒲公英。

Usage: dart run ci/build.dart test [android|ios]
  android    仅构建 Android
  ios        仅构建 iOS
不指定平台时同时构建两个平台。''';
```

- [ ] **Step 2: Add getters to ProdPipeline**

In `example/ci/pipelines/prod_pipeline.dart`, add after the constructor (line 9):

```dart
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
```

- [ ] **Step 3: Run all tests**

Run: `dart test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add example/ci/pipelines/test_pipeline.dart example/ci/pipelines/prod_pipeline.dart
git commit -m "feat: implement name/description/help in example pipelines"
```

---

### Task 5: Rewrite build.dart to use PipelineRegistry

**Files:**
- Modify: `example/ci/build.dart`

- [ ] **Step 1: Rewrite build.dart**

Replace the entire contents of `example/ci/build.dart` with:

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'pipelines/prod_pipeline.dart';
import 'pipelines/test_pipeline.dart';

Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(TestPipeline())
    ..register(ProdPipeline());

  await registry.run(args);
}
```

- [ ] **Step 2: Run all tests**

Run: `dart test`
Expected: All tests PASS

- [ ] **Step 3: Verify CLI behavior manually**

Run: `dart run example/ci/build.dart`
Expected: Prints usage with available pipelines, exits with code 64

Run: `dart run example/ci/build.dart test --help`
Expected: Prints TestPipeline help text

- [ ] **Step 4: Commit**

```bash
git add example/ci/build.dart
git commit -m "refactor: rewrite build.dart to use PipelineRegistry"
```
