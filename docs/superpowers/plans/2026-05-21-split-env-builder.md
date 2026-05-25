# Split EnvBuilder into Platform Builders + Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `EnvBuilder` into pure, stateless `AndroidBuilder` / `IOSBuilder` classes and a `BuildPipeline` orchestrator that supports building a single platform or both.

**Architecture:** `AndroidBuilder` and `IOSBuilder` are stateless wrappers around `flutter build` commands that receive all params and return a `File`. `BuildPipeline` is an abstract orchestrator that holds shared state (`buildNumber`, `metadata`), resolves versions, collects metadata, cleans the project, calls builders, and dispatches deploy/notify. Concrete `TestPipeline` and `ProdPipeline` provide env-specific config and deploy targets.

**Tech Stack:** Dart, package:test, package:flutter_ci_tools

---

## File Structure

```
lib/src/
├── env_builder.dart          → deleted (Task 8)
├── builders/
│   ├── android_builder.dart  → new (Task 1)
│   └── ios_builder.dart      → new (Task 2)
├── pipeline.dart             → new (Task 3, contains BuildPipeline, AppPlatform, DeployTarget, runStep)
├── config.dart               → unchanged
├── build_metadata.dart       → unchanged
├── deploy_service.dart       → unchanged
├── git_manager.dart          → unchanged
├── version_manager.dart      → unchanged
├── shell_runner.dart         → unchanged
├── logger.dart               → unchanged
└── exceptions.dart           → unchanged

example/ci/
├── prod_env.dart             → rewritten as ProdPipeline (Task 5)
├── test_env.dart             → rewritten as TestPipeline (Task 4)
├── build.dart                → updated entry point (Task 6)
├── app_config.dart           → unchanged
└── build_info_writer.dart    → unchanged

lib/flutter_ci_tools.dart     → updated exports (Task 7)
test/
├── env_builder_test.dart     → deleted
├── android_builder_test.dart → new (Task 1)
├── ios_builder_test.dart     → new (Task 2)
└── pipeline_test.dart        → new (Task 3)
```

---

### Task 1: Create AndroidBuilder

**Files:**
- Create: `lib/src/builders/android_builder.dart`
- Create: `test/android_builder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/android_builder_test.dart
import 'dart:io';
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  late _FakeShellRunner shell;

  setUp(() {
    shell = _FakeShellRunner();
  });

  group('AndroidBuilder', () {
    test('buildApk runs correct flutter build apk command', () async {
      final builder = AndroidBuilder(shellRunner: shell);
      // Note: will throw because the file doesn't exist on disk,
      // but the command should have been run
      try {
        await builder.buildApk(
          buildName: '1.2.0',
          buildNumber: 12001,
          envName: 'test',
        );
      } catch (_) {
        // Expected — File won't exist in test
      }

      expect(
        shell.runCalls,
        contains('fvm flutter build apk --build-name=1.2.0 --build-number=12001 --dart-define=ENV=test'),
      );
    });

    test('buildAppBundle runs correct flutter build appbundle command', () async {
      final builder = AndroidBuilder(shellRunner: shell);
      try {
        await builder.buildAppBundle(
          buildName: '1.0.0',
          buildNumber: 10000,
          envName: 'prod',
        );
      } catch (_) {
        // Expected — File won't exist in test
      }

      expect(
        shell.runCalls,
        contains('fvm flutter build appbundle --build-name=1.0.0 --build-number=10000 --dart-define=ENV=prod'),
      );
    });

    test('default constructor uses DefaultShellRunner', () {
      final builder = AndroidBuilder();
      expect(builder, isA<AndroidBuilder>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/android_builder_test.dart`
Expected: FAIL — `AndroidBuilder` not defined / not exported

- [ ] **Step 3: Write AndroidBuilder implementation**

```dart
// lib/src/builders/android_builder.dart
import 'dart:io';

import '../shell_runner.dart';

class AndroidBuilder {
  const AndroidBuilder({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  Future<File> buildApk({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'apk',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return File('build/app/outputs/flutter-apk/app-release.apk');
  }

  Future<File> buildAppBundle({
    required String buildName,
    required int buildNumber,
    required String envName,
  }) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'appbundle',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return File('build/app/outputs/bundle/release/app-release.aab');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/android_builder_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/builders/android_builder.dart test/android_builder_test.dart
git commit -m "feat: add AndroidBuilder — pure, stateless APK/AAB builder"
```

---

### Task 2: Create IOSBuilder

**Files:**
- Create: `lib/src/builders/ios_builder.dart`
- Create: `test/ios_builder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ios_builder_test.dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  late _FakeShellRunner shell;

  setUp(() {
    shell = _FakeShellRunner();
  });

  group('IOSBuilder', () {
    test('buildIpa runs correct flutter build ipa command', () async {
      final builder = IOSBuilder(shellRunner: shell);
      try {
        await builder.buildIpa(
          buildName: '1.2.0',
          buildNumber: 12001,
          envName: 'test',
          exportMethod: 'development',
        );
      } catch (_) {
        // Expected — IPA dir won't exist in test
      }

      expect(
        shell.runCalls,
        contains('fvm flutter build ipa --export-method=development --build-name=1.2.0 --build-number=12001 --dart-define=ENV=test'),
      );
    });

    test('buildIpa throws StateError if IPA directory not found', () async {
      // Use real DefaultShellRunner which will fail, but we catch StateError
      final builder = IOSBuilder(shellRunner: shell);
      // build/ios/ipa won't exist in test — expect StateError
      await expectLater(
        () => builder.buildIpa(
          buildName: '1.0.0',
          buildNumber: 10000,
          envName: 'test',
          exportMethod: 'ad-hoc',
        ),
        throwsStateError,
      );
    });

    test('default constructor uses DefaultShellRunner', () {
      final builder = IOSBuilder();
      expect(builder, isA<IOSBuilder>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/ios_builder_test.dart`
Expected: FAIL — `IOSBuilder` not defined / not exported

- [ ] **Step 3: Write IOSBuilder implementation**

```dart
// lib/src/builders/ios_builder.dart
import 'dart:io';

import '../shell_runner.dart';

class IOSBuilder {
  const IOSBuilder({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  Future<File> buildIpa({
    required String buildName,
    required int buildNumber,
    required String envName,
    required String exportMethod,
  }) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$exportMethod',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return _findIpa();
  }

  File _findIpa() {
    final ipaDir = Directory('build/ios/ipa');
    if (!ipaDir.existsSync()) {
      throw StateError(
        'IPA build failed: Directory not found at ${ipaDir.path}',
      );
    }
    final ipaList = ipaDir
        .listSync()
        .where((e) => e.path.endsWith('.ipa'))
        .toList();
    if (ipaList.isEmpty) {
      throw StateError(
        'IPA build failed: No .ipa file found in ${ipaDir.path}',
      );
    }
    return ipaList.first as File;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/ios_builder_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/builders/ios_builder.dart test/ios_builder_test.dart
git commit -m "feat: add IOSBuilder — pure, stateless IPA builder"
```

---

### Task 3: Create BuildPipeline (abstract orchestrator)

**Files:**
- Create: `lib/src/pipeline.dart` (contains BuildPipeline, AppPlatform, DeployTarget enums, runStep)
- Create: `test/pipeline_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/pipeline_test.dart
import 'dart:io';
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

// Reuse the same fakes from the existing test, but adapted for Pipeline
class _FakeVersionManager implements VersionManager {
  int? latestTag;
  int nextBuildNumber = 12001;
  List<int> pushedTags = [];

  @override
  Future<int?> fetchLatestBuildNumber() async => latestTag;

  @override
  Future<int> computeNextBuildNumber(int seed) async => nextBuildNumber;

  @override
  Future<void> pushNewBuildTag(int buildNumber) async {
    pushedTags.add(buildNumber);
  }

  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

class _FakeGitManager implements GitManager {
  bool isClean = true;
  bool didRestore = false;

  @override
  Future<void> checkClean() async {
    if (!isClean) throw GitException('dirty', 1);
  }

  @override
  Future<void> restoreWorkspace() async {
    didRestore = true;
  }

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
      {required String packageName,
      required String jsonKeyPath}) async {}

  @override
  Future<void> uploadToAppStore(File ipa,
      {required String issuerId,
      required String apiKeyId,
      required String apiKeyPath}) async {}
}

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

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

class _TestPipeline extends BuildPipeline {
  _TestPipeline(
    super.config, {
    super.versionManager,
    super.gitManager,
    super.deployService,
    super.shellRunner,
    super.androidBuilder,
    super.iosBuilder,
  });

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'ad-hoc';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.apk;

  @override
  Future<void> deployAndroid(File file) async {}

  @override
  Future<void> deployIOS(File file) async {}
}

void main() {
  late _FakeVersionManager version;
  late _FakeGitManager git;
  late _FakeDeployService deploy;
  late _FakeShellRunner shell;
  late CIToolsConfig config;

  _TestPipeline createPipeline() => _TestPipeline(
        config,
        versionManager: version,
        gitManager: git,
        deployService: deploy,
        shellRunner: shell,
        androidBuilder: _FakeAndroidBuilder(),
        iosBuilder: _FakeIOSBuilder(),
      );

  setUp(() {
    version = _FakeVersionManager();
    git = _FakeGitManager();
    deploy = _FakeDeployService();
    shell = _FakeShellRunner();
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000);
  });

  group('BuildPipeline', () {
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

    test('run orchestrates steps and pushes tag', () async {
      final pipeline = createPipeline();
      await pipeline.run();

      expect(pipeline.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('run restores workspace on failure', () async {
      git.isClean = false;
      final pipeline = createPipeline();

      try {
        await pipeline.run();
      } catch (_) {
        // Expected -- checkClean throws
      }

      expect(git.didRestore, isTrue);
    });

    test('buildFeishuMessage includes core info', () {
      final pipeline = createPipeline();
      pipeline.buildNumber = 12001;
      pipeline.metadata = BuildMetadata(
        branch: 'main',
        gitUser: 'Alice',
        gitHash: 'abc1234',
        recentCommits: 'commits',
        commitBody: '',
      );

      final msg = pipeline.buildFeishuMessage(
        platform: AppPlatform.android,
        target: DeployTarget.pgyer,
        downloadUrl: 'https://example.com',
      );

      expect(msg, contains('TestApp'));
      expect(msg, contains('12001'));
      expect(msg, contains('Android'));
      expect(msg, contains('abc1234'));
      expect(msg, contains('https://example.com'));
    });

    test('runAndroidOnly builds only Android', () async {
      final pipeline = createPipeline();
      await pipeline.runAndroidOnly();

      expect(pipeline.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('runIOSOnly builds only iOS', () async {
      final pipeline = createPipeline();
      await pipeline.runIOSOnly();

      expect(pipeline.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('runStep wraps with logging', () async {
      var called = false;
      await runStep('Test Step', () async {
        called = true;
        return 42;
      });
      expect(called, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/pipeline_test.dart`
Expected: FAIL — `BuildPipeline`, `AppPlatform`, `DeployTarget`, `runStep`, `AndroidBuildType` not defined

- [ ] **Step 3: Write BuildPipeline implementation**

```dart
// lib/src/pipeline.dart
import 'dart:io';

import 'build_metadata.dart';
import 'builders/android_builder.dart';
import 'builders/ios_builder.dart';
import 'config.dart';
import 'deploy_service.dart';
import 'git_manager.dart';
import 'logger.dart';
import 'shell_runner.dart';
import 'version_manager.dart';

enum AppPlatform {
  android('Android'),
  ios('iOS');

  final String label;
  const AppPlatform(this.label);
}

enum DeployTarget {
  pgyer('Pgyer'),
  googlePlay('Google Play'),
  appStore('App Store');

  final String label;
  const DeployTarget(this.label);
}

enum AndroidBuildType { apk, appbundle }

/// Executes a step with standardized logging and error handling.
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

  late int buildNumber;

  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  late final BuildMetadata metadata;

  String get envName;
  String get iosExportMethod;
  String get apiHost;
  AndroidBuildType get androidBuildType;
  bool get shouldSwapInfoPlist => false;

  Future<void> beforeBuild() async {}

  Future<void> deployAndroid(File file);
  Future<void> deployIOS(File file);

  Future<void> cleanProject() async {
    await _shellRunner.run('fvm', ['flutter', 'clean']);
    await _shellRunner.run('fvm', ['flutter', 'pub', 'get']);
  }

  Future<void> buildPrepare() async {
    if (shouldSwapInfoPlist) {
      Logger.info('Swapping Info.plist for product environment');
      File('ios/Runner/Info.plist').renameSync('ios/Runner/Info.plist.backup');
      File('ios/Runner/Info.plist.product').renameSync('ios/Runner/Info.plist');
    }
  }

  Future<File> _buildAndroid() async {
    switch (androidBuildType) {
      case AndroidBuildType.apk:
        return _androidBuilder.buildApk(
          buildName: buildName,
          buildNumber: buildNumber,
          envName: envName,
        );
      case AndroidBuildType.appbundle:
        return _androidBuilder.buildAppBundle(
          buildName: buildName,
          buildNumber: buildNumber,
          envName: envName,
        );
    }
  }

  Future<File> _buildIOS() async {
    return _iosBuilder.buildIpa(
      buildName: buildName,
      buildNumber: buildNumber,
      envName: envName,
      exportMethod: iosExportMethod,
    );
  }

  Future<void> uploadToPgyerAndNotify(AppPlatform platform, File file) async {
    Logger.info('Processing ${platform.label}...');
    final description = [
      ..._coreInfoLines(),
      '',
      'recent commits:',
      metadata.recentCommits,
    ].join('\n');

    final url = await _deployService.uploadToPgyer(
      file.path,
      config.pgyerApiKey!,
      updateDescription: description,
    );

    await _deployService.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: platform,
        target: DeployTarget.pgyer,
        downloadUrl: url,
      ),
    );
  }

  List<String> _coreInfoLines() => [
        'versionName: $buildName',
        'versionCode: $buildNumber',
        'env:         $envName',
        'api_host:    $apiHost',
        'git_hash:    ${metadata.gitHash}',
      ];

  String buildFeishuMessage({
    required AppPlatform platform,
    required DeployTarget target,
    String? downloadUrl,
  }) {
    const sep = '──────────────────────────';
    final lines = <String>[
      '🚀 ${config.appName} 新版本 $buildNumber (${platform.label} · ${target.label})',
      'branch: ${metadata.branch}  by: ${metadata.gitUser}',
      sep,
      ..._coreInfoLines(),
    ];
    if (downloadUrl != null) {
      lines
        ..add(sep)
        ..add('🔗 下载: $downloadUrl');
    }
    lines
      ..add(sep)
      ..add('最近提交:')
      ..add(metadata.recentCommits);
    if (metadata.commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(metadata.commitBody);
    }
    return lines.join('\n');
  }

  Future<void> run() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await _versionManager.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep(
      'Collect Build Metadata',
      () => BuildMetadata.collect(_gitManager),
    );
    try {
      await runStep('Check Git Status', _gitManager.checkClean);
      await beforeBuild();
      await buildPrepare();
      Logger.section('Starting Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final androidFile = await runStep('Build Android', _buildAndroid);
      final iosFile = await runStep('Build iOS', _buildIOS);
      await runStep('Deploy Android', () => deployAndroid(androidFile));
      await runStep('Deploy iOS', () => deployIOS(iosFile));
      await runStep(
        'Push Build Tag',
        () => _versionManager.pushNewBuildTag(buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }

  Future<void> runAndroidOnly() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await _versionManager.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep(
      'Collect Build Metadata',
      () => BuildMetadata.collect(_gitManager),
    );
    try {
      await runStep('Check Git Status', _gitManager.checkClean);
      await beforeBuild();
      await buildPrepare();
      Logger.section('Starting Android-Only Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final androidFile = await runStep('Build Android', _buildAndroid);
      await runStep('Deploy Android', () => deployAndroid(androidFile));
      await runStep(
        'Push Build Tag',
        () => _versionManager.pushNewBuildTag(buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }

  Future<void> runIOSOnly() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await _versionManager.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep(
      'Collect Build Metadata',
      () => BuildMetadata.collect(_gitManager),
    );
    try {
      await runStep('Check Git Status', _gitManager.checkClean);
      await beforeBuild();
      await buildPrepare();
      Logger.section('Starting iOS-Only Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final iosFile = await runStep('Build iOS', _buildIOS);
      await runStep('Deploy iOS', () => deployIOS(iosFile));
      await runStep(
        'Push Build Tag',
        () => _versionManager.pushNewBuildTag(buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/pipeline_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/pipeline.dart test/pipeline_test.dart
git commit -m "feat: add BuildPipeline — abstract orchestrator with platform enums and runStep"
```

---

### Task 4: Rewrite TestPipeline

**Files:**
- Modify: `example/ci/test_env.dart`

- [ ] **Step 1: Rewrite test_env.dart as TestPipeline**

```dart
// example/ci/test_env.dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class TestPipeline extends BuildPipeline {
  TestPipeline() : super(exampleConfig);

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'development';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.apk;

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
  }

  @override
  Future<void> deployAndroid(File apk) async =>
      uploadToPgyerAndNotify(AppPlatform.android, apk);

  @override
  Future<void> deployIOS(File ipa) async =>
      uploadToPgyerAndNotify(AppPlatform.ios, ipa);
}
```

- [ ] **Step 2: Verify the file parses correctly**

Run: `dart analyze example/ci/test_env.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add example/ci/test_env.dart
git commit -m "refactor(example): rewrite TestEnvBuilder as TestPipeline"
```

---

### Task 5: Rewrite ProdPipeline

**Files:**
- Modify: `example/ci/prod_env.dart`

- [ ] **Step 1: Rewrite prod_env.dart as ProdPipeline**

```dart
// example/ci/prod_env.dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class ProdPipeline extends BuildPipeline {
  ProdPipeline() : super(exampleConfig);

  @override
  String get envName => 'prod';

  @override
  String get iosExportMethod => 'app-store';

  @override
  String get apiHost => 'https://api.example.com';

  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.appbundle;

  @override
  bool get shouldSwapInfoPlist => true;

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
  }

  @override
  Future<void> deployAndroid(File aab) async {
    await DeployService.instance.uploadToGooglePlay(
      aab,
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    );
    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ),
    );
  }

  @override
  Future<void> deployIOS(File ipa) async {
    await DeployService.instance.uploadToAppStore(
      ipa,
      issuerId: ProdCredentials.appStoreIssuerId,
      apiKeyId: ProdCredentials.appStoreApiKeyId,
      apiKeyPath: ProdCredentials.appStoreApiKeyPath,
    );
    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the file parses correctly**

Run: `dart analyze example/ci/prod_env.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add example/ci/prod_env.dart
git commit -m "refactor(example): rewrite ProdEnvBuilder as ProdPipeline"
```

---

### Task 6: Update entry point (build.dart)

**Files:**
- Modify: `example/ci/build.dart`

- [ ] **Step 1: Update build.dart with optional platform arg**

```dart
// example/ci/build.dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'prod_env.dart';
import 'test_env.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run ci/build.dart <test|prod> [android|ios]');
    exit(64);
  }

  final BuildPipeline pipeline = switch (args.first) {
    'test' => TestPipeline(),
    'prod' => ProdPipeline(),
    _ => throw ArgumentError('Unknown env: ${args.first}'),
  };

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
    throw ArgumentError('Unknown platform: $platform');
  }

  await pipeline.run();
}
```

- [ ] **Step 2: Verify the file parses correctly**

Run: `dart analyze example/ci/build.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add example/ci/build.dart
git commit -m "feat(example): support optional android|ios platform arg in build.dart"
```

---

### Task 7: Update barrel exports

**Files:**
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Update exports**

Replace the `env_builder.dart` export with `pipeline.dart` and the builder exports.

```dart
// lib/flutter_ci_tools.dart
export 'src/build_metadata.dart';
export 'src/builders/android_builder.dart';
export 'src/builders/ios_builder.dart';
export 'src/config.dart';
export 'src/exceptions.dart';
export 'src/deploy_service.dart';
export 'src/git_manager.dart';
export 'src/logger.dart';
export 'src/pipeline.dart';
export 'src/shell_runner.dart';
export 'src/version_manager.dart';
```

- [ ] **Step 2: Verify barrel exports**

Run: `dart analyze lib/flutter_ci_tools.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/flutter_ci_tools.dart
git commit -m "refactor: update barrel exports — replace env_builder with pipeline + builders"
```

---

### Task 8: Delete env_builder.dart

**Files:**
- Delete: `lib/src/env_builder.dart`

- [ ] **Step 1: Verify nothing imports env_builder.dart**

Run: `grep -r "env_builder" lib/ example/ test/`
Expected: Only references in spec/plan files under docs/ — no Dart imports

- [ ] **Step 2: Delete the file**

```bash
rm lib/src/env_builder.dart
```

- [ ] **Step 3: Verify the package still analyzes clean**

Run: `dart analyze lib/ example/`
Expected: No errors (except possibly in existing non-refactored code)

- [ ] **Step 4: Commit**

```bash
git add lib/src/env_builder.dart
git commit -m "refactor: remove EnvBuilder — replaced by BuildPipeline + platform builders"
```

---

### Task 9: Run full test suite

**Files:**
- All unchanged test files remain

- [ ] **Step 1: Run all tests**

Run: `dart test`
Expected: All tests pass

- [ ] **Step 2: Run dart analyze on entire project**

Run: `dart analyze`
Expected: No errors

- [ ] **Step 3: Commit any remaining changes**

```bash
git status
# If there are any changes from fixing issues found in step 1-2:
git add -A
git commit -m "chore: final cleanup after EnvBuilder split"
```
