# Architecture Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Action coupling (late fields, inconsistent data flow) and clean up public API for pub.dev release.

**Architecture:** Replace `late int buildNumber` with a sealed type for compile-time state encoding. Add `buildArtifact` to PipelineContext so all inter-action data flows through context. Rename `Default*` utility classes to `*Impl`.

**Tech Stack:** Dart, package:test

**Spec:** `docs/superpowers/specs/2026-05-26-architecture-cleanup-design.md`

---

## File Map

| File | Change |
|------|--------|
| `lib/src/pipeline_context.dart` | Sealed type for buildNumber, add buildArtifact |
| `lib/src/actions/build_android_action.dart` | Return void, write to context |
| `lib/src/actions/build_ios_action.dart` | Return void, write to context |
| `lib/src/actions/pgyer_upload_action.dart` | Read artifact from context |
| `lib/src/actions/pgyer_upload_v2_action.dart` | Read artifact from context |
| `lib/src/actions/google_play_action.dart` | Read artifact from context |
| `lib/src/actions/app_store_action.dart` | Read artifact from context |
| `lib/src/utils/default_shell_runner.dart` | Rename to shell_runner_impl.dart, class to ShellRunnerImpl |
| `lib/src/utils/git_manager.dart` | Extract DefaultGitManager to git_manager_impl.dart |
| `lib/src/utils/version_manager.dart` | Extract DefaultVersionManager to version_manager_impl.dart |
| `lib/flutter_ci_tools.dart` | Update barrel exports |
| `test/pipeline_context_test.dart` | Update for sealed type + buildArtifact |
| `test/actions/build_android_action_test.dart` | Update for void return + context write |
| `test/actions/build_ios_action_test.dart` | Update for void return + context write |
| `test/actions/pgyer_upload_action_test.dart` | Update for context-based artifact |
| `test/actions/pgyer_upload_v2_action_test.dart` | Update for context-based artifact |
| `test/actions/google_play_action_test.dart` | Update for context-based artifact |
| `test/actions/app_store_action_test.dart` | Update for context-based artifact |
| `example/ci/pipelines/*.dart` | Update for new API |
| All public API files | Add dartdoc comments |

---

### Task 1: Add sealed BuildVersion type to PipelineContext

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Modify: `test/pipeline_context_test.dart`

- [ ] **Step 1: Write failing tests for sealed BuildVersion**

Replace the contents of `test/pipeline_context_test.dart` with:

```dart
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

void main() {
  group('PipelineContext', () {
    late PipelineContext ctx;

    setUp(() {
      ctx = PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 12000,
        platforms: <AppPlatform>{},
      );
    });

    group('construction', () {
      test('exposes config fields', () {
        expect(ctx.appName, 'TestApp');
        expect(ctx.seedBuildNumber, 12000);
      });

      test('exposes platforms passed to constructor', () {
        final context = PipelineContext(
          appName: 'A',
          seedBuildNumber: 10000,
          platforms: {AppPlatform.android},
        );
        expect(context.platforms, {AppPlatform.android});
      });
    });

    group('buildNumber (sealed)', () {
      test('throws StateError when accessed before resolution', () {
        expect(
          () => ctx.buildNumber,
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('buildNumber'),
          )),
        );
      });

      test('returns value after resolveBuildVersion', () {
        ctx.resolveBuildVersion(12001);
        expect(ctx.buildNumber, 12001);
      });

      test('buildName formats buildNumber correctly', () {
        ctx.resolveBuildVersion(12001);
        expect(ctx.buildName, '1.2.0');
      });

      test('buildName handles zeros', () {
        ctx.resolveBuildVersion(10000);
        expect(ctx.buildName, '1.0.0');
      });

      test('buildName handles triple digits', () {
        ctx.resolveBuildVersion(12345);
        expect(ctx.buildName, '1.2.3');
      });
    });

    group('buildArtifact', () {
      test('throws StateError when accessed before being set', () {
        expect(
          () => ctx.buildArtifact,
          throwsA(isA<StateError>()),
        );
      });

      test('returns file after setBuildArtifact', () {
        final file = ctx.setBuildArtifact as dynamic;
        // Will be tested properly after implementation
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/pipeline_context_test.dart`
Expected: FAIL — `resolveBuildVersion` and `buildArtifact` don't exist yet, `buildNumber` assignment syntax changed.

- [ ] **Step 3: Implement sealed BuildVersion + buildArtifact in PipelineContext**

Replace `lib/src/pipeline_context.dart` with:

```dart
import 'dart:io';

import 'build_metadata.dart';
import 'pipeline.dart' show AppPlatform;

/// State of the build version number.
sealed class BuildVersion {}

/// Build version has not yet been resolved by [ResolveBuildVersionAction].
class BuildVersionUnresolved extends BuildVersion {}

/// Build version was resolved to a concrete [value].
class BuildVersionResolved extends BuildVersion {
  final int value;
  BuildVersionResolved(this.value);
}

/// Shared, mutable context passed through all pipeline steps.
///
/// Holds both static configuration (app identity, platforms) provided at
/// construction time and runtime state (metadata, build number, build artifact)
/// populated by lifecycle actions during a single pipeline run.
///
/// Subclass this to bundle reusable configuration across multiple pipelines.
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
  });

  /// Display name of the application (used in notifications).
  final String appName;

  /// Starting build number used when no existing `builds/*` tag is found.
  final int seedBuildNumber;

  /// Platforms this pipeline run targets.
  final Set<AppPlatform> platforms;

  /// Git and build metadata, populated by `CollectMetadataAction`.
  late BuildMetadata metadata;

  BuildVersion _buildVersion = BuildVersionUnresolved();

  /// Resolved build number.
  ///
  /// Throws [StateError] if accessed before [resolveBuildVersion] is called
  /// (typically by `ResolveBuildVersionAction`).
  int get buildNumber => switch (_buildVersion) {
        BuildVersionUnresolved() => throw StateError(
            'buildNumber 尚未解析。请确保先执行 ResolveBuildVersionAction。',
          ),
        BuildVersionResolved(:final value) => value,
      };

  /// Sets the build number. Called by `ResolveBuildVersionAction`.
  void resolveBuildVersion(int version) {
    _buildVersion = BuildVersionResolved(version);
  }

  /// Human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  File? _buildArtifact;

  /// The build artifact file produced by a build action.
  ///
  /// Throws [StateError] if accessed before a build action sets it
  /// (e.g. `BuildAndroidAction` or `BuildIOSAction`).
  File get buildArtifact => _buildArtifact ??
      throw StateError(
        'buildArtifact 尚未设置。请先执行 BuildAndroidAction 或 BuildIOSAction。',
      );

  /// Sets the build artifact file. Called by build actions.
  void setBuildArtifact(File file) => _buildArtifact = file;
}
```

- [ ] **Step 4: Fix the incomplete buildArtifact test**

Update the `buildArtifact` test group in `test/pipeline_context_test.dart`:

```dart
    group('buildArtifact', () {
      test('throws StateError when accessed before being set', () {
        expect(
          () => ctx.buildArtifact,
          throwsA(isA<StateError>()),
        );
      });

      test('returns file after setBuildArtifact', () {
        final file = File('test.apk');
        ctx.setBuildArtifact(file);
        expect(ctx.buildArtifact, file);
      });
    });
```

- [ ] **Step 5: Run all tests to verify**

Run: `dart test test/pipeline_context_test.dart`
Expected: All tests pass.

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `dart test`
Expected: Other tests that use `context.buildNumber = X` will fail — those are updated in later tasks.

- [ ] **Step 7: Commit**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart
git commit -m "refactor: replace late buildNumber with sealed BuildVersion type"
```

---

### Task 2: Update BuildAndroidAction — return void, write to context

**Files:**
- Modify: `lib/src/actions/build_android_action.dart`
- Modify: `test/actions/build_android_action_test.dart`

- [ ] **Step 1: Update BuildAndroidAction**

Replace `lib/src/actions/build_android_action.dart`:

```dart
import 'dart:io';

import '../pipeline_context.dart';
import '../utils/default_shell_runner.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Android build output format.
enum AndroidBuildType {
  /// Standard APK package.
  apk,

  /// Android App Bundle for Play Store upload.
  appbundle,
}

/// Builds an Android artifact (APK or AAB) and stores it in context.
///
/// Reads `context.buildName` and `context.buildNumber` — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
///
/// After completion, the output file is available via `context.buildArtifact`.
class BuildAndroidAction extends PipelineAction<void> {
  BuildAndroidAction({
    required this.envName,
    required this.buildType,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String envName;
  final AndroidBuildType buildType;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Build Android';

  @override
  Future<void> run(PipelineContext context) async {
    final (subcommand, outputPath) = switch (buildType) {
      AndroidBuildType.apk => (
          'apk',
          'build/app/outputs/flutter-apk/app-release.apk',
        ),
      AndroidBuildType.appbundle => (
          'appbundle',
          'build/app/outputs/bundle/release/app-release.aab',
        ),
    };
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      subcommand,
      '--build-name=${context.buildName}',
      '--build-number=${context.buildNumber}',
      '--dart-define=ENV=$envName',
    ]);
    context.setBuildArtifact(File(outputPath));
  }
}
```

- [ ] **Step 2: Update the test**

Replace `test/actions/build_android_action_test.dart`:

```dart
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
  late PipelineContext context;

  setUp(() {
    shell = _FakeShellRunner();
    context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      platforms: <AppPlatform>{},
    )..resolveBuildVersion(12001);
  });

  test('BuildAndroidAction(apk) stores apk in context', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.apk,
      shellRunner: shell,
    );

    await action.run(context);

    expect(action.name, 'Build Android');
    expect(context.buildArtifact.path,
        'build/app/outputs/flutter-apk/app-release.apk');
    expect(
      shell.runCalls,
      contains(
        'fvm flutter build apk --build-name=1.2.0 --build-number=12001 --dart-define=ENV=prod',
      ),
    );
  });

  test('BuildAndroidAction(appbundle) stores aab in context', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.appbundle,
      shellRunner: shell,
    );

    await action.run(context);

    expect(context.buildArtifact.path,
        'build/app/outputs/bundle/release/app-release.aab');
    expect(
      shell.runCalls,
      contains(
        'fvm flutter build appbundle --build-name=1.2.0 --build-number=12001 --dart-define=ENV=prod',
      ),
    );
  });

  test('BuildAndroidAction default constructor does not throw', () {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.apk,
    );
    expect(action, isA<BuildAndroidAction>());
  });
}
```

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/build_android_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/build_android_action.dart test/actions/build_android_action_test.dart
git commit -m "refactor: BuildAndroidAction writes artifact to context instead of returning"
```

---

### Task 3: Update BuildIOSAction — return void, write to context

**Files:**
- Modify: `lib/src/actions/build_ios_action.dart`
- Modify: `test/actions/build_ios_action_test.dart`

- [ ] **Step 1: Update BuildIOSAction**

In `lib/src/actions/build_ios_action.dart`, change:
- Class declaration: `PipelineAction<File>` → `PipelineAction<void>`
- `run` return type: `Future<File>` → `Future<void>`
- Instead of `return _findIpa()`, do `context.setBuildArtifact(_findIpa());`

The `run` method becomes:

```dart
  @override
  Future<void> run(PipelineContext context) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$exportMethod',
      '--build-name=${context.buildName}',
      '--build-number=${context.buildNumber}',
      '--dart-define=ENV=$envName',
    ]);
    context.setBuildArtifact(_findIpa());
  }
```

Also update the class doc comment:

```dart
/// Builds an iOS IPA and stores it in context.
///
/// Reads `context.buildName` and `context.buildNumber` — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
///
/// After completion, the output file is available via `context.buildArtifact`.
```

- [ ] **Step 2: Update the test**

In `test/actions/build_ios_action_test.dart`:
- Change `context..buildNumber = 12001` → `context..resolveBuildVersion(12001)`
- The first test can no longer check `file.path` since run returns void. Instead, check `context.buildArtifact.path` — but note the test catches `StateError` from `_findIpa()`, so the artifact won't be set. Adjust the test to only verify the shell command was called correctly.

Updated test file:

```dart
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
  late PipelineContext context;

  setUp(() {
    shell = _FakeShellRunner();
    context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      platforms: <AppPlatform>{},
    )..resolveBuildVersion(12001);
  });

  test('BuildIOSAction runs flutter build ipa with correct args', () async {
    final action = BuildIOSAction(
      envName: 'prod',
      exportMethod: 'app-store',
      shellRunner: shell,
    );

    // _findIpa will throw StateError because build/ios/ipa won't exist,
    // but the flutter build command should have been run first.
    try {
      await action.run(context);
    } on StateError {
      // Expected — _findIpa fails because the directory doesn't exist
    }

    expect(action.name, 'Build iOS');
    expect(
      shell.runCalls,
      contains(
        'fvm flutter build ipa --export-method=app-store --build-name=1.2.0 --build-number=12001 --dart-define=ENV=prod',
      ),
    );
  });

  test('BuildIOSAction throws StateError if IPA directory not found',
      () async {
    final action = BuildIOSAction(
      envName: 'test',
      exportMethod: 'ad-hoc',
      shellRunner: shell,
    );

    await expectLater(action.run(context), throwsStateError);
  });

  test('BuildIOSAction default constructor does not throw', () {
    final action = BuildIOSAction(envName: 'prod', exportMethod: 'app-store');
    expect(action, isA<BuildIOSAction>());
  });
}
```

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/build_ios_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/build_ios_action.dart test/actions/build_ios_action_test.dart
git commit -m "refactor: BuildIOSAction writes artifact to context instead of returning"
```

---

### Task 4: Update PgyerUploadAction — read artifact from context

**Files:**
- Modify: `lib/src/actions/pgyer_upload_action.dart`
- Modify: `test/actions/pgyer_upload_action_test.dart`

- [ ] **Step 1: Update PgyerUploadAction**

In `lib/src/actions/pgyer_upload_action.dart`:
- Remove `required this.artifact` from constructor
- Remove `final File artifact;` field
- In `run()`, replace `final filePath = artifact.path;` with `final filePath = context.buildArtifact.path;`

Updated class:

```dart
/// Uploads a build artifact to Pgyer and returns the download URL.
///
/// Reads `context.buildArtifact` — requires a build action
/// (e.g. `BuildAndroidAction` or `BuildIOSAction`) earlier in the pipeline.
class PgyerUploadAction extends PipelineAction<String> {
  PgyerUploadAction({
    required this.apiKey,
    this.description,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String apiKey;
  final String? description;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<String> run(PipelineContext context) async {
    final filePath = context.buildArtifact.path;
    // ... rest unchanged ...
```

- [ ] **Step 2: Update the test**

In `test/actions/pgyer_upload_action_test.dart`:
- Remove `artifact: File('test.apk')` from all `PgyerUploadAction` constructors
- Set `context.setBuildArtifact(File('test.apk'))` before calling `action.run(context)`
- In the `stub` call, update the expected curl command (the `file=@test.apk` part stays the same since it reads from context)

Key changes — update the helper and test bodies:

```dart
  PipelineContext ctx() {
    final c = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 1000,
      platforms: {AppPlatform.android},
    );
    c.setBuildArtifact(File('test.apk'));
    return c;
  }
```

Remove `artifact:` from all `PgyerUploadAction(...)` constructors.

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/pgyer_upload_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/pgyer_upload_action.dart test/actions/pgyer_upload_action_test.dart
git commit -m "refactor: PgyerUploadAction reads artifact from context"
```

---

### Task 5: Update PgyerUploadV2Action — read artifact from context

**Files:**
- Modify: `lib/src/actions/pgyer_upload_v2_action.dart`
- Modify: `test/actions/pgyer_upload_v2_action_test.dart`

- [ ] **Step 1: Update PgyerUploadV2Action**

In `lib/src/actions/pgyer_upload_v2_action.dart`:
- Remove `required this.artifact` from constructor
- Remove `final File artifact;` field
- In `run()`, get artifact from context at the start: `final artifact = context.buildArtifact;`
- Update all internal references from `artifact` to use the local variable

Updated constructor and field section:

```dart
class PgyerUploadV2Action extends PipelineAction<String> {
  PgyerUploadV2Action({
    required this.apiKey,
    this.description,
    List<String>? apiDomains,
    Future<bool> Function(String domain)? probeDomain,
    ShellRunner? shellRunner,
  })  : apiDomains = apiDomains ?? _defaultApiDomains,
        _probeDomain = probeDomain ?? _defaultProbeDomain,
        _shellRunner = shellRunner ?? DefaultShellRunner();

  final String apiKey;
  final String? description;
  final List<String> apiDomains;
  final Future<bool> Function(String domain) _probeDomain;
  final ShellRunner _shellRunner;
```

In `run()`, add at the top:

```dart
  @override
  Future<String> run(PipelineContext context) async {
    final artifact = context.buildArtifact;
    final domain = await _selectReachableDomain();
    // ... rest uses `artifact` local variable ...
```

Also update `_getCOSToken` and `_uploadToCOS` to accept `File artifact` as a parameter, or make them use the local `artifact` from `run()`. The cleanest approach: pass `artifact` to the private methods.

Updated private method signatures:

```dart
  Future<_CosToken> _getCOSToken(String apiBaseUrl, File artifact) async { ... }
  Future<void> _uploadToCOS(_CosToken token, File artifact) async { ... }
```

And in `run()`:

```dart
    final token = await _getCOSToken(apiBaseUrl, artifact);
    await _uploadToCOS(token, artifact);
```

- [ ] **Step 2: Update the test**

In `test/actions/pgyer_upload_v2_action_test.dart`:
- Update `ctx()` to set buildArtifact:

```dart
  PipelineContext ctx() {
    final c = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 1000,
      platforms: {AppPlatform.android},
    );
    return c;
  }
```

- In each test that creates a temp file and an action, set `ctx().setBuildArtifact(apk)` before calling `action.run(ctx())`. Since ctx() creates a new context each time, you need to create the context, set the artifact, then run.

Pattern for tests that use a temp file:

```dart
    final tmp = Directory.systemTemp.createTempSync();
    final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
    try {
      final context = ctx()..setBuildArtifact(apk);
      final action = PgyerUploadV2Action(
        apiKey: 'k',
        probeDomain: (d) async => d == 'api.pgyer.com',
        shellRunner: shell,
      );
      final url = await action.run(context);
      expect(url, 'https://pgyer.com/abcd');
    } finally {
      tmp.deleteSync(recursive: true);
    }
```

- Remove `artifact:` from all `PgyerUploadV2Action(...)` constructors.

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/pgyer_upload_v2_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/pgyer_upload_v2_action.dart test/actions/pgyer_upload_v2_action_test.dart
git commit -m "refactor: PgyerUploadV2Action reads artifact from context"
```

---

### Task 6: Update GooglePlayUploadAction — read artifact from context

**Files:**
- Modify: `lib/src/actions/google_play_action.dart`
- Modify: `test/actions/google_play_action_test.dart`

- [ ] **Step 1: Update GooglePlayUploadAction**

In `lib/src/actions/google_play_action.dart`:
- Remove `required this.artifact` from constructor
- Remove `final File artifact;` field
- In `run()`, replace `artifact.path` with `context.buildArtifact.path`

Updated class:

```dart
/// Uploads an AAB file to Google Play via Fastlane Supply.
///
/// Reads `context.buildArtifact` — requires `BuildAndroidAction`
/// earlier in the pipeline body.
class GooglePlayUploadAction extends PipelineAction<void> {
  GooglePlayUploadAction({
    required this.packageName,
    required this.jsonKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String packageName;
  final String jsonKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Google Play';

  @override
  Future<void> run(PipelineContext context) async {
    final artifact = context.buildArtifact;
    Logger.info('AAB: ${artifact.path}');
    // ... rest uses artifact local variable ...
```

- [ ] **Step 2: Update the test**

In `test/actions/google_play_action_test.dart`:
- Remove `artifact:` from constructors
- Create context with buildArtifact set

```dart
  PipelineContext ctx() {
    final c = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 1000,
      platforms: {AppPlatform.android},
    );
    c.setBuildArtifact(File('build/app-release.aab'));
    return c;
  }
```

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/google_play_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/google_play_action.dart test/actions/google_play_action_test.dart
git commit -m "refactor: GooglePlayUploadAction reads artifact from context"
```

---

### Task 7: Update AppStoreUploadAction — read artifact from context

**Files:**
- Modify: `lib/src/actions/app_store_action.dart`
- Modify: `test/actions/app_store_action_test.dart`

- [ ] **Step 1: Update AppStoreUploadAction**

In `lib/src/actions/app_store_action.dart`:
- Remove `required this.artifact` from constructor
- Remove `final File artifact;` field
- In `run()`, add `final artifact = context.buildArtifact;` at the top

Updated class:

```dart
/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
///
/// Reads `context.buildArtifact` — requires `BuildIOSAction`
/// earlier in the pipeline body.
class AppStoreUploadAction extends PipelineAction<void> {
  AppStoreUploadAction({
    required this.issuerId,
    required this.apiKeyId,
    required this.apiKeyPath,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String issuerId;
  final String apiKeyId;
  final String apiKeyPath;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    final artifact = context.buildArtifact;
    Logger.info('IPA: ${artifact.path}');
    // ... rest unchanged, uses `artifact` local variable ...
```

- [ ] **Step 2: Update the test**

In `test/actions/app_store_action_test.dart`:
- Remove `artifact:` from constructors
- Create context with buildArtifact set

```dart
  PipelineContext ctx({File? artifact}) {
    final c = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 1000,
      platforms: {AppPlatform.ios},
    );
    c.setBuildArtifact(artifact ?? File('build/ios/ipa/app.ipa'));
    return c;
  }
```

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/app_store_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/app_store_action.dart test/actions/app_store_action_test.dart
git commit -m "refactor: AppStoreUploadAction reads artifact from context"
```

---

### Task 8: Rename Default* classes to *Impl

**Files:**
- Modify: `lib/src/utils/default_shell_runner.dart` → rename to `lib/src/utils/shell_runner_impl.dart`
- Modify: `lib/src/utils/git_manager.dart` — extract `DefaultGitManager` to `lib/src/utils/git_manager_impl.dart`
- Modify: `lib/src/utils/version_manager.dart` — extract `DefaultVersionManager` to `lib/src/utils/version_manager_impl.dart`
- Modify: `lib/flutter_ci_tools.dart` — update exports

- [ ] **Step 1: Rename DefaultShellRunner to ShellRunnerImpl**

Rename file:
```bash
git mv lib/src/utils/default_shell_runner.dart lib/src/utils/shell_runner_impl.dart
```

In the renamed file, change:
- `class DefaultShellRunner implements ShellRunner` → `class ShellRunnerImpl implements ShellRunner`
- Add dartdoc comment

- [ ] **Step 2: Update all imports of default_shell_runner.dart**

Find all files that import `default_shell_runner.dart`:
```bash
grep -r "default_shell_runner" lib/ test/ example/
```

Update each import from `../utils/default_shell_runner.dart` (or similar) to `../utils/shell_runner_impl.dart`.

Files to update (based on current codebase):
- `lib/src/actions/build_android_action.dart`
- `lib/src/actions/build_ios_action.dart`
- `lib/src/actions/pgyer_upload_action.dart`
- `lib/src/actions/pgyer_upload_v2_action.dart`
- `lib/src/actions/google_play_action.dart`
- `lib/src/actions/app_store_action.dart`
- `lib/src/actions/feishu_build_notify_action.dart`
- `lib/src/actions/feishu_notify_action.dart`
- `lib/src/utils/git_manager.dart`
- `lib/src/utils/version_manager.dart`
- `lib/src/pipeline.dart` (if applicable)

Also replace all usages of `DefaultShellRunner()` with `ShellRunnerImpl()`.

- [ ] **Step 3: Extract DefaultGitManager to git_manager_impl.dart**

Create `lib/src/utils/git_manager_impl.dart` with the `DefaultGitManager` class (renamed to `GitManagerImpl`). Move the class from `git_manager.dart`.

Update `lib/src/utils/git_manager.dart` to only contain the abstract `GitManager` class.

- [ ] **Step 4: Extract DefaultVersionManager to version_manager_impl.dart**

Create `lib/src/utils/version_manager_impl.dart` with the `DefaultVersionManager` class (renamed to `VersionManagerImpl`). Move the class from `version_manager.dart`.

Update `lib/src/utils/version_manager.dart` to only contain the abstract `VersionManager` class.

- [ ] **Step 5: Update barrel exports**

Update `lib/flutter_ci_tools.dart`:

```dart
// Replace
export 'src/utils/default_shell_runner.dart';
// With
export 'src/utils/shell_runner_impl.dart';

// Add new exports for split files
export 'src/utils/git_manager_impl.dart';
export 'src/utils/version_manager_impl.dart';
```

- [ ] **Step 6: Update all imports and usages of DefaultGitManager and DefaultVersionManager**

Search and replace:
- `DefaultGitManager` → `GitManagerImpl`
- `DefaultVersionManager` → `VersionManagerImpl`
- Update import paths for the new files

- [ ] **Step 7: Run full test suite**

Run: `dart test`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: rename Default* utility classes to *Impl"
```

---

### Task 9: Update example app

**Files:**
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`
- Modify: `example/ci/pipelines/android_test_pipeline.dart`

- [ ] **Step 1: Update test_pipeline.dart**

Changes:
- Remove `final apk = await runAction(BuildAndroidAction(...))` → `await runAction(BuildAndroidAction(...))`
- Remove `final ipa = await runAction(BuildIOSAction(...))` → `await runAction(BuildIOSAction(...))`
- Remove `artifact: apk` / `artifact: ipa` from upload action constructors
- `_deployToPgyer` no longer needs the `File artifact` parameter — remove it, upload reads from context

Updated `_deployToPgyer`:

```dart
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
```

Updated `body()` calls:

```dart
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
```

- [ ] **Step 2: Update prod_pipeline.dart**

Changes:
- Remove `final aab = await runAction(...)` → `await runAction(...)`
- Remove `final ipa = await runAction(...)` → `await runAction(...)`
- Remove `artifact: aab` from `GooglePlayUploadAction`
- Remove `artifact: ipa` from `AppStoreUploadAction`

- [ ] **Step 3: Update android_test_pipeline.dart**

Changes:
- Remove `final apk = await runAction(...)` → `await runAction(...)`
- Remove `artifact: apk` from `PgyerUploadAction`

- [ ] **Step 4: Run dart analyze on example**

Run: `dart analyze example/`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add example/
git commit -m "refactor: update example app for new data flow API"
```

---

### Task 10: Update remaining tests that assign buildNumber directly

**Files:**
- Any test file using `context..buildNumber = X` or `context.buildNumber = X`

- [ ] **Step 1: Find all tests that directly assign buildNumber**

Run:
```bash
grep -rn "buildNumber =" test/
```

- [ ] **Step 2: Replace each `context..buildNumber = X` with `context..resolveBuildVersion(X)`**

Common pattern:
```dart
// Before
context..buildNumber = 12001;
// After
context..resolveBuildVersion(12001);
```

- [ ] **Step 3: Run full test suite**

Run: `dart test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/
git commit -m "refactor: update tests to use resolveBuildVersion"
```

---

### Task 11: Run dart analyze and fix any remaining issues

**Files:**
- Various

- [ ] **Step 1: Run dart analyze**

Run: `dart analyze`
Expected: No errors or warnings.

- [ ] **Step 2: Fix any issues found**

- [ ] **Step 3: Run full test suite**

Run: `dart test`
Expected: All tests pass.

- [ ] **Step 4: Commit if any fixes needed**

```bash
git add -A
git commit -m "fix: resolve remaining analysis issues after refactoring"
```

---

### Task 12: Add dartdoc comments to public API

**Files:**
- `lib/src/actions/pipeline_action.dart`
- `lib/src/pipeline.dart`
- `lib/src/pipeline_registry.dart`
- `lib/src/build_metadata.dart`
- `lib/src/utils/shell_runner.dart`
- `lib/src/utils/git_manager.dart`
- `lib/src/utils/version_manager.dart`
- `lib/src/utils/logger.dart`
- `lib/src/utils/exceptions.dart`
- All 15 action files in `lib/src/actions/`

- [ ] **Step 1: Add dartdoc to core abstractions**

Add dartdoc to `PipelineAction`, `BuildPipeline`, `PipelineContext`, `PipelineRegistry`, `BuildMetadata`.

- [ ] **Step 2: Add dartdoc to all Action classes**

Ensure each action class has a doc comment explaining:
- What it does
- What it reads from context
- What it writes to context (if anything)
- Constructor parameter descriptions

- [ ] **Step 3: Add dartdoc to Utils interfaces**

Add dartdoc to `ShellRunner`, `GitManager`, `VersionManager`, `Logger`, and exception classes.

- [ ] **Step 4: Run dart doc to verify**

Run: `dart doc`
Expected: No undocumented public API warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/
git commit -m "docs: add dartdoc comments to public API"
```

---

### Task 13: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add new version entry**

Add a `## 0.2.0` entry above the existing `## 0.1.0`:

```markdown
## 0.2.0

### Breaking Changes

- `PipelineContext.buildNumber` is no longer a `late int` field. Use `resolveBuildVersion()` to set it; accessing before resolution throws `StateError` with a descriptive message.
- `BuildAndroidAction` and `BuildIOSAction` now return `void` instead of `File`. The build artifact is stored in `context.buildArtifact`.
- `PgyerUploadAction`, `PgyerUploadV2Action`, `GooglePlayUploadAction`, and `AppStoreUploadAction` no longer accept an `artifact` constructor parameter. They read from `context.buildArtifact` instead.
- `DefaultShellRunner` renamed to `ShellRunnerImpl`.
- `DefaultGitManager` renamed to `GitManagerImpl`.
- `DefaultVersionManager` renamed to `VersionManagerImpl`.

### Added

- `PipelineContext.buildArtifact` / `setBuildArtifact()` for passing build artifacts between actions.
- `BuildVersion` sealed type for type-safe build number state tracking.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG for 0.2.0"
```
