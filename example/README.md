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

The **Counter** tab works immediately. The **About** tab shows the message
*"build_info.json not populated — run `dart run ci/build.dart <env>` first"*
until the CI pipeline has been executed at least once.

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
# Internal test build → Pgyer + Feishu notification
dart run ci/build.dart test

# Release build → Google Play + App Store + Feishu notification
dart run ci/build.dart prod
```

## What to copy into your own project

- The entire **`ci/`** directory is directly portable. Adjust:
  - `app_config.dart` — your `appName`, `seedBuildNumber`, env-var names
  - `test_env.dart` / `prod_env.dart` — your `apiHost`, build flavors,
    artifact paths
- The **`lib/build_info.dart` + About page** pattern is optional but useful
  for support: testers and users can read the exact build their app came
  from.

## Notes

- **`fvm` is assumed.** Build commands call `Process.run('fvm', ['flutter', ...])`.
  If you don't use `fvm`, change those calls to `Process.run('flutter', [...])`.
- **`uploadAndNotify` vs direct `DeployService` calls.** `TestEnvBuilder` uses
  the convenience `uploadAndNotify` (Pgyer + Feishu in one call).
  `ProdEnvBuilder` calls `DeployService.instance.uploadToGooglePlay` /
  `uploadToAppStore` directly, then `sendFeishuNotification` with a message
  built by `buildFeishuMessage(target: DeployTarget.googlePlay)` (or
  `appStore`). The helper exists for the common Pgyer case; for store
  uploads you reach one layer down.
- **`exampleConfig` is `final`, not `const`,** because env vars are read at
  runtime. The main package's `README.md` shows `const myAppConfig` for the
  static case.
- **AAB output path** assumes the default flavor and release build mode. Adjust
  in `prod_env.dart`'s `buildAndroid` if you add flavors.
