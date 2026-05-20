# Example App for `flutter_ci_tools` — Design

Date: 2026-05-20
Status: Approved (ready for implementation plan)

## Goal

Add an `example/` directory to `flutter_ci_tools` that demonstrates a real
consumer setup: a runnable Flutter app whose build/deploy is driven by
`flutter_ci_tools`, covering two environments and all four deploy targets
exposed by the package (Pgyer, Feishu notifications, Google Play, App Store).

## Why

The package's `README.md` currently shows fragments of usage. New users have no
end-to-end reference for:

- How to organize multiple `EnvBuilder` subclasses for different envs.
- How to wire `CIToolsConfig` credentials from environment variables.
- How to flow `BuildMetadata` (gitHash, branch, recentCommits) into the running
  app so it can be displayed at runtime.
- When to use the convenience `uploadAndNotify` vs calling `DeployService`
  methods directly.

A complete example is also a pub.dev convention.

## Scope

### In scope

- A self-contained Flutter app under `example/`.
- Two `EnvBuilder` subclasses (test, prod) demonstrating four deploy targets.
- Credential loading from `Platform.environment` with placeholder fallbacks.
- A runtime mechanism to write build metadata into a bundled asset and display
  it on an About page.
- An `example/README.md` explaining setup, env vars, and what to copy.

### Out of scope

- No changes to `lib/src/*.dart` in the main package.
- No exposing of `EnvBuilder._shellRunner` as protected.
- No tests inside `example/` (main package already covers the API surface).
- No `shouldSwapInfoPlist` / `buildPrepare` override demonstration.
- No GitHub Actions / Jenkinsfile / CI platform-specific files.

## Directory layout

```
example/
├── pubspec.yaml
├── README.md
├── .gitignore
├── lib/
│   ├── main.dart
│   └── build_info.dart
├── assets/
│   └── build_info.json
└── ci/
    ├── app_config.dart
    ├── build_info_writer.dart
    ├── test_env.dart
    ├── prod_env.dart
    └── build.dart
```

## File-by-file design

### `example/pubspec.yaml`

```yaml
name: flutter_ci_tools_example
description: Example app demonstrating flutter_ci_tools usage.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.4.0
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_ci_tools:
    path: ../
  flutter_test:
    sdk: flutter

flutter:
  assets:
    - assets/build_info.json
```

Notes:
- `flutter_ci_tools` is a **dev dependency** — CI tooling must not enter the
  production bundle.
- `path: ../` lets the example track the main package without publication.
- `publish_to: none` because the example itself is not a publishable package.

### `example/lib/main.dart`

Layout:
- `ExampleApp` (`StatelessWidget`) wraps a `MaterialApp`.
- `HomeShell` is a `StatefulWidget` with a bottom `NavigationBar` and an
  `IndexedStack` of two tabs (Counter, About). No state-management library.
- AppBar title: `"Example ($_env)"` where
  `const _env = String.fromEnvironment('ENV', defaultValue: 'dev')`.

Why `String.fromEnvironment('ENV')` rather than reading from
`build_info.json`: `EnvBuilder.buildIOS` already passes
`--dart-define=ENV=$envName`. The example continues that established
convention.

`CounterPage`: the standard Flutter template counter. Demonstrates that the app
is real and runnable even without the CI pipeline.

`AboutPage`: uses `FutureBuilder<BuildInfo>(future: BuildInfo.load(), ...)`.
On success, renders a `ListView` of `ListTile`s for env, buildName, buildNumber,
gitHash, branch, recentCommits. On error, shows a centred message:
`"build_info.json not populated — run dart run ci/build.dart <env> first"`.

This split (`FutureBuilder` rather than synchronous startup load) means the app
still runs cleanly without CI ever having been executed; only the About tab
shows the placeholder hint.

### `example/lib/build_info.dart`

```dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class BuildInfo {
  final String env;
  final String buildName;
  final int buildNumber;
  final String gitHash;
  final String branch;
  final String recentCommits;

  const BuildInfo({
    required this.env,
    required this.buildName,
    required this.buildNumber,
    required this.gitHash,
    required this.branch,
    required this.recentCommits,
  });

  factory BuildInfo.fromJson(Map<String, dynamic> json) => BuildInfo(
        env: json['env'] as String,
        buildName: json['buildName'] as String,
        buildNumber: json['buildNumber'] as int,
        gitHash: json['gitHash'] as String,
        branch: json['branch'] as String,
        recentCommits: json['recentCommits'] as String,
      );

  static Future<BuildInfo> load() async {
    final raw = await rootBundle.loadString('assets/build_info.json');
    return BuildInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
```

### `example/assets/build_info.json` (committed placeholder)

```json
{
  "env": "dev",
  "buildName": "0.0.0",
  "buildNumber": 0,
  "gitHash": "unknown",
  "branch": "unknown",
  "recentCommits": "(not built)"
}
```

Why commit a placeholder: avoids `flutter analyze` complaining about a missing
asset, lets a fresh clone `flutter run` immediately. The CI pipeline overwrites
this at build time; the overwrite is reverted by `GitManager.restoreWorkspace`
in `EnvBuilder.run()`'s `finally` block, so the repo stays clean.

### `example/ci/app_config.dart`

```dart
import 'dart:io';
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

const _placeholder = 'YOUR_VALUE_HERE';

String _env(String key) => Platform.environment[key] ?? _placeholder;

final exampleConfig = CIToolsConfig(
  appName: 'FlutterCIToolsExample',
  seedBuildNumber: 10000,
  pgyerApiKey: _env('PGYER_API_KEY'),
  feishuWebhookUrl: _env('FEISHU_WEBHOOK_URL'),
);

class ProdCredentials {
  static String get googlePlayPackageName => _env('GOOGLE_PLAY_PACKAGE_NAME');
  static String get googlePlayJsonKeyPath  => _env('GOOGLE_PLAY_JSON_KEY_PATH');
  static String get appStoreIssuerId       => _env('APP_STORE_ISSUER_ID');
  static String get appStoreApiKeyId       => _env('APP_STORE_API_KEY_ID');
  static String get appStoreApiKeyPath     => _env('APP_STORE_API_KEY_PATH');
}
```

Notes:
- `exampleConfig` is `final` (not `const`) because env vars are read at
  runtime. The main README shows `const myAppConfig` for the static case; the
  example README will explicitly note the difference.
- No pre-flight credential validation. When a credential is missing, the
  failure occurs at the actual deploy step (`uploadToPgyer` returns 401,
  `uploadToGooglePlay` throws `DeployException` if the JSON key file is
  missing). Letting the real failure surface is more educational than a
  custom error.

### Required environment variables

| Variable | Purpose | Used by |
|---|---|---|
| `PGYER_API_KEY` | Pgyer upload | test |
| `FEISHU_WEBHOOK_URL` | Feishu bot webhook | test + prod |
| `GOOGLE_PLAY_PACKAGE_NAME` | e.g. `com.example.flutter_ci_tools_example` | prod |
| `GOOGLE_PLAY_JSON_KEY_PATH` | Service Account JSON absolute path | prod |
| `APP_STORE_ISSUER_ID` | App Store Connect issuer UUID | prod |
| `APP_STORE_API_KEY_ID` | API Key ID | prod |
| `APP_STORE_API_KEY_PATH` | `.p8` file absolute path | prod |

### `example/ci/build_info_writer.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

Future<void> writeBuildInfo({
  required String env,
  required String buildName,
  required int buildNumber,
  required BuildMetadata metadata,
}) async {
  final json = {
    'env': env,
    'buildName': buildName,
    'buildNumber': buildNumber,
    'gitHash': metadata.gitHash,
    'branch': metadata.branch,
    'recentCommits': metadata.recentCommits,
  };
  await File('assets/build_info.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}
```

### `example/ci/test_env.dart`

```dart
import 'dart:io';
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'app_config.dart';
import 'build_info_writer.dart';

class TestEnvBuilder extends EnvBuilder {
  TestEnvBuilder() : super(exampleConfig);

  @override String get envName => 'test';
  @override String get iosExportMethod => 'ad-hoc';
  @override String get apiHost => 'https://api.test.example.com';

  @override
  Future<File> buildAndroid() async {
    await writeBuildInfo(
      env: envName, buildName: buildName,
      buildNumber: buildNumber, metadata: metadata,
    );
    final result = await Process.run('fvm', [
      'flutter', 'build', 'apk',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    if (result.exitCode != 0) {
      throw StateError('flutter build apk failed: ${result.stderr}');
    }
    return File('build/app/outputs/flutter-apk/app-release.apk');
  }

  @override
  Future<void> processArtifacts(File apk, File ipa) async {
    await uploadAndNotify(AppPlatform.android, apk);
    await uploadAndNotify(AppPlatform.ios, ipa);
  }
}
```

`uploadAndNotify` is the convenience path: it uploads to Pgyer + sends a Feishu
message in one call. That matches the test env's "share a link with QA" flow.

### `example/ci/prod_env.dart`

```dart
import 'dart:io';
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'app_config.dart';
import 'build_info_writer.dart';

class ProdEnvBuilder extends EnvBuilder {
  ProdEnvBuilder() : super(exampleConfig);

  @override String get envName => 'prod';
  @override String get iosExportMethod => 'app-store';
  @override String get apiHost => 'https://api.example.com';

  @override
  Future<File> buildAndroid() async {
    await writeBuildInfo(
      env: envName, buildName: buildName,
      buildNumber: buildNumber, metadata: metadata,
    );
    final result = await Process.run('fvm', [
      'flutter', 'build', 'appbundle',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    if (result.exitCode != 0) {
      throw StateError('flutter build appbundle failed: ${result.stderr}');
    }
    return File('build/app/outputs/bundle/release/app-release.aab');
  }

  @override
  Future<void> processArtifacts(File aab, File ipa) async {
    // Android → Google Play
    await DeployService.instance.uploadToGooglePlay(
      aab,
      packageName: ProdCredentials.googlePlayPackageName,
      jsonKeyPath: ProdCredentials.googlePlayJsonKeyPath,
    );
    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.android,
        target: DeployTarget.googlePlay,
      ),
    );

    // iOS → App Store
    await DeployService.instance.uploadToAppStore(
      ipa,
      issuerId: ProdCredentials.appStoreIssuerId,
      apiKeyId: ProdCredentials.appStoreApiKeyId,
      apiKeyPath: ProdCredentials.appStoreApiKeyPath,
    );
    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: AppPlatform.ios,
        target: DeployTarget.appStore,
      ),
    );
  }
}
```

Prod deliberately does **not** call `uploadAndNotify` — that helper is
hardcoded to Pgyer. The example shows that for production stores you reach
directly for `DeployService.instance.*` plus `buildFeishuMessage(...)`. This is
intentional teaching: the two paths exist for a reason.

### `example/ci/build.dart`

```dart
import 'dart:io';
import 'test_env.dart';
import 'prod_env.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run ci/build.dart <test|prod>');
    exit(64);
  }
  final builder = switch (args.first) {
    'test' => TestEnvBuilder(),
    'prod' => ProdEnvBuilder(),
    _ => throw ArgumentError('Unknown env: ${args.first}'),
  };
  await builder.run();
}
```

### `example/.gitignore`

Use the standard Flutter `.gitignore` template (generated by `flutter create`,
covers `.dart_tool/`, `build/`, `.flutter-plugins`,
`.flutter-plugins-dependencies`, `ios/Pods/`, `android/.gradle/`, etc.).

Notably, `assets/build_info.json` is **not** ignored — see the placeholder
discussion above.

### Platform directories (`android/`, `ios/`)

Required for `flutter build apk` / `flutter build ipa` to work. Scaffolded by
running `flutter create .` inside `example/` during initial implementation;
the generated `android/` and `ios/` directories are committed as-is (no
custom signing config, no native code changes).

### `example/README.md` outline

1. **What this shows** — one sentence: full Flutter app + two-env CI scripts +
   four deploy targets.
2. **Setup** — `cd example && flutter pub get`.
3. **Try the app without CI** — `flutter run`; About tab shows the
   "build_info.json not populated" hint.
4. **Run the CI pipeline** — environment variable table (the table above) +
   `dart run ci/build.dart test` / `dart run ci/build.dart prod`.
5. **What to copy into your own project** — the entire `ci/` directory is
   directly portable; the `lib/build_info.dart` + About page pattern is
   optional but recommended.
6. **Notes** — fvm assumption; `uploadAndNotify` vs direct `DeployService`
   choice; why `exampleConfig` is `final` not `const`.

## Key design decisions (recap)

| Decision | Reason |
|---|---|
| `example/` is its own pub package via `path: ../` | Matches pub.dev convention; user can copy as-is. |
| Two envs (test/prod), not three | Enough to demonstrate split + different deploy targets; minimal noise. |
| Test uses APK; prod uses AAB | Pgyer accepts APK; `uploadToGooglePlay` requires AAB. |
| Credentials via `Platform.environment` + placeholder | No silent fallbacks; failures surface at the real call site. |
| `buildInfo` written in `buildAndroid`, not `buildPrepare` | Appears under the "Build Android" step in logs; runs once before both platform builds (Android first). |
| Prod skips `uploadAndNotify` | Helper is hardcoded to Pgyer; prod shows the lower-level API. |
| No tests in `example/` | Main package already has 32 tests covering the API surface. |
| Placeholder `build_info.json` committed | First-clone `flutter run` works; CI overwrite is reverted by `restoreWorkspace`. |
| No changes to main package code | Keeps the example a pure consumer demo. |

## Risks / open questions

- **fvm assumption** in `buildAndroid`. The main package's `buildIOS` also
  hardcodes `fvm`, so the example mirrors it. README will call this out.
- **`build_info.json` overwrite not reaching `restoreWorkspace`**: if the
  pipeline fails before `restoreWorkspace`, the overwritten file is left
  dirty. Acceptable — the user will see it in `git status` and discard it.
  Not adding bespoke recovery for the example.
- **AAB path** `build/app/outputs/bundle/release/app-release.aab` assumes
  default flavor / build mode. If the user adds flavors later, they'll need
  to adjust. Documented as a note.

## Out of scope (recap)

- Modifying `lib/src/*.dart`.
- Exposing `EnvBuilder._shellRunner`.
- Writing tests inside `example/`.
- Demonstrating `shouldSwapInfoPlist` / `buildPrepare`.
- Providing GitHub Actions / Jenkins / GitLab CI files.
