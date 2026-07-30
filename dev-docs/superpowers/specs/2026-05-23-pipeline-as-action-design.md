# BuildPipeline as Pure Lifecycle Container Design

## Problem

`BuildPipeline` (lib/src/pipeline.dart) currently mixes three responsibilities:

1. **Lifecycle / configuration contract** — abstract getters (`name`, `description`, `help`, `envName`, `apiHost`, `iosExportMethod`, `androidBuildType`, `shouldSwapInfoPlist`) and hooks (`beforeBuild`, `deployAndroid`, `deployIOS`).
2. **Utility methods** — `runStep`, `buildFeishuMessage`, `buildPrepare`, `cleanProject`.
3. **Hard-coded build orchestration** — holds `AndroidBuilder / IOSBuilder / VersionManager / GitManager / ShellRunner`; private `_buildAndroid / _buildIOS`; three near-duplicate flow methods `run / runAndroidOnly / runIOSOnly` that hard-code the sequence `resolve version → metadata → git check → beforeBuild → buildPrepare → clean → build → deploy → push tag → restore`.

Meanwhile `PipelineAction` (lib/src/actions/pipeline_action.dart) is the clean opposite: just `name` and `run(context)`. Upload and notify steps are already Actions.

The inconsistency is concrete:
- Upload/notify = Action (typed unit of work, communicates through context).
- Build/clean/version/git = hard-coded in base class (communicates through private methods and fields).

This forces three near-duplicate flow methods, blocks new platforms or non-standard flows (e.g. deploy-only without build), and makes "subclass writes new pipeline" require understanding the base class's full orchestration.

## Goal

Make `BuildPipeline` a pure lifecycle container: it provides only the execution shell (lifecycle hooks + `PipelineContext` + logging helper). All concrete build / deploy / notification steps are `PipelineAction` instances that the subclass composes in its own `body()`.

## Non-goals

- Extending `AppPlatform` beyond `{ android, ios }`. Future macOS / Web support is a separate decision.
- Deleting the existing service classes (`VersionManager / GitManager / AndroidBuilder / IOSBuilder / ShellRunner`). They remain as Action internals.
- Changing the CLI surface (`prod / prod android / prod ios`) or interactive selector behaviour.
- Adding a generic dependency graph / DAG executor. The pipeline body remains a hand-written sequence.

## Design

### Core abstractions

```dart
abstract class PipelineAction<R> {
  String get name;
  Future<R> run(PipelineContext context);
}

class PipelineContext {
  PipelineContext({required this.config, required this.platforms});

  final CIToolsConfig config;
  final Set<AppPlatform> platforms;

  late int buildNumber;
  late BuildMetadata metadata;

  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }
  // The string-keyed store (set<T> / get<T> / tryGet<T> / has / remove<T>)
  // and the `_store` field are removed entirely.
}

abstract class BuildPipeline {
  BuildPipeline(this._config);
  final CIToolsConfig _config;
  late final PipelineContext context;

  String get name;
  String get description;
  String get help;

  Future<void> beforeBuild() async {}
  Future<void> body();
  Future<void> afterBuild() async {}

  Future<void> run(Set<AppPlatform> platforms) async {
    context = PipelineContext(config: _config, platforms: platforms);
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e, st) {
        Logger.error('afterBuild failed', e, st);
      }
    }
  }

  Future<R> runAction<R>(PipelineAction<R> action) =>
      runStep(action.name, () => action.run(context));
}

/// Top-level helper. Used by `runAction` and available to Actions that need
/// to log sub-steps. Behaviour identical to today's `runStep`.
Future<T> runStep<T>(String name, Future<T> Function() action) async { ... }
```

#### Notable changes vs. current base class

- Removed getters: `envName`, `apiHost`, `iosExportMethod`, `androidBuildType`, `shouldSwapInfoPlist`.
- Removed methods: `deployAndroid`, `deployIOS`, `cleanProject`, `buildPrepare`, `_buildAndroid`, `_buildIOS`, `buildFeishuMessage`, `runAndroidOnly`, `runIOSOnly`.
- Removed fields: `_versionManager`, `_gitManager`, `_shellRunner`, `_androidBuilder`, `_iosBuilder`.
- Added: `body()` abstract method, `afterBuild()` hook, `runAction<R>(action)` helper.
- `PipelineAction` becomes generic `PipelineAction<R>` so Actions can return typed outputs (e.g. `BuildAndroidAction` returns `File`).
- `PipelineContext.set<T> / get<T> / tryGet<T> / has / remove<T>` and `_store` are deleted.
- `run(Set<AppPlatform>)` replaces the three `run / runAndroidOnly / runIOSOnly` entry points.

### Data-flow rule (the "P3 line")

Everything that is a true global, set once and read many times, lives on `PipelineContext`: `config`, `platforms`, `buildName`, `buildNumber`, `metadata`. Actions read these directly from `context`.

Everything else — credentials, artifact paths, per-action options — flows through Action **constructor parameters** as typed values, and Action **return values** when downstream Actions need them.

There is no more string-keyed bag. The example:

```dart
// before
context.set<String>('artifact_path', aab.path);
context.set<String>('google_play_package_name', ...);
await GooglePlayUploadAction().run(context);

// after
final aab = await runAction(BuildAndroidAction(
  envName: 'prod',
  buildType: AndroidBuildType.appbundle,
));
await runAction(GooglePlayUploadAction(
  artifact: aab,
  packageName: ProdCredentials.googlePlayPackageName,
  jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
));
```

### Lifecycle and error handling

`run(Set<AppPlatform>)` is the only entry point. It executes:

1. Construct `PipelineContext` with config + platforms.
2. `await beforeBuild()` (subclass-overridable; default no-op).
3. `await body()` (subclass-implemented; the main pipeline).
4. In `finally`: `await afterBuild()` (subclass-overridable; default no-op).

If `body()` throws, the original exception propagates after `afterBuild()` runs. If `afterBuild()` itself throws, the error is logged and swallowed so it cannot mask the original failure.

`beforeBuild` is kept (though technically redundant under the new model) for symmetry with `afterBuild` and to give "preparation that must run before the main body" an explicit, conventional location.

### Action catalog

#### A. Build-lifecycle actions (new, extracted from base class)

| Action | Replaces | Constructor params | Returns |
|---|---|---|---|
| `ResolveBuildVersionAction` | `VersionManager.computeNextBuildNumber` + assignment to `context.buildNumber` | optional `versionManager` | `void` |
| `CollectMetadataAction` | `BuildMetadata.collect(_gitManager)` + assignment to `context.metadata` | optional `gitManager` | `void` |
| `CheckGitStatusAction` | `_gitManager.checkClean` | optional `gitManager` | `void` |
| `SwapInfoPlistAction` | `buildPrepare()` Info.plist rename block | none | `void` |
| `CleanProjectAction` | `cleanProject()` (`flutter clean` + `flutter pub get`) | optional `shellRunner` | `void` |
| `BuildAndroidAction` | `_buildAndroid()` | `envName`, `buildType: AndroidBuildType`, optional `androidBuilder` | `File` |
| `BuildIOSAction` | `_buildIOS()` | `envName`, `exportMethod`, optional `iosBuilder` | `File` |
| `PushBuildTagAction` | `_versionManager.pushNewBuildTag(...)` | optional `versionManager` | `void` |
| `RestoreWorkspaceAction` | `_gitManager.restoreWorkspace()` | optional `gitManager` | `void` |

Actions that mutate `PipelineContext` (`ResolveBuildVersionAction`, `CollectMetadataAction`) assign to the `late` fields on context. They are still typed `PipelineAction<void>` because their effect is observable on `context`, not through a return value — they belong to the same "set up context state" category as today's flow.

#### B. Deploy / upload actions (refactored to P3 shape)

| Action | Constructor params | Returns |
|---|---|---|
| `PgyerUploadAction` | `artifact: File`, `apiKey: String`, `description: String?` | `String` (download URL) |
| `GooglePlayUploadAction` | `artifact: File`, `packageName: String`, `jsonKeyPath: String` | `void` |
| `AppStoreUploadAction` | `artifact: File`, `issuerId: String`, `apiKeyId: String`, `apiKeyPath: String` | `void` |

`PgyerUploadAction` now returns the download URL by value; the previous `context.set('pgyer_url', ...)` indirection is removed.

#### C. Notification actions

| Action | Constructor params | Returns |
|---|---|---|
| `FeishuNotifyAction` | `message: String` | `void` |
| `FeishuBuildNotifyAction` (new) | `platform: AppPlatform`, `target: DeployTarget`, `downloadUrl: String?` | `void` |

`FeishuBuildNotifyAction.run(context)` reads `config / buildNumber / metadata` from context, formats the standard build-notification text (the logic previously in `BuildPipeline.buildFeishuMessage`), then delegates to `FeishuNotifyAction(message: ...).run(context)` internally. The low-level `FeishuNotifyAction` is kept for non-standard messages (errors, custom announcements).

### Why service classes are kept

`VersionManager / GitManager / AndroidBuilder / IOSBuilder / ShellRunner` survive the refactor as Action internals (typically injected via optional constructor parameter, e.g. `BuildAndroidAction({AndroidBuilder? androidBuilder})`). Reasons, in order of weight:

1. **Cohesion of related operations.** `GitManager` holds `checkClean / restoreWorkspace` and any future git commands together. Splitting them into Actions would scatter `git` shell calls across the codebase.
2. **Cross-Action reuse.** `GitManager` is used by both `CheckGitStatusAction` and `RestoreWorkspaceAction`; `ShellRunner` is used by nearly every Action. The service layer prevents copy-paste.
3. **Action stays a thin shell.** Each Action's `run()` is "read context → bind constructor params → delegate to service". Inlining the service would inflate Actions back into the same kind of class the refactor is removing.
4. **Layered abstraction.** `shell → service → Action → pipeline body` — each layer is exactly one step higher than the one below it. The layering is itself a maintainability property, not a testing convenience.

Testability is a side-effect of these choices, not the justification.

### Subclass form

```dart
class ProdPipeline extends BuildPipeline {
  ProdPipeline() : super(exampleConfig);

  @override String get name => 'prod';
  @override String get description => '构建并部署到生产环境 (Google Play / App Store)';
  @override String get help => '...';

  @override
  Future<void> beforeBuild() async {
    await writeBuildInfo(
      env: 'prod',
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      metadata: context.metadata,
    );
  }

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());
    await runAction(CleanProjectAction());

    if (context.platforms.contains(AppPlatform.android)) {
      final aab = await runAction(BuildAndroidAction(
        envName: 'prod',
        buildType: AndroidBuildType.appbundle,
      ));
      await runAction(GooglePlayUploadAction(
        artifact: aab,
        packageName: ProdCredentials.googlePlayPackageName,
        jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
      ));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ));
    }

    if (context.platforms.contains(AppPlatform.ios)) {
      final ipa = await runAction(BuildIOSAction(
        envName: 'prod',
        exportMethod: 'app-store',
      ));
      await runAction(AppStoreUploadAction(
        artifact: ipa,
        issuerId: ProdCredentials.appStoreIssuerId,
        apiKeyId: ProdCredentials.appStoreApiKeyId,
        apiKeyPath: ProdCredentials.appStoreApiKeyPath,
      ));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ));
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

### CLI and registry

`PipelineRegistry.run(args)` continues to parse:
- `dart run ci/build.dart <name>` → `pipeline.run({android, ios})`
- `dart run ci/build.dart <name> android` → `pipeline.run({android})`
- `dart run ci/build.dart <name> ios` → `pipeline.run({ios})`
- No args → interactive selector → `pipeline.run({android, ios})`

The registry's only internal change: it no longer calls `runAndroidOnly` / `runIOSOnly`; it builds a `Set<AppPlatform>` and calls `run(set)`.

### Logging contract

`Action.name` becomes the sole source of the log section header. `runAction(action)` prints `▶ ${action.name}` and the completion line. Each Action gets its own section — there is no longer a coarser "Deploy Android" wrapper. Action `name` strings should be reviewed during implementation to read well as section headers (e.g. `'Build Android'`, `'Upload to Google Play'`, `'Send Feishu Notification'`).

Actions that want to subdivide their own work may call `runStep('Sub Step', () => ...)` directly — `runStep` remains a top-level function, not locked to `BuildPipeline`.

### File / type reorganization

- `AppPlatform` enum: stays near `BuildPipeline` (likely `lib/src/pipeline.dart` or extracted to `lib/src/pipeline_context.dart`). It is referenced by `PipelineContext.platforms`, so its home is the base layer.
- `DeployTarget` enum: moves to `lib/src/actions/feishu_build_notify_action.dart`. It is purely a label-bearing enum for Feishu notification formatting; placing it next to its consumer reflects its real scope.
- `AndroidBuildType` enum: moves to `lib/src/actions/build_android_action.dart`. It only configures Android build output.
- Old `pipeline.dart`: shrinks to `BuildPipeline` + `AppPlatform` + the top-level `runStep<T>`. All other content migrates out.

## Migration path

Phased rollout (`M2`):

1. **Add the new Action classes** with no base-class changes. Tests for each new Action are added in this step. The old `BuildPipeline` flow continues to work unchanged.
2. **Introduce the new base class shape** (`body / afterBuild / run(Set<AppPlatform>)` and `runAction`) alongside the old surface. Mark `run() / runAndroidOnly() / runIOSOnly()` and the old getters as deprecated. CI still green because subclasses still build.
3. **Update `PipelineRegistry`** to call `run(Set<AppPlatform>)` instead of the per-platform methods.
4. **Migrate the three example pipelines** (`TestPipeline`, `ProdPipeline`, `AndroidTestPipeline`) to the new shape (override `body`, drop old getters / `deployAndroid` / `deployIOS`).
5. **Delete the deprecated surface** from `BuildPipeline`: old getters, old methods, old fields, `PipelineContext.set/get<T>`, top-level `buildFeishuMessage`, etc.

Each step is a separate commit so any single step is independently reviewable and revertable.

## Testing

Each Action has direct unit tests with a fake service (`AndroidBuilder`, `ShellRunner`, etc.) injected via constructor. `BuildPipeline` itself gets a small set of tests for the lifecycle guarantees:

- `body()` exception still triggers `afterBuild()`.
- `afterBuild()` exception is logged but does not propagate.
- `context.platforms` is set from the `run(...)` argument.

Existing `BuildPipeline` tests that exercised the old hard-coded flow will be deleted or rewritten as part of step 4-5 of the migration.

## Open questions resolved during brainstorming

1. **`Action.name` semantics**: accepted — `name` is the log section header, one section per Action; per-platform grouping disappears. Existing `name` strings will be reviewed during implementation.
2. **`AppPlatform` extension**: out of scope; remains `{ android, ios }`.
3. **`DeployTarget` and `AndroidBuildType` homes**: moved to their consumer Action files (see "File / type reorganization").
4. **`runStep` visibility**: stays a top-level function; `runAction` delegates to it; Actions may call it directly for sub-steps.
