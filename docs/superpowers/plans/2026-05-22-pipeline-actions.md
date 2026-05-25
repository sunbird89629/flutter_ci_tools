# Pipeline Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fat DeployService interface with independent PipelineAction classes, each encapsulating one deploy/notification operation.

**Architecture:** PipelineAction is an abstract interface with `name` and `run(PipelineContext)`. Four concrete actions (PgyerUpload, FeishuNotify, GooglePlay, AppStore) copy logic from DefaultDeployService. Actions communicate through PipelineContext's key-value store. Subclasses manually call actions in their deploy methods.

**Tech Stack:** Dart 3.4+, `package:test`, zero external dependencies

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/src/actions/pipeline_action.dart` | Create | Abstract interface |
| `lib/src/actions/pgyer_upload_action.dart` | Create | Pgyer upload with retry |
| `lib/src/actions/feishu_notify_action.dart` | Create | Feishu webhook notification |
| `lib/src/actions/google_play_action.dart` | Create | Google Play via fastlane supply |
| `lib/src/actions/app_store_action.dart` | Create | App Store via fastlane pilot |
| `test/actions/pgyer_upload_action_test.dart` | Create | Pgyer action tests |
| `test/actions/feishu_notify_action_test.dart` | Create | Feishu action tests |
| `test/actions/google_play_action_test.dart` | Create | Google Play action tests |
| `test/actions/app_store_action_test.dart` | Create | App Store action tests |
| `lib/src/pipeline.dart` | Modify | Remove DeployService, keep buildFeishuMessage |
| `example/ci/pipelines/test_pipeline.dart` | Modify | Use actions |
| `example/ci/pipelines/prod_pipeline.dart` | Modify | Use actions |
| `example/ci/pipelines/android_test_pipeline.dart` | Modify | Use actions |
| `test/pipeline_test.dart` | Modify | Remove _FakeDeployService, update tests |
| `lib/src/deploy_service.dart` | Delete | Replaced by actions |
| `test/deploy_service_test.dart` | Delete | Replaced by action tests |
| `lib/flutter_ci_tools.dart` | Modify | Update exports |

---

### Task 1: Create PipelineAction interface

**Files:**
- Create: `lib/src/actions/pipeline_action.dart`
- Create: `test/actions/pipeline_action_test.dart`

- [ ] **Step 1: Create the actions directory**

```bash
mkdir -p lib/src/actions test/actions
```

- [ ] **Step 2: Write the interface**

```dart
// lib/src/actions/pipeline_action.dart
import '../pipeline_context.dart';

/// A single deploy/notification step in a pipeline.
///
/// Actions receive a [PipelineContext] and store results in its
/// key-value store for downstream actions to consume.
abstract class PipelineAction {
  /// Human-readable name for logging (e.g. "Upload to Pgyer").
  String get name;

  /// Executes this action using data from [context].
  ///
  /// Results should be stored via [PipelineContext.set] for downstream actions.
  Future<void> run(PipelineContext context);
}
```

- [ ] **Step 3: Write a basic test**

```dart
// test/actions/pipeline_action_test.dart
import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _TestAction extends PipelineAction {
  bool ran = false;
  PipelineContext? capturedContext;

  @override
  String get name => 'Test Action';

  @override
  Future<void> run(PipelineContext context) async {
    ran = true;
    capturedContext = context;
  }
}

void main() {
  test('PipelineAction run receives context', () async {
    final action = _TestAction();
    final context = PipelineContext(
      config: const CIToolsConfig(appName: 'Test', seedBuildNumber: 1000),
    );

    await action.run(context);

    expect(action.ran, isTrue);
    expect(action.capturedContext, same(context));
  });

  test('PipelineAction has a name', () {
    final action = _TestAction();
    expect(action.name, 'Test Action');
  });
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/actions/pipeline_action_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/pipeline_action.dart test/actions/pipeline_action_test.dart
git commit -m "feat: add PipelineAction interface"
```

---

### Task 2: Create PgyerUploadAction (TDD)

**Files:**
- Create: `test/actions/pgyer_upload_action_test.dart`
- Create: `lib/src/actions/pgyer_upload_action.dart`

- [ ] **Step 1: Write the test file**

```dart
// test/actions/pgyer_upload_action_test.dart
import 'package:flutter_ci_tools/src/actions/pgyer_upload_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final Map<String, ShellResult> _responses = {};
  ShellResult? _fallback;
  final List<String> runCalls = [];

  void stub(String executable, List<String> args, ShellResult result) {
    _responses['$executable ${args.join(' ')}'] = result;
  }

  void stubAny(ShellResult result) {
    _fallback = result;
  }

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String executable, List<String> args) async {
    final key = '$executable ${args.join(' ')}';
    runCalls.add(key);
    return _responses[key] ?? _fallback ?? ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

PipelineContext _makeContext({String? apiKey}) {
  final context = PipelineContext(
    config: CIToolsConfig(
      appName: 'TestApp',
      seedBuildNumber: 1000,
      pgyerApiKey: apiKey ?? 'test_api_key',
    ),
  );
  context.buildNumber = 1001;
  context.buildName;
  return context;
}

void main() {
  group('PgyerUploadAction', () {
    late _FakeShellRunner shell;
    late PgyerUploadAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = PgyerUploadAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Upload to Pgyer');
    });

    test('uploads file and stores pgyer_url in context', () async {
      shell.stub('curl', [
        '--http1.1',
        '-F', 'file=@test.apk',
        '-F', '_api_key=test_api_key',
        'https://www.pgyer.com/apiv2/app/upload',
      ], ShellResult(
        exitCode: 0,
        stdout: '{"code":0,"data":{"buildKey":"abc123"}}',
        stderr: '',
      ));

      final context = _makeContext();
      context.set<String>('artifact_path', 'test.apk');

      await action.run(context);

      expect(context.get<String>('pgyer_url'), 'https://www.pgyer.com/abc123');
    });

    test('includes description when pgyer_description is set', () async {
      shell.stub('curl', [
        '--http1.1',
        '-F', 'file=@test.apk',
        '-F', '_api_key=test_api_key',
        '-F', 'buildUpdateDescription=release notes',
        'https://www.pgyer.com/apiv2/app/upload',
      ], ShellResult(
        exitCode: 0,
        stdout: '{"code":0,"data":{"buildKey":"xyz"}}',
        stderr: '',
      ));

      final context = _makeContext();
      context.set<String>('artifact_path', 'test.apk');
      context.set<String>('pgyer_description', 'release notes');

      await action.run(context);

      expect(context.get<String>('pgyer_url'), 'https://www.pgyer.com/xyz');
    });

    test('throws DeployException on API error', () async {
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":1,"message":"Invalid API key"}',
        stderr: '',
      ));

      final context = _makeContext();
      context.set<String>('artifact_path', 'test.apk');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });

    test('throws DeployException on JSON parse failure', () async {
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '<html>502 Bad Gateway</html>',
        stderr: '',
      ));

      final context = _makeContext();
      context.set<String>('artifact_path', 'test.apk');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });

    test('retries on failure and succeeds', () async {
      var callCount = 0;
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":0,"data":{"buildKey":"retry-ok"}}',
        stderr: '',
      ));

      final context = _makeContext();
      context.set<String>('artifact_path', 'test.apk');

      await action.run(context);

      expect(context.get<String>('pgyer_url'), 'https://www.pgyer.com/retry-ok');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/actions/pgyer_upload_action_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement PgyerUploadAction**

```dart
// lib/src/actions/pgyer_upload_action.dart
import 'dart:convert';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads a build artifact to Pgyer and stores the download URL in context.
///
/// Reads: `artifact_path` (String), `config.pgyerApiKey`, `pgyer_description` (String?)
/// Writes: `pgyer_url` (String)
class PgyerUploadAction extends PipelineAction {
  PgyerUploadAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer';

  @override
  Future<void> run(PipelineContext context) async {
    final filePath = context.get<String>('artifact_path');
    final apiKey = context.config.pgyerApiKey!;
    final description = context.tryGet<String>('pgyer_description');

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
        final buildKey = response['data']['buildKey'];
        final fullUrl = 'https://www.pgyer.com/$buildKey';
        Logger.success('Upload successful! Download URL: $fullUrl');
        context.set<String>('pgyer_url', fullUrl);
      } else {
        throw DeployException(
          'Upload failed with API error: ${response['message']}',
        );
      }
    } catch (e) {
      if (e is DeployException) rethrow;
      throw DeployException('Failed to parse upload response: $e');
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/actions/pgyer_upload_action_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/pgyer_upload_action.dart test/actions/pgyer_upload_action_test.dart
git commit -m "feat: add PgyerUploadAction with retry logic"
```

---

### Task 3: Create FeishuNotifyAction (TDD)

**Files:**
- Create: `test/actions/feishu_notify_action_test.dart`
- Create: `lib/src/actions/feishu_notify_action.dart`

- [ ] **Step 1: Write the test file**

```dart
// test/actions/feishu_notify_action_test.dart
import 'package:flutter_ci_tools/src/actions/feishu_notify_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];
  final List<List<String>> capturedArgs = [];

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
    capturedArgs.add(args);
  }

  @override
  Future<ShellResult> runAndCapture(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
    capturedArgs.add(args);
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('FeishuNotifyAction', () {
    late _FakeShellRunner shell;
    late FeishuNotifyAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = FeishuNotifyAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Send Feishu Notification');
    });

    test('sends POST with correct JSON payload', () async {
      final context = PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          feishuWebhookUrl: 'https://hooks.example.com/webhook',
        ),
      );
      context.set<String>('notification_message', 'Hello from CI');

      await action.run(context);

      expect(shell.runCalls, contains(contains('https://hooks.example.com/webhook')));
      expect(shell.capturedArgs.first, contains('Hello from CI'));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/actions/feishu_notify_action_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement FeishuNotifyAction**

```dart
// lib/src/actions/feishu_notify_action.dart
import 'dart:convert';

import '../default_shell_runner.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Sends a text message to a Feishu (Lark) webhook.
///
/// Reads: `config.feishuWebhookUrl`, `notification_message` (String)
class FeishuNotifyAction extends PipelineAction {
  FeishuNotifyAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final webhookUrl = context.config.feishuWebhookUrl!;
    final message = context.get<String>('notification_message');

    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      "msg_type": "text",
      "content": {"text": message},
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

- [ ] **Step 4: Run tests**

Run: `dart test test/actions/feishu_notify_action_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/feishu_notify_action.dart test/actions/feishu_notify_action_test.dart
git commit -m "feat: add FeishuNotifyAction"
```

---

### Task 4: Create GooglePlayUploadAction (TDD)

**Files:**
- Create: `test/actions/google_play_action_test.dart`
- Create: `lib/src/actions/google_play_action.dart`

- [ ] **Step 1: Write the test file**

```dart
// test/actions/google_play_action_test.dart
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/google_play_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('GooglePlayUploadAction', () {
    late _FakeShellRunner shell;
    late GooglePlayUploadAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = GooglePlayUploadAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Upload to Google Play');
    });

    test('throws if json key file does not exist', () {
      final context = PipelineContext(
        config: const CIToolsConfig(appName: 'Test', seedBuildNumber: 1000),
      );
      context.set<String>('artifact_path', 'nonexistent.aab');
      context.set<String>('google_play_package_name', 'com.example');
      context.set<String>('google_play_json_key_path', '/nonexistent/path.json');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/actions/google_play_action_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement GooglePlayUploadAction**

```dart
// lib/src/actions/google_play_action.dart
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an AAB file to Google Play via Fastlane Supply.
///
/// Reads: `artifact_path` (String), `google_play_package_name` (String),
///        `google_play_json_key_path` (String)
class GooglePlayUploadAction extends PipelineAction {
  GooglePlayUploadAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Google Play';

  @override
  Future<void> run(PipelineContext context) async {
    final aabPath = context.get<String>('artifact_path');
    final packageName = context.get<String>('google_play_package_name');
    final jsonKeyPath = context.get<String>('google_play_json_key_path');

    Logger.section('Uploading to Google Play');
    Logger.info('AAB: $aabPath');
    Logger.info('Package: $packageName');
    if (!File(jsonKeyPath).existsSync()) {
      throw DeployException(
        'Google Play Service Account JSON not found at $jsonKeyPath',
      );
    }
    await _shellRunner.run('fastlane', [
      'supply',
      '--aab', aabPath,
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

- [ ] **Step 4: Run tests**

Run: `dart test test/actions/google_play_action_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/google_play_action.dart test/actions/google_play_action_test.dart
git commit -m "feat: add GooglePlayUploadAction"
```

---

### Task 5: Create AppStoreUploadAction (TDD)

**Files:**
- Create: `test/actions/app_store_action_test.dart`
- Create: `lib/src/actions/app_store_action.dart`

- [ ] **Step 1: Write the test file**

```dart
// test/actions/app_store_action_test.dart
import 'dart:io';

import 'package:flutter_ci_tools/src/actions/app_store_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('AppStoreUploadAction', () {
    late _FakeShellRunner shell;
    late AppStoreUploadAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = AppStoreUploadAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Upload to App Store');
    });

    test('throws if api key file does not exist', () {
      final context = PipelineContext(
        config: const CIToolsConfig(appName: 'Test', seedBuildNumber: 1000),
      );
      context.set<String>('artifact_path', 'nonexistent.ipa');
      context.set<String>('app_store_issuer_id', 'issuer123');
      context.set<String>('app_store_api_key_id', 'key123');
      context.set<String>('app_store_api_key_path', '/nonexistent/key.p8');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/actions/app_store_action_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement AppStoreUploadAction**

```dart
// lib/src/actions/app_store_action.dart
import 'dart:convert';
import 'dart:io';

import '../default_shell_runner.dart';
import '../exceptions.dart';
import '../logger.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Uploads an IPA file to App Store Connect via Fastlane Pilot.
///
/// Reads: `artifact_path` (String), `app_store_issuer_id` (String),
///        `app_store_api_key_id` (String), `app_store_api_key_path` (String)
class AppStoreUploadAction extends PipelineAction {
  AppStoreUploadAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to App Store';

  @override
  Future<void> run(PipelineContext context) async {
    final ipaPath = context.get<String>('artifact_path');
    final issuerId = context.get<String>('app_store_issuer_id');
    final apiKeyId = context.get<String>('app_store_api_key_id');
    final apiKeyPath = context.get<String>('app_store_api_key_path');

    Logger.section('Uploading to App Store');
    Logger.info('IPA: $ipaPath');
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
        '--ipa', ipaPath,
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

- [ ] **Step 4: Run tests**

Run: `dart test test/actions/app_store_action_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/app_store_action.dart test/actions/app_store_action_test.dart
git commit -m "feat: add AppStoreUploadAction"
```

---

### Task 6: Update BuildPipeline — remove DeployService

**Files:**
- Modify: `lib/src/pipeline.dart`

- [ ] **Step 1: Remove DeployService from BuildPipeline**

In `lib/src/pipeline.dart`:

Remove the import:
```dart
import 'deploy_service.dart';
```

In the constructor, remove `DeployService? deployService` parameter and `_deployService = deployService ?? DefaultDeployService()` initializer.

Remove these fields/getters:
```dart
final DeployService _deployService;
DeployService get deployService => _deployService;
```

Remove the `uploadToPgyerAndNotify` method entirely (lines 193-219).

Keep `buildFeishuMessage` and `_coreInfoLines` — subclasses use them to assemble `notification_message`.

- [ ] **Step 2: Verify pipeline.dart compiles**

Run: `dart analyze lib/src/pipeline.dart`
Expected: No errors in this file (subclasses will break, fixed in next task).

- [ ] **Step 3: Commit**

```bash
git add lib/src/pipeline.dart
git commit -m "refactor: remove DeployService from BuildPipeline"
```

---

### Task 7: Update example pipelines to use actions

**Files:**
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`
- Modify: `example/ci/pipelines/android_test_pipeline.dart`

- [ ] **Step 1: Update test_pipeline.dart**

Replace the entire file content with:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class TestPipeline extends BuildPipeline {
  TestPipeline() : super(exampleConfig);

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
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> deployAndroid(File apk) async =>
      _deployToPgyer(AppPlatform.android, apk);

  @override
  Future<void> deployIOS(File ipa) async =>
      _deployToPgyer(AppPlatform.ios, ipa);

  Future<void> _deployToPgyer(AppPlatform platform, File file) async {
    context.set<String>('artifact_path', file.path);
    context.set<String>('pgyer_description', [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         $envName',
      'api_host:    $apiHost',
      'git_hash:    ${context.metadata.gitHash}',
      '',
      'recent commits:',
      context.metadata.recentCommits,
    ].join('\n'));

    await PgyerUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: platform,
      target: DeployTarget.pgyer,
      downloadUrl: context.get<String>('pgyer_url'),
    ));
    await FeishuNotifyAction().run(context);
  }
}
```

- [ ] **Step 2: Update prod_pipeline.dart**

Replace the entire file content with:

```dart
import 'dart:io';

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
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> deployAndroid(File aab) async {
    context.set<String>('artifact_path', aab.path);
    context.set<String>('google_play_package_name', ProdCredentials.googlePlayPackageName);
    context.set<String>('google_play_json_key_path', ProdCredentials.googlePlayJsonKeyPath);

    await GooglePlayUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.android,
      target: DeployTarget.googlePlay,
    ));
    await FeishuNotifyAction().run(context);
  }

  @override
  Future<void> deployIOS(File ipa) async {
    context.set<String>('artifact_path', ipa.path);
    context.set<String>('app_store_issuer_id', ProdCredentials.appStoreIssuerId);
    context.set<String>('app_store_api_key_id', ProdCredentials.appStoreApiKeyId);
    context.set<String>('app_store_api_key_path', ProdCredentials.appStoreApiKeyPath);

    await AppStoreUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.ios,
      target: DeployTarget.appStore,
    ));
    await FeishuNotifyAction().run(context);
  }
}
```

- [ ] **Step 3: Update android_test_pipeline.dart**

Replace the entire file content with:

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import '../app_config.dart';
import '../build_info_writer.dart';

class AndroidTestPipeline extends BuildPipeline {
  AndroidTestPipeline() : super(exampleConfig);

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
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> deployAndroid(File apk) async {
    context.set<String>('artifact_path', apk.path);
    context.set<String>('pgyer_description', [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         $envName',
      'api_host:    $apiHost',
      'git_hash:    ${context.metadata.gitHash}',
      '',
      'recent commits:',
      context.metadata.recentCommits,
    ].join('\n'));

    await PgyerUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      downloadUrl: context.get<String>('pgyer_url'),
    ));
    await FeishuNotifyAction().run(context);
  }

  @override
  Future<void> deployIOS(File ipa) async {
    context.set<String>('artifact_path', ipa.path);
    context.set<String>('pgyer_description', [
      'versionName: ${context.buildName}',
      'versionCode: ${context.buildNumber}',
      'env:         $envName',
      'api_host:    $apiHost',
      'git_hash:    ${context.metadata.gitHash}',
      '',
      'recent commits:',
      context.metadata.recentCommits,
    ].join('\n'));

    await PgyerUploadAction().run(context);

    context.set<String>('notification_message', buildFeishuMessage(
      platform: AppPlatform.ios,
      target: DeployTarget.pgyer,
      downloadUrl: context.get<String>('pgyer_url'),
    ));
    await FeishuNotifyAction().run(context);
  }

  @override
  String get description => "android 测试环境版本构建，用于开发期间调试脚本的功能";

  @override
  String get help => "this is help text";

  @override
  String get name => "android_test";
}
```

- [ ] **Step 4: Verify example compiles**

Run: `dart analyze example/`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add example/ci/pipelines/
git commit -m "refactor: update example pipelines to use PipelineAction"
```

---

### Task 8: Update pipeline tests

**Files:**
- Modify: `test/pipeline_test.dart`

- [ ] **Step 1: Remove _FakeDeployService and its usage**

In `test/pipeline_test.dart`:

Delete the `_FakeDeployService` class (lines 71-89).

Remove `deploy` from the `createPipeline` method and `setUp`:
```dart
// Before:
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

// After:
_TestPipeline createPipeline() => _TestPipeline(
      config,
      versionManager: version,
      gitManager: git,
      shellRunner: shell,
      androidBuilder: _FakeAndroidBuilder(),
      iosBuilder: _FakeIOSBuilder(),
    );

setUp(() {
    version = _FakeVersionManager();
    git = _FakeGitManager();
    shell = _FakeShellRunner();
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000);
  });
```

Remove the `late _FakeDeployService deploy;` declaration.

Remove the `deploy_service.dart` import if present.

- [ ] **Step 2: Run all tests**

Run: `dart test`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/pipeline_test.dart
git commit -m "test: remove FakeDeployService from pipeline tests"
```

---

### Task 9: Delete DeployService and update exports

**Files:**
- Delete: `lib/src/deploy_service.dart`
- Delete: `test/deploy_service_test.dart`
- Modify: `lib/flutter_ci_tools.dart`

- [ ] **Step 1: Delete DeployService files**

```bash
rm lib/src/deploy_service.dart test/deploy_service_test.dart
```

- [ ] **Step 2: Update barrel export**

In `lib/flutter_ci_tools.dart`, replace:

```dart
export 'src/deploy_service.dart';
```

With:

```dart
export 'src/actions/app_store_action.dart';
export 'src/actions/feishu_notify_action.dart';
export 'src/actions/google_play_action.dart';
export 'src/actions/pgyer_upload_action.dart';
export 'src/actions/pipeline_action.dart';
```

These should be placed alphabetically among the existing exports.

- [ ] **Step 3: Verify no stale references**

Run: `grep -rn 'deploy_service\|DeployService\|DefaultDeployService' lib/ test/ example/`
Expected: No matches.

- [ ] **Step 4: Run full test suite**

Run: `dart test`
Expected: All tests PASS.

- [ ] **Step 5: Run static analysis**

Run: `dart analyze`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: delete DeployService, replaced by PipelineAction classes"
```
