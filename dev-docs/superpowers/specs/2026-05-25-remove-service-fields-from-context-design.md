# Remove Service-Specific Fields from PipelineContext

**Date:** 2026-05-25
**Status:** Approved

## Problem

`PipelineContext` currently holds two service-specific credential fields: `pgyerApiKey` and `feishuWebhookUrl`. These fields:

- **Violate single responsibility** -- a generic pipeline context shouldn't know about specific third-party services.
- **Won't scale** -- adding fir.im, email, Slack, etc. would mean constantly expanding PipelineContext.
- **Are used inconsistently** -- `pgyerApiKey` is already passed via action constructor (context is just a middleman), while `feishuWebhookUrl` is force-unwrapped directly inside `FeishuNotifyAction.run()`.
- **Are partially redundant** -- Google Play and App Store actions already bypass PipelineContext entirely for their credentials (using a separate `ProdCredentials` class in the example).

## Design

### Principle

Credentials are the action's own concern. Each `PipelineAction` receives its credentials via constructor parameters. `PipelineContext` holds only shared pipeline runtime state.

### Changes

#### 1. PipelineContext (`lib/src/pipeline_context.dart`)

Remove `pgyerApiKey` and `feishuWebhookUrl` fields and their constructor parameters.

**Before:**
```dart
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
    this.pgyerApiKey,
    this.feishuWebhookUrl,
  });
  // ...
  final String? pgyerApiKey;
  final String? feishuWebhookUrl;
}
```

**After:**
```dart
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
  });
  // ...
  // pgyerApiKey and feishuWebhookUrl removed
}
```

#### 2. FeishuNotifyAction (`lib/src/actions/feishu_notify_action.dart`)

Accept `webhookUrl` via constructor instead of reading from context.

**Before:**
```dart
class FeishuNotifyAction extends PipelineAction<void> {
  FeishuNotifyAction({required this.message});
  final String message;

  @override
  Future<void> run(PipelineContext context) async {
    final webhookUrl = context.feishuWebhookUrl!;  // force-unwrap from context
    // ...
  }
}
```

**After:**
```dart
class FeishuNotifyAction extends PipelineAction<void> {
  FeishuNotifyAction({required this.webhookUrl, required this.message});
  final String webhookUrl;
  final String message;

  @override
  Future<void> run(PipelineContext context) async {
    // use this.webhookUrl directly
  }
}
```

#### 3. FeishuBuildNotifyAction (`lib/src/actions/feishu_build_notify_action.dart`)

Add `webhookUrl` to constructor, pass through to internal `FeishuNotifyAction`.

**Before:**
```dart
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({required this.deployTarget, this.downloadUrl});
  // ...
  @override
  Future<void> run(PipelineContext context) async {
    // ... format message ...
    await FeishuNotifyAction(message: message).run(context);
  }
}
```

**After:**
```dart
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.deployTarget,
    this.downloadUrl,
  });
  final String webhookUrl;
  // ...
  @override
  Future<void> run(PipelineContext context) async {
    // ... format message ...
    await FeishuNotifyAction(webhookUrl: webhookUrl, message: message).run(context);
  }
}
```

#### 4. Example code (`example/ci/`)

- **`app_config.dart`**: `ExampleAppContext` removes `pgyerApiKey` and `feishuWebhookUrl` from its PipelineContext super call. The env var reads stay here as local getters (`String get pgyerApiKey => _env('PGYER_API_KEY')`) so pipelines can access them via `context.pgyerApiKey` where `context` is typed as `ExampleAppContext`.
- **`pipelines/test_pipeline.dart`**: `body()` accesses credentials via the typed context (e.g. `(context as ExampleAppContext).pgyerApiKey`) and passes to action constructors.
- **`pipelines/android_test_pipeline.dart`**: Same pattern -- either via typed context or direct hardcoding.
- **`pipelines/prod_pipeline.dart`**: Already uses `ProdCredentials` -- no change needed for Google Play / App Store. Update `FeishuBuildNotifyAction` calls to pass `webhookUrl`.

#### 5. Tests

Update all test files that construct `PipelineContext` with `pgyerApiKey` or `feishuWebhookUrl`:
- `test/pipeline_context_test.dart`
- `test/actions/feishu_notify_action_test.dart`
- `test/actions/feishu_build_notify_action_test.dart`

### What stays the same

- `PgyerUploadAction` / `PgyerUploadV2Action` -- already use constructor params for `apiKey`. No change needed.
- `GooglePlayUploadAction` / `AppStoreUploadAction` -- already use constructor params. No change needed.
- `DeployTarget` enum -- stays as-is (it's a notification label, not a credential concern).
- Pipeline architecture -- no structural changes.

### Out of scope

- Introducing a generic credential/config bag on PipelineContext.
- Abstracting deploy targets or notification channels into interfaces.
- Adding new notification channels (email, Slack, etc.) -- that's a separate effort.
