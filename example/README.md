# flutter_ci_tools example

A complete demo of how to consume `flutter_ci_tools` in a real Flutter app:
two envs (`test`, `prod`), four deploy targets (Pgyer, Feishu, Google Play,
App Store), and runtime display of build metadata.

## Setup

```bash
cd example
flutter pub get
```

## Try the app without CI

```bash
flutter run
```

The **Counter** tab works immediately. The **About** tab shows placeholder
build metadata ("dev", "0.0.0", "unknown", etc.) from the committed
`assets/build_info.json`. After the CI pipeline runs, real build info
(branch, git hash, recent commits) replaces the placeholder.

## Run the CI pipeline

The pipeline reads credentials from environment variables. Missing variables
fall back to the string `YOUR_VALUE_HERE`, which causes the actual deploy
call to fail with a clear error from the upstream service — no pre-flight
validation is performed.

| Variable | Purpose | Used by |
|---|---|---|
| `PGYER_API_KEY` | Pgyer upload | test |
| `FEISHU_WEBHOOK_URL` | Feishu bot webhook | test + prod |
| `GOOGLE_PLAY_PACKAGE_NAME` | e.g. `com.example.flutter_ci_tools_example` | prod |
| `GOOGLE_PLAY_JSON_KEY_PATH` | Service Account JSON absolute path | prod |
| `APP_STORE_ISSUER_ID` | App Store Connect issuer UUID | prod |
| `APP_STORE_API_KEY_ID` | API Key ID | prod |
| `APP_STORE_API_KEY_PATH` | `.p8` file absolute path | prod |

Then:

```bash
# Internal test build → Pgyer + Feishu notification (both platforms)
dart run ci/build.dart test

# Release build → Google Play + App Store + Feishu notification (both platforms)
dart run ci/build.dart prod

# Android-only test build (for debugging the CI scripts themselves)
dart run ci/build.dart android_test

# Single-platform variants of any pipeline
dart run ci/build.dart test android
dart run ci/build.dart prod ios

# Interactive selector (no args)
dart run ci/build.dart
```

## How a pipeline is built

A pipeline subclasses `BuildPipeline` and implements `body()` as an ordered
list of `PipelineAction`s. The base class provides the lifecycle shell
(`beforeBuild → body → afterBuild`) and a `runAction(...)` helper that wraps
each step with logging.

```dart
class ProdPipeline extends BuildPipeline {
  ProdPipeline() : super(exampleConfig);

  @override String get name => 'prod';
  @override String get description => '构建并部署到生产环境';
  @override String get help => '...';

  @override
  Future<void> body() async {
    // Prelude — populates context.buildNumber and context.metadata.
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CheckGitStatusAction());

    await runAction(SwapInfoPlistAction());     // prod-specific
    await runAction(CleanProjectAction());
    await writeBuildInfo(env: 'prod', ...);     // bundles build_info.json

    // Per-platform build + deploy. context.platforms is set by the CLI.
    if (context.platforms.contains(AppPlatform.android)) {
      final aab = await runAction(BuildAndroidAction(
        envName: 'prod', buildType: AndroidBuildType.appbundle,
      ));
      await runAction(GooglePlayUploadAction(artifact: aab, ...));
      await runAction(FeishuBuildNotifyAction(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ));
    }
    // iOS branch is symmetric — see ci/pipelines/prod_pipeline.dart.

    await runAction(PushBuildTagAction());
  }

  // Always runs, even if body() throws.
  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

Data flows through Action constructor params (`artifact: aab`) and return
values (`PgyerUploadAction.run` returns the download URL). `PipelineContext`
holds only the genuinely shared, read-only state: `config`, `platforms`, and
the lifecycle-populated `buildNumber` / `metadata`. There is no string-keyed
context store.

## What to copy into your own project

- The entire **`ci/`** directory is directly portable. Adjust:
  - `app_config.dart` — your `appName`, `seedBuildNumber`, env-var names
  - `pipelines/*.dart` — pick which prelude / build / upload / notify
    Actions to compose for each of your environments. Use `test_pipeline.dart`
    and `prod_pipeline.dart` as starting templates.
  - `build_info_writer.dart` — optional; emits `assets/build_info.json` so
    the running app can display its own build metadata.
- The **`lib/build_info.dart` + About page** pattern is optional but useful
  for support: testers and users can read the exact build their app came
  from.

## Notes

- **`fvm` is assumed.** `CleanProjectAction`, `BuildAndroidAction`, and
  `BuildIOSAction` shell out to `fvm flutter ...`. If you don't use `fvm`,
  inject a custom `ShellRunner` into those actions, or fork the action
  classes.
- **`exampleConfig` is `final`, not `const`,** because env vars are read at
  runtime. The main package's `README.md` shows `const myAppConfig` for the
  static case.
- **`writeBuildInfo` lives in `body()`, not `beforeBuild()`,** because it
  reads `context.buildName` / `buildNumber` / `metadata` — fields populated
  by `ResolveBuildVersionAction` and `CollectMetadataAction`, both of which
  run inside `body()`. Calling it from `beforeBuild` would throw
  `LateInitializationError`.
- **Use `FeishuBuildNotifyAction` for standard build notifications,**
  `FeishuNotifyAction(message: ...)` for custom messages. The former
  formats the standard "new build" template internally and delegates to
  the latter for the actual HTTP call.
