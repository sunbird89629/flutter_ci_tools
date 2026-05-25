# Pipeline Actions Design

## Problem

DeployService is a fat interface with 4 unrelated methods (uploadToPgyer, sendFeishuNotification, uploadToGooglePlay, uploadToAppStore). This violates single responsibility — adding a new deploy target means modifying the interface and all implementations. The methods are independent operations that don't share state, yet they're bundled into one injectable service.

## Goal

Replace DeployService with independent PipelineAction classes that:
1. Each encapsulate one deploy/notification operation
2. Communicate through PipelineContext's key-value store
3. Are independently testable with fake ShellRunner
4. Follow the existing DI pattern (constructor injection)

## Design

### PipelineAction Interface

```dart
abstract class PipelineAction {
  String get name;
  Future<void> run(PipelineContext context);
}
```

- `name`: human-readable label for logging
- `run`: executes the action, reads inputs from context, stores results via `context.set`
- Returns `void` — all outputs go through context store

### Concrete Actions

**PgyerUploadAction**
- Reads: `artifact_path` (String), `config.pgyerApiKey`, `pgyer_description` (String?, optional)
- Writes: `pgyer_url` (String) — the download URL
- Internals: curl with 3-attempt retry, JSON response parsing (copied from DefaultDeployService.uploadToPgyer)
- Constructor: `PgyerUploadAction({ShellRunner? shellRunner})`

**FeishuNotifyAction**
- Reads: `config.feishuWebhookUrl`, `notification_message` (String)
- Writes: nothing
- Internals: curl POST with JSON payload (copied from DefaultDeployService.sendFeishuNotification)
- Constructor: `FeishuNotifyAction({ShellRunner? shellRunner})`

**GooglePlayUploadAction**
- Reads: `artifact_path` (String), `google_play_package_name` (String), `google_play_json_key_path` (String)
- Writes: nothing
- Internals: fastlane supply (copied from DefaultDeployService.uploadToGooglePlay)
- Constructor: `GooglePlayUploadAction({ShellRunner? shellRunner})`

**AppStoreUploadAction**
- Reads: `artifact_path` (String), `app_store_issuer_id` (String), `app_store_api_key_id` (String), `app_store_api_key_path` (String)
- Writes: nothing
- Internals: fastlane pilot with temp api_key.json (copied from DefaultDeployService.uploadToAppStore)
- Constructor: `AppStoreUploadAction({ShellRunner? shellRunner})`

### Context Store Key Conventions

| Key | Type | Writer | Reader |
|-----|------|--------|--------|
| `artifact_path` | `String` | pipeline (build step) | all upload actions |
| `pgyer_url` | `String` | PgyerUploadAction | FeishuNotifyAction (via pipeline) |
| `pgyer_description` | `String` | pipeline | PgyerUploadAction |
| `notification_message` | `String` | pipeline (buildFeishuMessage) | FeishuNotifyAction |
| `google_play_package_name` | `String` | pipeline | GooglePlayUploadAction |
| `google_play_json_key_path` | `String` | pipeline | GooglePlayUploadAction |
| `app_store_issuer_id` | `String` | pipeline | AppStoreUploadAction |
| `app_store_api_key_id` | `String` | pipeline | AppStoreUploadAction |
| `app_store_api_key_path` | `String` | pipeline | AppStoreUploadAction |

### BuildPipeline Changes

Remove:
- `DeployService` constructor parameter and `_deployService` field
- `DeployService get deployService` getter
- `uploadToPgyerAndNotify()` convenience method

Keep:
- `buildFeishuMessage()` — subclasses use it to assemble `notification_message` for context

### Subclass Pattern

```dart
@override
Future<void> deployAndroid(File file) async {
  context.set<String>('artifact_path', file.path);
  await PgyerUploadAction().run(context);
  context.set<String>('notification_message', buildFeishuMessage(
    platform: AppPlatform.android,
    target: DeployTarget.pgyer,
    downloadUrl: context.get<String>('pgyer_url'),
  ));
  await FeishuNotifyAction().run(context);
}
```

### Error Handling

Each action throws `DeployException` on failure. PgyerUploadAction retains 3-attempt retry. Pipeline's existing `runStep` catches and logs.

### Testing

Each action tested independently with fake ShellRunner. Existing deploy_service_test patterns (stub curl responses, verify context state) migrate to per-action test files.

## Files

| File | Action |
|------|--------|
| `lib/src/actions/pipeline_action.dart` | Create |
| `lib/src/actions/pgyer_upload_action.dart` | Create |
| `lib/src/actions/feishu_notify_action.dart` | Create |
| `lib/src/actions/google_play_action.dart` | Create |
| `lib/src/actions/app_store_action.dart` | Create |
| `test/actions/pgyer_upload_action_test.dart` | Create |
| `test/actions/feishu_notify_action_test.dart` | Create |
| `test/actions/google_play_action_test.dart` | Create |
| `test/actions/app_store_action_test.dart` | Create |
| `lib/src/deploy_service.dart` | Delete |
| `test/deploy_service_test.dart` | Delete |
| `lib/flutter_ci_tools.dart` | Update exports |
| `lib/src/pipeline.dart` | Remove DeployService, keep buildFeishuMessage |
| `example/ci/pipelines/*.dart` | Update deploy methods to use actions |
| `test/pipeline_test.dart` | Remove _FakeDeployService, update pipeline tests |

## Migration Order

1. Create PipelineAction interface + 4 action classes (copy logic from DeployService)
2. Create action tests (copy/adapt from deploy_service_test)
3. Update BuildPipeline: remove DeployService, keep buildFeishuMessage
4. Update subclasses: deploy methods use actions
5. Update pipeline tests
6. Delete DeployService + its test
7. Update barrel export
