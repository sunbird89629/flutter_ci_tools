# flutter_ci_tools

Reusable CI tooling for Flutter apps. Provides a pipeline/action architecture
for build orchestration, git-tag-based versioning, deploy services (Pgyer,
Feishu, Google Play, App Store), and structured terminal logging.

## Execution Summary

Every `runAction()` call records the action's `status`
(`success` / `failed` / `skipped` / `interrupted`), `duration`, and any
`error` / `stackTrace`. When the pipeline finishes (success or failure),
a summary is printed automatically:

```
────────────────────────────────────
执行摘要
────────────────────────────────────
✅ ResolveBuildVersionAction (12ms)
✅ CleanProjectAction (3.1s)
✅ BuildAndroidAction (47.2s)
❌ PgyerUploadAction (1.8s)
────────────────────────────────────
```

The same information is available programmatically via
`pipeline.executedActions`, `pipeline.allSucceeded`, and
`pipeline.lastFailure` — useful for custom post-build hooks (e.g. a
Feishu notification that reports which step failed).

## Design Philosophy

- **Minimal concepts.** Three building blocks: Pipeline, Action, Context. Nothing else to learn.
- **Code is the config.** No YAML, no DSL. Compose pipelines in Dart and the type checker is your linter.
- **Batteries included.** Built-in actions cover the common path — clean, version, build, upload, notify.
- **Zero ceiling.** Every interface is open. Subclass, replace, or write your own action without forking.

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
  @override String get description => 'Build Android APK & deploy to Pgyer';
  @override String get help => '...';

  @override
  PipelineContext createContext(List<String> args) =>
      MyAppContext(rawArgs: args);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CleanProjectAction());

    // Build artifact is stored on context.buildArtifact.
    await runAction(BuildAndroidAction(
      envName: 'test', buildType: AndroidBuildType.apk,
    ));
    await runAction(PgyerUploadAction(
      apiKey: (context as MyAppContext).pgyerApiKey,
      description: 'test build',
    ));

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

A pipeline decides internally what to build — there's no platform enum.
For an app that ships both Android and iOS, write two pipelines (e.g.
`android-test` and `ios-test`) or use a single pipeline that runs both
builds back-to-back.

## Usage

### 1. Define your PipelineContext

Subclass `PipelineContext` to bundle shared configuration (app name,
credentials, etc.) across all pipelines:

```dart
class MyAppContext extends PipelineContext {
  MyAppContext({super.rawArgs})
      : super(appName: 'MyApp', seedBuildNumber: 10000);

  String get pgyerApiKey => Platform.environment['PGYER_API_KEY'] ?? '';
  String get feishuWebhookUrl => Platform.environment['FEISHU_WEBHOOK_URL'] ?? '';
}
```

`rawArgs` carries the CLI args passed after the pipeline name through to
the context — see [CLI Arguments](#cli-arguments) below.

### 2. Create a BuildPipeline

Implement `body()` to compose actions. Use `runAction()` to execute each
step with automatic logging and error handling:

```dart
class MyPipeline extends BuildPipeline {
  @override String get name => 'test';
  @override String get description => '...';
  @override String get help => '...';

  @override
  PipelineContext createContext(List<String> args) =>
      MyAppContext(rawArgs: args);

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
dart run ci/build.dart test                 # run the 'test' pipeline
dart run ci/build.dart test --flavor=prod   # extra args pass through to the pipeline
dart run ci/build.dart                      # interactive selector
dart run ci/build.dart test --help          # pipeline-specific help
```

## CLI Arguments

Everything after the pipeline name is forwarded to the pipeline via
`createContext(args)`. Store it on the context as `rawArgs` (the
`PipelineContext` base supports this directly) and read it through the
built-in `ArgsParser`:

```dart
@override
Future<void> body() async {
  final flavor = context.args.getOption('flavor') ?? 'dev';
  final dryRun = context.args.has('--dry-run');

  await runAction(BuildAndroidAction(
    envName: flavor,
    buildType: AndroidBuildType.apk,
  ));
  if (!dryRun) await runAction(PushBuildTagAction());
}
```

`ArgsParser` handles three common patterns: `has('--flag')`,
`getOption('key')` for `--key=value`, and `positional` for the first
non-flag argument. Pipelines are free to interpret args however they
like — no full arg-parsing framework imposed.

## API

| Symbol | Description |
|--------|-------------|
| `PipelineContext` | Shared config + runtime state (`appName`, `seedBuildNumber`, `rawArgs`, `args`, `git`, `buildNumber`, `buildArtifact`) |
| `BuildPipeline` | Abstract base: `beforeBuild → body → afterBuild` lifecycle, plus action tracking (`executedActions`, `allSucceeded`, `lastFailure`) |
| `PipelineAction<R>` | Abstract action unit; receives context, returns typed result; carries `status` / `duration` / `error` after running |
| `ActionStatus` | Enum: `success`, `failed`, `skipped`, `interrupted` |
| `BuildVersion` | Sealed type — `BuildVersionUnresolved` / `BuildVersionResolved` — guarding `context.buildNumber` |
| `PipelineRegistry` | Registers pipelines; handles CLI routing and interactive selection |
| `ArgsParser` | Minimal CLI parser: `has`, `getOption('key')` for `--key=value`, `positional` |
| `runStep` | Logs + times a pipeline step, rethrows on failure |
| `Logger` | Coloured stdout/stderr output |
| `ShellRunner` | Process runner with live streaming and capture |
| `GitManager` | Git status, branch, hash, commit history |
| `VersionManager` | `builds/*` git-tag-based build numbering |

Built-in actions include `ResolveBuildVersionAction`,
`CheckGitStatusAction`, `CleanProjectAction`, `BuildAndroidAction`,
`BuildIOSAction`, `PgyerUploadAction`, `PgyerUploadV2Action`,
`GooglePlayUploadAction`, `AppStoreUploadAction`, `FeishuBuildNotifyAction`,
`FeishuNotifyAction`, `SwapInfoPlistAction`, `PushBuildTagAction`,
and `RestoreWorkspaceAction`.

## Example

A complete consumer demo lives in [`example/`](./example/) — three pipelines
(test, prod, android-test), all deploy targets, and a Flutter app that displays
its own build metadata at runtime.
