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

A pipeline subclasses `Pipeline` and implements `body()` as an ordered list of
`PipelineAction`s. The base class provides the lifecycle shell
(`beforeBuild → body → afterBuild`) and a `runAction(...)` helper that wraps
each step with logging.

```dart
class ProdPipeline extends Pipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      ExampleAppContext(args: args);

  @override String get name => 'prod';
  @override String get description => '构建并部署到生产环境';
  @override String get help => '...';

  @override
  Future<void> body() async {
    // Writes ContextKeys.buildNumber — everything downstream depends on it.
    await runAction(ResolveBuildVersionAction());
    await runAction(CheckGitStatusAction());
    await runAction(SwapInfoPlistAction());     // prod-specific
    await runAction(CleanProjectAction());

    // Android
    await runAction(BuildAndroidAction(
      envName: 'prod', buildType: AndroidBuildType.appbundle,
    ));
    await runAction(GooglePlayUploadAction(
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: (context as ExampleAppContext).feishuWebhookUrl,
      target: 'Google Play',
    ));

    // iOS branch is symmetric — see ci/pipelines/prod_pipeline.dart.

    await runAction(PushBuildTagAction());
  }

  // Always runs, even if body() throws.
  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

Actions return nothing — they hand results to the next step through
`PipelineContext`'s string-keyed bag. `BuildAndroidAction` puts the artifact
under `ContextKeys.buildArtifact`, and `GooglePlayUploadAction` reads it from
there. Everything a pipeline needs beyond that (credentials, webhook URLs)
goes in through Action constructor params or a `PipelineContext` subclass like
`ExampleAppContext`.

## What to copy into your own project

- The entire **`ci/`** directory is directly portable. Adjust:
  - `app_config.dart` — your `ExampleAppContext` equivalent (`appName`,
    `seedBuildNumber`, webhook URL) and the `ProdCredentials` env-var names
  - `pipelines/*.dart` — pick which prelude / build / upload / notify
    Actions to compose for each of your environments. Use
    `android_test_pipeline.dart` (single platform, Pgyer) and
    `prod_pipeline.dart` (both platforms, store upload) as starting templates.
  - `build.dart` — registers the pipelines with `PipelineRegistry`.

## Notes

- **`fvm` is assumed.** `CleanProjectAction`, `BuildAndroidAction`, and
  `BuildIOSAction` shell out to `fvm flutter ...`. If you don't use `fvm`,
  inject a custom `ShellRunner` into those actions, or fork the action
  classes.
- **`ResolveBuildVersionAction` must come first in `body()`.** It writes
  `ContextKeys.buildNumber`, which the build and notify actions read. Without
  it they throw `StateError: missing key`.
- **Use `FeishuBuildNotifyAction` for standard build notifications,**
  `FeishuNotifyAction(message: ...)` for custom messages. The former extends
  the latter, overriding only `buildMessage()` to format the standard "new
  build" template — sending, retrying, and error handling are shared.
