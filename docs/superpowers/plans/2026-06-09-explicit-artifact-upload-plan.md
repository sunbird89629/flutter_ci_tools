# Explicit Artifact Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement explicit artifact passing for upload actions, parallel execution support, and multiple download URLs in Feishu notifications.

**Architecture:**
- Build actions return File while still writing to context (backward compatible)
- Upload actions accept optional File? artifact parameter
- BuildPipeline gets runParallel() method
- FeishuBuildNotifyAction accepts List<String>? downloadUrls

**Tech Stack:** Dart, flutter_ci_tools

---

## File Structure

**Modified:**
- `lib/src/pipeline.dart` - Add runParallel() and _runTracked()
- `lib/src/actions/build_android_action.dart` - Return File instead of void
- `lib/src/actions/build_ios_action.dart` - Return File instead of void
- `lib/src/actions/pgyer_upload_action.dart` - Add optional artifact param
- `lib/src/actions/pgyer_upload_v2_action.dart` - Add optional artifact param
- `lib/src/actions/feishu_build_notify_action.dart` - Add optional downloadUrls param

**New Tests:**
- `test/pipeline_parallel_test.dart` - Test runParallel()
- Plus update existing test files

---

### Task 1: Refactor BuildPipeline - extract _runTracked() and add runParallel()

**Files:**
- Modify: `lib/src/pipeline.dart`
- Test: `test/pipeline_test.dart` (update) + `test/pipeline_parallel_test.dart` (new)

- [ ] **Step 1: Read the current pipeline.dart to understand existing code**

(Already have context - current runAction has tracking logic inline)

- [ ] **Step 2: Extract _runTracked() from runAction()**

Modify `lib/src/pipeline.dart`:

```dart
abstract class BuildPipeline {
  // ... existing fields and methods ...

  /// 串行执行（现有，重构后）。
  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    return _runTracked(action);
  }

  /// 并行执行多个 action，全部完成后返回；任一失败时其余仍跑完，
  /// 失败状态各自记录（沿用 _printSummary 的逐条展示）。
  /// 返回 List<R>，按输入顺序对应每个 action 的结果。
  Future<List<R>> runParallel<R>(List<PipelineAction<R>> actions) async {
    executedActions.addAll(actions);
    return Future.wait(actions.map(_runTracked));
  }

  /// 抽出的单 action 追踪逻辑（计时 + 状态 + 错误）。
  Future<R> _runTracked<R>(PipelineAction<R> action) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await runStep(action.name, () => action.run(context));
      stopwatch.stop();
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
      return result;
    } catch (e, st) {
      stopwatch.stop();
      action
        ..status = ActionStatus.failed
        ..duration = stopwatch.elapsed
        ..error = e
        ..stackTrace = st;
      rethrow;
    }
  }

  // ... rest of BuildPipeline ...
}
```

- [ ] **Step 3: Run existing tests to ensure refactor didn't break anything**

Run: `dart test test/pipeline_test.dart -v`
Expected: All tests pass

- [ ] **Step 4: Write test for runParallel() (failing first)**

Create `test/pipeline_parallel_test.dart`:

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _TestAction extends PipelineAction<int> {
  _TestAction(this.value, {this.delay = Duration.zero});

  final int value;
  final Duration delay;

  @override
  Future<int> run(PipelineContext context) async {
    await Future.delayed(delay);
    return value;
  }
}

class _TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      PipelineContext(appName: 'test', seedBuildNumber: 1, rawArgs: args);

  @override
  String get help => 'test';

  Future<List<int>> runIt() async {
    await run([]);
    return [];
  }
}

void main() {
  group('BuildPipeline runParallel', () {
    test('runs multiple actions in parallel and returns results in order', () async {
      final pipeline = _TestPipeline();
      await pipeline.run([]);

      final results = await pipeline.runParallel([
        _TestAction(1, delay: const Duration(milliseconds: 50)),
        _TestAction(2, delay: const Duration(milliseconds: 10)),
        _TestAction(3, delay: const Duration(milliseconds: 30)),
      ]);

      expect(results, [1, 2, 3]);
      expect(pipeline.executedActions.length, 3);
      expect(pipeline.allSucceeded, isTrue);
    });

    test('tracks status and duration for parallel actions', () async {
      final pipeline = _TestPipeline();
      await pipeline.run([]);

      await pipeline.runParallel([
        _TestAction(1),
        _TestAction(2),
      ]);

      for (final action in pipeline.executedActions) {
        expect(action.status, ActionStatus.success);
        expect(action.duration, isNotNull);
      }
    });

    test('one action fails - others still complete and get recorded', () async {
      class _FailingAction extends PipelineAction<void> {
        @override
        Future<void> run(PipelineContext context) async {
          throw StateError('oops');
        }
      }

      final pipeline = _TestPipeline();
      await pipeline.run([]);

      Object? caughtError;
      try {
        await pipeline.runParallel([
          _TestAction(1),
          _FailingAction(),
          _TestAction(3),
        ]);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isStateError);
      expect(pipeline.executedActions.length, 3);
      expect(pipeline.executedActions[0].status, ActionStatus.success);
      expect(pipeline.executedActions[1].status, ActionStatus.failed);
      expect(pipeline.executedActions[2].status, ActionStatus.success);
      expect(pipeline.lastFailure, isNotNull);
    });
  });
}
```

- [ ] **Step 5: Run the new test - it should pass**

Run: `dart test test/pipeline_parallel_test.dart -v`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/src/pipeline.dart test/pipeline_parallel_test.dart
git commit -m "refactor: extract _runTracked and add runParallel"
```

---

### Task 2: Update BuildAndroidAction to return File

**Files:**
- Modify: `lib/src/actions/build_android_action.dart`
- Test: `test/actions/build_android_action_test.dart`

- [ ] **Step 1: Read current build_android_action.dart**

(Already have context)

- [ ] **Step 2: Modify BuildAndroidAction to return File**

```dart
import 'dart:io';

import '../pipeline_context.dart';
import '../utils/shell_runner_impl.dart';
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
class BuildAndroidAction extends PipelineAction<File> {
  /// Creates an Android build action.
  ///
  /// [envName] is the `--dart-define=ENV` value (e.g. `"prod"`, `"staging"`).
  /// [buildType] selects APK or AAB output.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  BuildAndroidAction({
    required this.envName,
    required this.buildType,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// The `--dart-define=ENV` value passed to the Flutter build.
  final String envName;

  /// Whether to build an APK or an AAB.
  final AndroidBuildType buildType;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Build Android';

  @override
  Future<File> run(PipelineContext context) async {
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
    final file = File(outputPath);
    context.setBuildArtifact(file);
    return file;
  }
}
```

- [ ] **Step 3: Update the test**

Modify `test/actions/build_android_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

import '../utils/fake_shell_runner.dart';

void main() {
  group('BuildAndroidAction', () {
    test('runs flutter build apk with correct args', () async {
      final shell = FakeShellRunner();
      final context = PipelineContext(
        appName: 'test',
        seedBuildNumber: 123,
        rawArgs: const [],
      );
      context.resolveBuildVersion(123);

      final action = BuildAndroidAction(
        envName: 'test',
        buildType: AndroidBuildType.apk,
        shellRunner: shell,
      );
      final result = await action.run(context);

      expect(shell.calls, hasLength(1));
      expect(shell.calls.first.command, 'fvm');
      expect(shell.calls.first.args, [
        'flutter',
        'build',
        'apk',
        '--build-name=1.2.3',
        '--build-number=123',
        '--dart-define=ENV=test',
      ]);
      expect(result.path, endsWith('app-release.apk'));
      expect(context.buildArtifact.path, endsWith('app-release.apk'));
    });

    test('runs flutter build appbundle with correct args', () async {
      final shell = FakeShellRunner();
      final context = PipelineContext(
        appName: 'test',
        seedBuildNumber: 123,
        rawArgs: const [],
      );
      context.resolveBuildVersion(123);

      final action = BuildAndroidAction(
        envName: 'prod',
        buildType: AndroidBuildType.appbundle,
        shellRunner: shell,
      );
      final result = await action.run(context);

      expect(shell.calls.first.args[2], 'appbundle');
      expect(result.path, endsWith('app-release.aab'));
      expect(context.buildArtifact.path, endsWith('app-release.aab'));
    });
  });
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/actions/build_android_action_test.dart -v`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/build_android_action.dart test/actions/build_android_action_test.dart
git commit -m "refactor: BuildAndroidAction returns File (backward compatible)"
```

---

### Task 3: Update BuildIOSAction to return File

**Files:**
- Modify: `lib/src/actions/build_ios_action.dart`
- Test: `test/actions/build_ios_action_test.dart`

- [ ] **Step 1: Modify BuildIOSAction to return File**

```dart
import 'dart:io';

import '../pipeline_context.dart';
import '../utils/shell_runner_impl.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Builds an iOS IPA and stores it in context.
///
/// Reads `context.buildName` and `context.buildNumber` — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
///
/// After completion, the output file is available via `context.buildArtifact`.
class BuildIOSAction extends PipelineAction<File> {
  /// Creates an iOS build action.
  ///
  /// [envName] is the `--dart-define=ENV` value (e.g. `"prod"`, `"staging"`).
  /// [exportMethod] is the Xcode export method (e.g. `"ad-hoc"`, `"app-store"`).
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  BuildIOSAction({
    required this.envName,
    required this.exportMethod,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// The `--dart-define=ENV` value passed to the Flutter build.
  final String envName;

  /// Xcode export method (e.g. `"ad-hoc"`, `"app-store"`, `"development"`).
  final String exportMethod;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Build iOS';

  @override
  Future<File> run(PipelineContext context) async {
    await _shellRunner.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$exportMethod',
      '--build-name=${context.buildName}',
      '--build-number=${context.buildNumber}',
      '--dart-define=ENV=$envName',
    ]);
    final file = _findIpa();
    context.setBuildArtifact(file);
    return file;
  }

  File _findIpa() {
    final ipaDir = Directory('build/ios/ipa');
    if (!ipaDir.existsSync()) {
      throw StateError(
        'IPA build failed: Directory not found at ${ipaDir.path}',
      );
    }
    final ipaList =
        ipaDir.listSync().where((e) => e.path.endsWith('.ipa')).toList();
    if (ipaList.isEmpty) {
      throw StateError(
        'IPA build failed: No .ipa file found in ${ipaDir.path}',
      );
    }
    return ipaList.first as File;
  }
}
```

- [ ] **Step 2: Update the test**

Modify `test/actions/build_ios_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

import '../utils/fake_shell_runner.dart';

void main() {
  group('BuildIOSAction', () {
    test('runs flutter build ipa with correct args', () async {
      final shell = FakeShellRunner();
      final context = PipelineContext(
        appName: 'test',
        seedBuildNumber: 123,
        rawArgs: const [],
      );
      context.resolveBuildVersion(123);

      // Create a fake IPA file for _findIpa
      final ipaDir = Directory('build/ios/ipa');
      await ipaDir.create(recursive: true);
      final fakeIpa = File('${ipaDir.path}/test.ipa');
      await fakeIpa.writeAsString('fake');

      final action = BuildIOSAction(
        envName: 'test',
        exportMethod: 'development',
        shellRunner: shell,
      );
      final result = await action.run(context);

      expect(shell.calls, hasLength(1));
      expect(shell.calls.first.command, 'fvm');
      expect(shell.calls.first.args, [
        'flutter',
        'build',
        'ipa',
        '--export-method=development',
        '--build-name=1.2.3',
        '--build-number=123',
        '--dart-define=ENV=test',
      ]);
      expect(result.path, endsWith('test.ipa'));
      expect(context.buildArtifact.path, endsWith('test.ipa'));

      // Cleanup
      await ipaDir.delete(recursive: true);
    });
  });
}
```

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/build_ios_action_test.dart -v`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/build_ios_action.dart test/actions/build_ios_action_test.dart
git commit -m "refactor: BuildIOSAction returns File (backward compatible)"
```

---

### Task 4: Update PgyerUploadAction to support explicit artifact

**Files:**
- Modify: `lib/src/actions/pgyer_upload_action.dart`
- Test: `test/actions/pgyer_upload_action_test.dart`

- [ ] **Step 1: Modify PgyerUploadAction**

```dart
import 'dart:convert';
import 'dart:io';

import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads the build artifact from [PipelineContext.buildArtifact] to Pgyer
/// and returns the download URL.
class PgyerUploadAction extends PipelineAction<String> {
  /// Creates a Pgyer upload action.
  ///
  /// [apiKey] is the Pgyer API key for authentication.
  /// [description] is an optional build description shown on Pgyer.
  /// [artifact] optionally specifies the file to upload; if null, uses context.buildArtifact.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  PgyerUploadAction({
    required this.apiKey,
    this.description,
    this.artifact,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Pgyer API key for authentication.
  final String apiKey;

  /// Optional build description shown on the Pgyer download page.
  final String? description;

  /// Optional explicit file to upload; uses context.buildArtifact if null.
  final File? artifact;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<String> run(PipelineContext context) async {
    final file = artifact ?? context.buildArtifact;
    Logger.info('Uploading ${file.path} ...');
    const maxAttempts = 3;
    ShellResult? result;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        Logger.info('Retrying upload (attempt $attempt/$maxAttempts)...');
        await Future.delayed(const Duration(seconds: 5));
      }
      result = await _shellRunner.runAndCapture('curl', [
        '--http1.1',
        '-F',
        'file=@${file.path}',
        '-F',
        '_api_key=$apiKey',
        if (description != null) ...[
          '-F',
          'buildUpdateDescription=$description',
        ],
        'https://api.xcxwo.com/apiv2/app/upload',
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

- [ ] **Step 2: Update the test - add test for explicit artifact**

Add to `test/actions/pgyer_upload_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

import '../utils/fake_shell_runner.dart';

void main() {
  group('PgyerUploadAction', () {
    test('uploads from context.buildArtifact (default behavior)', () async {
      // ... existing test ...
    });

    test('uploads explicit artifact when provided', () async {
      final shell = FakeShellRunner()
        ..nextResult = ShellResult(0, '''
          {
            "code": 0,
            "data": {
              "buildKey": "abc123"
            }
          }
        ''', '');

      final tempDir = Directory.systemTemp.createTempSync();
      final testFile = File('${tempDir.path}/test.apk')
        ..writeAsStringSync('test');

      final context = PipelineContext(
        appName: 'test',
        seedBuildNumber: 123,
        rawArgs: const [],
      );
      // Do NOT set context.buildArtifact - we're passing explicitly

      final action = PgyerUploadAction(
        apiKey: 'test-key',
        artifact: testFile,
        shellRunner: shell,
      );
      final result = await action.run(context);

      expect(result, 'https://www.pgyer.com/abc123');
      expect(shell.calls, hasLength(1));
      expect(shell.calls.first.args, hasLength(7));
      expect(shell.calls.first.args[4], endsWith('test.apk'));

      tempDir.deleteSync(recursive: true);
    });
  });
}
```

(Keep the existing test, just add the new one)

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/pgyer_upload_action_test.dart -v`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/pgyer_upload_action.dart test/actions/pgyer_upload_action_test.dart
git commit -m "feat: PgyerUploadAction supports explicit artifact parameter"
```

---

### Task 5: Update PgyerUploadV2Action to support explicit artifact

**Files:**
- Modify: `lib/src/actions/pgyer_upload_v2_action.dart`
- Test: `test/actions/pgyer_upload_v2_action_test.dart`

- [ ] **Step 1: Modify PgyerUploadV2Action**

```dart
import 'dart:convert';
import 'dart:io';

import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Pgyer's official 3-step "fastUploadApp" upload protocol.
///
/// In contrast to [PgyerUploadAction] (the legacy single-shot endpoint),
/// this action:
/// 1. Probes a list of API domains and picks the first reachable one
///    (resilient to regional DNS / firewall issues in mainland China).
/// 2. Requests a Tencent COS upload token from Pgyer.
/// 3. Uploads the artifact directly to COS (bypassing Pgyer's own servers
///    — much faster for large files).
/// 4. Polls `buildInfo` until processing completes and returns the build's
///    public download URL.
///
/// The artifact file is read from [PipelineContext.buildArtifact] by default,
/// or from the explicit [artifact] parameter if provided.
///
/// Returns the download URL (e.g. `https://www.pgyer.com/abc123`).
class PgyerUploadV2Action extends PipelineAction<String> {
  /// Creates a Pgyer V2 upload action.
  ///
  /// [apiKey] is the Pgyer API key for authentication.
  /// [description] is an optional build description shown on Pgyer.
  /// [artifact] optionally specifies the file to upload; if null, uses context.buildArtifact.
  /// [apiDomains] overrides the default list of API hosts to probe.
  /// [probeDomain] overrides the default domain reachability check for testing.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  PgyerUploadV2Action({
    required this.apiKey,
    this.description,
    this.artifact,
    List<String>? apiDomains,
    Future<bool> Function(String domain)? probeDomain,
    ShellRunner? shellRunner,
  }) : apiDomains = apiDomains ?? _defaultApiDomains,
       _probeDomain = probeDomain ?? _defaultProbeDomain,
       _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Pgyer API key for authentication.
  final String apiKey;

  /// Optional build description shown on the Pgyer download page.
  final String? description;

  /// Optional explicit file to upload; uses context.buildArtifact if null.
  final File? artifact;

  /// Ordered list of API hosts to probe. First reachable one is used.
  final List<String> apiDomains;

  final Future<bool> Function(String domain) _probeDomain;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer (V2)';

  @override
  Future<String> run(PipelineContext context) async {
    final file = artifact ?? context.buildArtifact;
    final domain = await _selectReachableDomain();
    final apiBaseUrl = 'http://$domain/apiv2';
    final webDomain = domain.startsWith('api.') ? domain.substring(4) : domain;

    final token = await _getCOSToken(apiBaseUrl, file);
    await _uploadToCOS(token, file);
    final shortcutUrl = await _pollBuildInfo(apiBaseUrl, token.key);
    final downloadUrl = 'https://$webDomain/$shortcutUrl';
    Logger.success('Pgyer build ready: $downloadUrl');
    return downloadUrl;
  }

  Future<String> _selectReachableDomain() async {
    Logger.info('Probing Pgyer API domains...');
    for (final domain in apiDomains) {
      if (await _probeDomain(domain)) {
        Logger.info('Using domain $domain');
        return domain;
      }
    }
    throw DeployException(
      'All Pgyer API domains unreachable: ${apiDomains.join(', ')}',
    );
  }

  /// Default probe: HTTPS GET against `/apiv2/app/getCOSToken` with a
  /// 5-second connect timeout and 10-second overall timeout. Any HTTP
  /// response (even an error code) counts as reachable; network/timeout
  /// errors count as unreachable.
  static Future<bool> _defaultProbeDomain(String domain) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .getUrl(Uri.parse('https://$domain/apiv2/app/getCOSToken'))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<_CosToken> _getCOSToken(String apiBaseUrl, File file) async {
    Logger.info('Requesting COS upload token...');
    final buildType = file.path.split('.').last;
    final result = await _shellRunner.runAndCapture('curl', [
      '-s',
      '--form-string',
      '_api_key=$apiKey',
      '--form-string',
      'buildType=$buildType',
      if (description != null) ...[
        '--form-string',
        'buildUpdateDescription=$description',
      ],
      '$apiBaseUrl/app/getCOSToken',
    ]);
    if (result.exitCode != 0) {
      throw DeployException('getCOSToken curl failed: ${result.stderr}');
    }
    final dynamic response;
    try {
      response = jsonDecode(result.stdout);
    } catch (_) {
      throw DeployException('getCOSToken returned non-JSON: ${result.stdout}');
    }
    if (response['code'] != 0) {
      throw DeployException(
        'getCOSToken failed: ${response['message'] ?? response}',
      );
    }
    final data = response['data'] as Map<String, dynamic>?;
    final endpoint = data?['endpoint'] as String?;
    final key = data?['key'] as String?;
    final signature = data?['signature'] as String?;
    final securityToken = data?['x-cos-security-token'] as String?;
    if (endpoint == null ||
        key == null ||
        signature == null ||
        securityToken == null) {
      throw DeployException(
        'getCOSToken response missing required fields: ${result.stdout}',
      );
    }
    return _CosToken(
      endpoint: endpoint,
      key: key,
      signature: signature,
      securityToken: securityToken,
    );
  }

  Future<void> _uploadToCOS(_CosToken token, File file) async {
    final fileName = file.path.split('/').last;
    final size = file.lengthSync();
    Logger.info('Uploading $fileName ($size bytes) to COS...');
    final result = await _shellRunner.runAndCapture('curl', [
      '-o',
      '/dev/null',
      '-w',
      '%{http_code}',
      '-s',
      '--connect-timeout',
      '30',
      '--max-time',
      '1800',
      '--form-string',
      'key=${token.key}',
      '--form-string',
      'signature=${token.signature}',
      '--form-string',
      'x-cos-security-token=${token.securityToken}',
      '--form-string',
      'x-cos-meta-file-name=$fileName',
      '-F',
      'file=@${file.path}',
      token.endpoint,
    ]);
    if (result.exitCode != 0) {
      throw DeployException('COS upload curl failed: ${result.stderr}');
    }
    final httpCode = result.stdout.trim();
    if (httpCode != '204') {
      throw DeployException(
          'COS upload returned HTTP $httpCode (expected 204)');
    }
    Logger.success('Uploaded to COS.');
  }

  Future<String> _pollBuildInfo(String apiBaseUrl, String key) async {
    Logger.info('Waiting for Pgyer to process the build...');
    const maxAttempts = 60;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = await _shellRunner.runAndCapture('curl', [
        '-s',
        '$apiBaseUrl/app/buildInfo?_api_key=$apiKey&buildKey=$key',
      ]);
      if (result.exitCode == 0) {
        try {
          final response = jsonDecode(result.stdout);
          if (response['code'] == 0) {
            final data = response['data'] as Map<String, dynamic>?;
            final shortcutUrl = data?['buildShortcutUrl'] as String?;
            if (shortcutUrl == null) {
              throw DeployException(
                'buildInfo missing buildShortcutUrl: ${result.stdout}',
              );
            }
            return shortcutUrl;
          }
        } catch (e) {
          if (e is DeployException) rethrow;
          // Treat JSON parse failures as transient and keep polling.
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    throw DeployException(
        'Pgyer build processing timed out after ${maxAttempts}s');
  }
}

const _defaultApiDomains = [
  'api.pgyer.com',
  'api.xcxwo.com',
  'api.pgyeraapp.com',
];

class _CosToken {
  _CosToken({
    required this.endpoint,
    required this.key,
    required this.signature,
    required this.securityToken,
  });

  final String endpoint;
  final String key;
  final String signature;
  final String securityToken;
}
```

- [ ] **Step 2: Update the test - add test for explicit artifact**

Add to `test/actions/pgyer_upload_v2_action_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

import '../utils/fake_shell_runner.dart';

void main() {
  group('PgyerUploadV2Action', () {
    // ... existing tests ...

    test('uploads explicit artifact when provided', () async {
      final shell = FakeShellRunner();
      var callIndex = 0;
      shell.nextResults = [
        // getCOSToken
        ShellResult(0, '''
          {
            "code": 0,
            "data": {
              "endpoint": "https://cos.example.com",
              "key": "test-key",
              "signature": "test-sig",
              "x-cos-security-token": "test-token"
            }
          }
        ''', ''),
        // upload to COS (returns 204)
        ShellResult(0, '204', ''),
        // poll buildInfo
        ShellResult(0, '''
          {
            "code": 0,
            "data": {
              "buildShortcutUrl": "abc123"
            }
          }
        ''', ''),
      ];

      final tempDir = Directory.systemTemp.createTempSync();
      final testFile = File('${tempDir.path}/test.apk')
        ..writeAsStringSync('test');

      final context = PipelineContext(
        appName: 'test',
        seedBuildNumber: 123,
        rawArgs: const [],
      );

      final action = PgyerUploadV2Action(
        apiKey: 'test-key',
        artifact: testFile,
        probeDomain: (_) async => true,
        shellRunner: shell,
      );
      final result = await action.run(context);

      expect(result, 'https://www.pgyer.com/abc123');

      tempDir.deleteSync(recursive: true);
    });
  });
}
```

(Keep existing tests, just add the new one)

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/pgyer_upload_v2_action_test.dart -v`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/pgyer_upload_v2_action.dart test/actions/pgyer_upload_v2_action_test.dart
git commit -m "feat: PgyerUploadV2Action supports explicit artifact parameter"
```

---

### Task 6: Update FeishuBuildNotifyAction to support multiple downloadUrls

**Files:**
- Modify: `lib/src/actions/feishu_build_notify_action.dart`
- Test: `test/actions/feishu_build_notify_action_test.dart`

- [ ] **Step 1: Modify FeishuBuildNotifyAction**

Update to support `downloadUrls`:

```dart
import '../utils/shell_runner_impl.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'feishu_notify_action.dart';
import 'pipeline_action.dart';

/// Destination where a build artifact will be uploaded.
///
/// Used to label the standard Feishu build-notification message.
enum DeployTarget {
  /// Pgyer beta distribution platform.
  pgyer('Pgyer'),

  /// Google Play Store.
  googlePlay('Google Play'),

  /// Apple App Store.
  appStore('App Store');

  /// Human-readable deploy target name.
  final String label;
  const DeployTarget(this.label);
}

/// Sends the standard "new build" message to Feishu.
///
/// Reads `context.buildName`, `context.buildNumber`, and `context.git` to
/// format the message text. Requires `ResolveBuildVersionAction` earlier in
/// the pipeline body.
class FeishuBuildNotifyAction extends PipelineAction<void> {
  /// Creates a Feishu build notification action.
  ///
  /// [webhookUrl] is the Feishu bot webhook URL.
  /// [target] is the deploy destination (Pgyer, Google Play, etc.).
  /// [downloadUrl] is an optional single direct download link included in the message.
  /// [downloadUrls] is an optional list of download links included in the message.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.target,
    this.downloadUrl,
    this.downloadUrls,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Deploy destination label (Pgyer, Google Play, or App Store).
  final DeployTarget target;

  /// Optional single direct download link included in the notification message.
  final String? downloadUrl;

  /// Optional list of download links included in the notification message.
  final List<String>? downloadUrls;

  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final message = await _formatMessage(context);
    await FeishuNotifyAction(
      webhookUrl: webhookUrl,
      message: message,
      shellRunner: _shellRunner,
    ).run(context);
  }

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
    final urls = downloadUrls ?? (downloadUrl != null ? [downloadUrl!] : null);
    if (urls != null && urls.isNotEmpty) {
      lines.add(sep);
      if (urls.length == 1) {
        lines.add('🔗 下载: ${urls.single}');
      } else {
        lines.add('🔗 下载链接:');
        for (var i = 0; i < urls.length; i++) {
          lines.add('  ${i + 1}. ${urls[i]}');
        }
      }
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
}
```

- [ ] **Step 2: Update the test**

Read current test first, then add test for multiple URLs case.

Add to `test/actions/feishu_build_notify_action_test.dart`:

```dart
// (Keep existing tests, add new one)

test('formats message with multiple downloadUrls', () async {
  final shell = FakeShellRunner();
  final context = PipelineContext(
    appName: 'TestApp',
    seedBuildNumber: 123,
    rawArgs: const [],
    git: FakeGitManager(),
  );
  context.resolveBuildVersion(123);

  final action = FeishuBuildNotifyAction(
    webhookUrl: 'https://example.com/webhook',
    target: DeployTarget.pgyer,
    downloadUrls: [
      'https://www.pgyer.com/android123',
      'https://www.pgyer.com/ios456',
    ],
    shellRunner: shell,
  );

  await action.run(context);

  final message = shell.calls.first.args.first;
  expect(message, contains('🔗 下载链接:'));
  expect(message, contains('  1. https://www.pgyer.com/android123'));
  expect(message, contains('  2. https://www.pgyer.com/ios456'));
});
```

- [ ] **Step 3: Run tests**

Run: `dart test test/actions/feishu_build_notify_action_test.dart -v`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/feishu_build_notify_action.dart test/actions/feishu_build_notify_action_test.dart
git commit -m "feat: FeishuBuildNotifyAction supports multiple downloadUrls"
```

---

### Task 7: Update example/test_env_pipeline.dart to use the new features

**Files:**
- Modify: `example/ci/pipelines/test_env_pipeline.dart`

- [ ] **Step 1: Read current test_env_pipeline.dart**

(Check current implementation first)

- [ ] **Step 2: Update the pipeline to use parallel upload and multiple URLs**

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';

final String pgyerApiKey = '1540c89d7f12ade530a14ac4adf9caa2';
// MessageBus Bot Webhook
final String feishuWebhookUrl =
    'https://open.feishu.cn/open-apis/bot/v2/hook/82ab0b57-f8c9-493f-a69d-575271f12bfd';

class TestEnvPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      ExampleAppContext(args: args);

  @override
  String get description => '构建并部署到测试环境 (Pgyer)';
  @override
  String get help => '''
Test Pipeline
构建测试版本并上传到蒲公英。

Usage: dart run ci/build.dart test
同时构建 Android 和 iOS 两个平台，并行上传。
''';

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CheckGitStatusAction());
    await runAction(CleanProjectAction());

    // 构建，显式拿到两个文件
    final androidFile = await runAction(BuildAndroidAction(
      envName: 'test',
      buildType: AndroidBuildType.apk,
    ));
    final iosFile = await runAction(BuildIOSAction(
      envName: 'test',
      exportMethod: 'development',
    ));

    // 并行上传
    final urls = await runParallel([
      PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: androidFile),
      PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: iosFile),
    ]);

    // 一条通知包含两个链接
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrls: urls,
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

- [ ] **Step 3: Commit**

```bash
git add example/ci/pipelines/test_env_pipeline.dart
git commit -m "example: update TestEnvPipeline to use parallel upload"
```

---

### Task 8: Run all tests and do final verification

**Files:** (no changes)

- [ ] **Step 1: Run all tests**

Run: `dart test -v`
Expected: All tests pass

- [ ] **Step 2: Verify formatting**

Run: `dart format --set-exit-if-changed .`
Expected: No formatting issues (or fix and commit)

- [ ] **Step 3: Verify static analysis**

Run: `dart analyze`
Expected: No issues

- [ ] **Step 4: Commit if any fixes needed**

(Only if formatting/analysis fixes were needed)

---

## Plan Self-Review

- [x] Spec coverage: All spec requirements have corresponding tasks
- [x] Placeholder scan: No placeholders, all code and commands are complete
- [x] Type consistency: Type names, method signatures match the existing codebase
- [x] Backward compatibility: All changes maintain backward compatibility

## Final Checklist

- [ ] All tasks completed
- [ ] All tests pass
- [x] No placeholders in plan
- [x] Spec requirements all covered:
  - [x] Build actions return File
  - [x] Upload actions accept explicit File? artifact
  - [x] BuildPipeline has runParallel()
  - [x] FeishuBuildNotifyAction accepts List<String>? downloadUrls
  - [x] All backward compatible
