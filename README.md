# flutter_ci_tools

Reusable CI tooling for Flutter apps. Provides a pipeline/action architecture
for build orchestration, git-tag-based versioning, deploy services (Pgyer,
Feishu, Google Play, App Store), and structured terminal logging.

## Quick Start

### 1. Entry point — `ci/build.dart`

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'pipelines/test_pipeline.dart';
import 'pipelines/prod_pipeline.dart';

Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(TestPipeline())
    ..register(ProdPipeline());
  await registry.run(args);
}
```

### 2. Define a pipeline

```dart
class TestPipeline extends BuildPipeline {
  @override String get name => 'test';
  @override String get description => 'Build & deploy to Pgyer';
  @override String get help => '...';

  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      MyAppContext(platforms: platforms);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CleanProjectAction());

    if (context.platforms.contains(AppPlatform.android)) {
      final apk = await runAction(BuildAndroidAction(
        envName: 'test', buildType: AndroidBuildType.apk,
      ));
      await runAction(PgyerUploadAction(
        artifact: apk, apiKey: (context as MyAppContext).pgyerApiKey, description: '...',
      ));
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

## Usage

### 1. Define your PipelineContext

Subclass `PipelineContext` to bundle shared configuration (app name,
credentials, etc.) across all pipelines:

```dart
class MyAppContext extends PipelineContext {
  MyAppContext({required super.platforms})
      : super(appName: 'MyApp', seedBuildNumber: 10000);

  String get pgyerApiKey => Platform.environment['PGYER_API_KEY'] ?? '';
  String get feishuWebhookUrl => Platform.environment['FEISHU_WEBHOOK_URL'] ?? '';
}
```

### 2. Create a BuildPipeline

Implement `body()` to compose actions. Use `runAction()` to execute each
step with automatic logging and error handling:

```dart
class MyPipeline extends BuildPipeline {
  @override String get name => 'test';
  @override String get description => '...';
  @override String get help => '...';

  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      MyAppContext(platforms: platforms);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    // ... compose more actions
  }
}
```

### 3. Register & run

```dart
Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(MyPipeline());
  await registry.run(args);
}
```

Run from the command line:

```bash
dart run ci/build.dart test           # both platforms
dart run ci/build.dart test android   # Android only
dart run ci/build.dart                # interactive selector
```

## API

| Symbol | Description |
|--------|-------------|
| `PipelineContext` | Shared config + runtime state passed through all actions |
| `BuildPipeline` | Abstract base: `beforeBuild → body → afterBuild` lifecycle |
| `PipelineAction<R>` | Abstract action unit; receives context, returns typed result |
| `PipelineRegistry` | Registers pipelines; handles CLI routing and interactive selection |
| `runStep` | Logs + times a pipeline step, rethrows on failure |
| `Logger` | Coloured stdout/stderr output |
| `ShellRunner` | Process runner with live streaming and capture |
| `GitManager` | Git status, branch, hash, commit history |
| `VersionManager` | `builds/*` git-tag-based build numbering |
| `BuildMetadata` | Collects branch/user/hash/commits at build time |

Built-in actions include `ResolveBuildVersionAction`, `CollectMetadataAction`,
`CheckGitStatusAction`, `CleanProjectAction`, `BuildAndroidAction`,
`BuildIOSAction`, `PgyerUploadAction`, `PgyerUploadV2Action`,
`GooglePlayUploadAction`, `AppStoreUploadAction`, `FeishuBuildNotifyAction`,
`FeishuNotifyAction`, `SwapInfoPlistAction`, `PushBuildTagAction`,
and `RestoreWorkspaceAction`.

## Example

A complete consumer demo lives in [`example/`](./example/) — three pipelines
(test, prod, android-test), all deploy targets, and a Flutter app that displays
its own build metadata at runtime.
