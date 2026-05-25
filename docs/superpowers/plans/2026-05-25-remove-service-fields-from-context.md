# Remove Service-Specific Fields from PipelineContext

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `pgyerApiKey` and `feishuWebhookUrl` from `PipelineContext`, making each action responsible for receiving its own credentials via constructor parameters.

**Architecture:** Credentials flow directly from pipeline `body()` to action constructors. `PipelineContext` retains only shared runtime state (`appName`, `seedBuildNumber`, `platforms`, `metadata`, `buildNumber`). Example code stores credentials as getters on context subclasses for convenience.

**Tech Stack:** Dart, package:test

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/src/pipeline_context.dart` | Modify | Remove `pgyerApiKey` and `feishuWebhookUrl` fields |
| `lib/src/actions/feishu_notify_action.dart` | Modify | Add `webhookUrl` constructor param |
| `lib/src/actions/feishu_build_notify_action.dart` | Modify | Add `webhookUrl` constructor param, pass to `FeishuNotifyAction` |
| `example/ci/app_config.dart` | Modify | Remove fields from super call, keep as local getters |
| `example/ci/pipelines/android_test_pipeline.dart` | Modify | Store credentials locally, pass to actions |
| `example/ci/pipelines/test_pipeline.dart` | Modify | Access credentials via typed context |
| `example/ci/pipelines/prod_pipeline.dart` | Modify | Pass `webhookUrl` to `FeishuBuildNotifyAction` |
| `test/pipeline_context_test.dart` | Modify | Remove credential-related test cases |
| `test/actions/feishu_notify_action_test.dart` | Modify | Pass `webhookUrl` to action constructor |
| `test/actions/feishu_build_notify_action_test.dart` | Modify | Pass `webhookUrl` to action constructor |

---

### Task 1: Update FeishuNotifyAction to accept webhookUrl via constructor

**Files:**
- Modify: `lib/src/actions/feishu_notify_action.dart`
- Modify: `test/actions/feishu_notify_action_test.dart`

- [ ] **Step 1: Update FeishuNotifyAction**

Add `webhookUrl` as a required constructor parameter. Remove the `context.feishuWebhookUrl!` read from `run()`.

```dart
// lib/src/actions/feishu_notify_action.dart
class FeishuNotifyAction extends PipelineAction<void> {
  FeishuNotifyAction({
    required this.webhookUrl,
    required this.message,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String webhookUrl;
  final String message;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Notification';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('Sending Feishu notification...');
    final jsonMessage = jsonEncode({
      'msg_type': 'text',
      'content': {'text': message},
    });
    final result = await _shellRunner.runAndCapture('curl', [
      '-X',
      'POST',
      '-H',
      'Content-Type: application/json',
      '-d',
      jsonMessage,
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

- [ ] **Step 2: Update FeishuNotifyAction test**

Pass `webhookUrl` to the action constructor instead of setting it on context.

```dart
// test/actions/feishu_notify_action_test.dart
test('FeishuNotifyAction posts the given message to the configured webhook',
    () async {
  final shell = _FakeShellRunner();
  final context = PipelineContext(
    appName: 'TestApp',
    seedBuildNumber: 1000,
    platforms: {AppPlatform.android},
  );

  final action = FeishuNotifyAction(
    webhookUrl: 'https://open.feishu.cn/hook',
    message: 'hello world',
    shellRunner: shell,
  );
  await action.run(context);

  expect(action.name, 'Send Feishu Notification');
  expect(shell.lastUrl, 'https://open.feishu.cn/hook');
  expect(shell.lastJson, contains('hello world'));
  expect(shell.lastJson, contains('text'));
});
```

- [ ] **Step 3: Run tests to verify**

Run: `dart test test/actions/feishu_notify_action_test.dart`
Expected: PASS (note: will fail until Task 2 removes `feishuWebhookUrl` from PipelineContext if test still references it — but the test above no longer does, so it should pass)

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/feishu_notify_action.dart test/actions/feishu_notify_action_test.dart
git commit -m "refactor: FeishuNotifyAction accepts webhookUrl via constructor"
```

---

### Task 2: Update FeishuBuildNotifyAction to accept webhookUrl via constructor

**Files:**
- Modify: `lib/src/actions/feishu_build_notify_action.dart`
- Modify: `test/actions/feishu_build_notify_action_test.dart`

- [ ] **Step 1: Update FeishuBuildNotifyAction**

Add `webhookUrl` as a required constructor parameter. Pass it through to `FeishuNotifyAction` in `run()`.

```dart
// lib/src/actions/feishu_build_notify_action.dart
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.platform,
    required this.target,
    this.downloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? DefaultShellRunner();

  final String webhookUrl;
  final AppPlatform platform;
  final DeployTarget target;
  final String? downloadUrl;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Send Feishu Build Notification';

  @override
  Future<void> run(PipelineContext context) async {
    final message = _formatMessage(context);
    await FeishuNotifyAction(
      webhookUrl: webhookUrl,
      message: message,
      shellRunner: _shellRunner,
    ).run(context);
  }

  // _formatMessage stays unchanged
}
```

- [ ] **Step 2: Update FeishuBuildNotifyAction test**

Pass `webhookUrl` to the action constructor instead of setting it on context.

```dart
// test/actions/feishu_build_notify_action_test.dart
test('FeishuBuildNotifyAction sends formatted build message via webhook',
    () async {
  final shell = _FakeShellRunner();
  final context = PipelineContext(
    appName: 'TestApp',
    seedBuildNumber: 12000,
    platforms: <AppPlatform>{},
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
    webhookUrl: 'https://open.feishu.cn/hook',
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
```

- [ ] **Step 3: Run tests to verify**

Run: `dart test test/actions/feishu_build_notify_action_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/src/actions/feishu_build_notify_action.dart test/actions/feishu_build_notify_action_test.dart
git commit -m "refactor: FeishuBuildNotifyAction accepts webhookUrl via constructor"
```

---

### Task 3: Remove pgyerApiKey and feishuWebhookUrl from PipelineContext

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Modify: `test/pipeline_context_test.dart`

- [ ] **Step 1: Remove fields from PipelineContext**

```dart
// lib/src/pipeline_context.dart
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
  });

  final String appName;
  final int seedBuildNumber;
  final Set<AppPlatform> platforms;
  late BuildMetadata metadata;
  late int buildNumber;

  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }
}
```

- [ ] **Step 2: Update PipelineContext test**

Remove the `pgyerApiKey`/`feishuWebhookUrl` related test cases. Keep all other tests.

```dart
// test/pipeline_context_test.dart — remove these two tests:
// - 'exposes flattened config fields' (rewrite without credential assertions)
// - 'accepts optional credentials' (delete entirely)

// Updated 'exposes flattened config fields' test:
test('exposes config fields', () {
  expect(ctx.appName, 'TestApp');
  expect(ctx.seedBuildNumber, 12000);
});
```

- [ ] **Step 3: Run all tests**

Run: `dart test`
Expected: PASS (example code will fail to compile — that's fixed in Tasks 4-5)

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart
git commit -m "refactor: remove pgyerApiKey and feishuWebhookUrl from PipelineContext"
```

---

### Task 4: Update ExampleAppContext and its pipelines

**Files:**
- Modify: `example/ci/app_config.dart`
- Modify: `example/ci/pipelines/test_pipeline.dart`
- Modify: `example/ci/pipelines/prod_pipeline.dart`

- [ ] **Step 1: Update ExampleAppContext**

Remove `pgyerApiKey` and `feishuWebhookUrl` from the super call. Keep them as local getters for pipelines to use.

```dart
// example/ci/app_config.dart
class ExampleAppContext extends PipelineContext {
  ExampleAppContext({required super.platforms})
      : super(
          appName: 'FlutterCIToolsExample',
          seedBuildNumber: 10000,
        );

  String get pgyerApiKey => _env('PGYER_API_KEY');
  String get feishuWebhookUrl => _env('FEISHU_WEBHOOK_URL');
}
```

- [ ] **Step 2: Update TestPipeline**

Cast `context` to `ExampleAppContext` to access credentials. Pass `webhookUrl` to `FeishuBuildNotifyAction`.

In `_deployToPgyer`, change:
```dart
// Before:
apiKey: context.pgyerApiKey!,
// After:
apiKey: (context as ExampleAppContext).pgyerApiKey,
```

Add `webhookUrl` to both `FeishuBuildNotifyAction` calls:
```dart
await runAction(FeishuBuildNotifyAction(
  webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
  platform: platform,
  target: DeployTarget.pgyer,
  downloadUrl: pgyerUrl,
));
```

- [ ] **Step 3: Update ProdPipeline**

Add `webhookUrl` to both `FeishuBuildNotifyAction` calls. Since `ProdPipeline` creates `ExampleAppContext`, cast context:

```dart
await runAction(FeishuBuildNotifyAction(
  webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
  platform: AppPlatform.android,
  target: DeployTarget.googlePlay,
));
```

(Same for the iOS block with `DeployTarget.appStore`.)

- [ ] **Step 4: Run dart analyze**

Run: `dart analyze`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add example/ci/app_config.dart example/ci/pipelines/test_pipeline.dart example/ci/pipelines/prod_pipeline.dart
git commit -m "refactor: update example pipelines to pass credentials directly to actions"
```

---

### Task 5: Update AndroidTestPipeline

**Files:**
- Modify: `example/ci/pipelines/android_test_pipeline.dart`

- [ ] **Step 1: Update AndroidTestContext and AndroidTestPipeline**

Remove credential fields from `AndroidTestContext` super call. Store them as local fields. Pass to actions in `body()`.

```dart
// example/ci/pipelines/android_test_pipeline.dart
class AndroidTestContext extends PipelineContext {
  AndroidTestContext({required super.platforms})
      : super(
          appName: 'testAppName',
          seedBuildNumber: 10000,
        );

  final String pgyerApiKey = '1540c89d7f12ade530a14ac4adf9caa2';
  final String feishuWebhookUrl =
      'https://open.feishu.cn/open-apis/bot/v2/hook/82ab0b57-f8c9-493f-a69d-575271f12bfd';
}
```

In `body()`, cast context and pass credentials:
```dart
final ctx = context as AndroidTestContext;

final pgyerUrl = await runAction(PgyerUploadAction(
  artifact: apk,
  apiKey: ctx.pgyerApiKey,
));
await runAction(FeishuBuildNotifyAction(
  webhookUrl: ctx.feishuWebhookUrl,
  platform: AppPlatform.android,
  target: DeployTarget.pgyer,
  downloadUrl: pgyerUrl,
));
```

- [ ] **Step 2: Run dart analyze**

Run: `dart analyze`
Expected: No errors

- [ ] **Step 3: Run all tests**

Run: `dart test`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add example/ci/pipelines/android_test_pipeline.dart
git commit -m "refactor: update AndroidTestPipeline to pass credentials directly to actions"
```

---

### Task 6: Final verification

- [ ] **Step 1: Run full test suite**

Run: `dart test`
Expected: All tests PASS

- [ ] **Step 2: Run dart analyze**

Run: `dart analyze`
Expected: No issues

- [ ] **Step 3: Verify no stale references**

Run: `grep -r 'pgyerApiKey\|feishuWebhookUrl' lib/src/`
Expected: No matches (fields fully removed from library code)

- [ ] **Step 4: Final commit if needed**

If any cleanup was needed:
```bash
git add -A && git commit -m "chore: clean up stale references to removed PipelineContext fields"
```
