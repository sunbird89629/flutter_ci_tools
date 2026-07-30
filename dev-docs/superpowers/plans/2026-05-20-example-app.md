# Example App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `example/` directory containing a runnable Flutter app whose build/deploy is driven by `flutter_ci_tools`, demonstrating two envs (test, prod) and all four deploy targets (Pgyer, Feishu, Google Play, App Store).

**Architecture:** `example/` is a self-contained Flutter package that depends on the parent via `path: ../`. Two `EnvBuilder` subclasses live under `example/ci/`. A bundled `assets/build_info.json` is written by the CI pipeline and read at runtime by an About page, demonstrating how `BuildMetadata` flows into the running app.

**Tech Stack:** Dart SDK ^3.4.0, Flutter ≥3.22.0, `flutter_ci_tools` (path dep), `fvm` for Flutter SDK pinning.

**Reference spec:** `docs/superpowers/specs/2026-05-20-example-app-design.md` — read it first if anything is ambiguous.

**No tests in `example/`** — see spec "Out of scope". Verification per task is via `dart analyze` / `flutter analyze`; final smoke test is `flutter build apk --debug` and `flutter run`.

---

## Task 1: Scaffold the Flutter project

**Files:**
- Create: `example/` (via `flutter create`)

- [ ] **Step 1: Run flutter create from repo root**

```bash
flutter create \
  --project-name flutter_ci_tools_example \
  --org com.example \
  --platforms android,ios \
  --no-pub \
  example
```

Expected: `example/` directory populated with `pubspec.yaml`, `lib/main.dart`, `android/`, `ios/`, `test/widget_test.dart`, `.gitignore`, etc.

- [ ] **Step 2: Remove the default widget test**

The spec explicitly excludes tests from `example/`.

```bash
rm example/test/widget_test.dart
rmdir example/test
```

Expected: no error.

- [ ] **Step 3: Verify directory structure**

```bash
ls example/
```

Expected output includes: `android/`, `ios/`, `lib/`, `pubspec.yaml`, `.gitignore`, `README.md` (will be overwritten later).

- [ ] **Step 4: Commit the scaffold**

```bash
git add example/
git commit -m "chore(example): scaffold Flutter project via flutter create"
```

---

## Task 2: Replace `pubspec.yaml` with the example's pubspec

**Files:**
- Modify: `example/pubspec.yaml`

- [ ] **Step 1: Overwrite `example/pubspec.yaml`**

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
  uses-material-design: true
  assets:
    - assets/build_info.json
```

- [ ] **Step 2: Run pub get**

```bash
cd example && flutter pub get
```

Expected: "Got dependencies!" with no errors. `flutter_ci_tools` resolves from `../`.

- [ ] **Step 3: Commit**

```bash
git add example/pubspec.yaml example/pubspec.lock
git commit -m "chore(example): pin flutter_ci_tools via path dep, declare build_info.json asset"
```

---

## Task 3: Create the placeholder `build_info.json`

**Files:**
- Create: `example/assets/build_info.json`

- [ ] **Step 1: Create the assets directory and placeholder file**

`example/assets/build_info.json`:

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

- [ ] **Step 2: Verify the asset is detected**

```bash
cd example && flutter pub get
```

Expected: no warnings about missing assets.

- [ ] **Step 3: Commit**

```bash
git add example/assets/build_info.json
git commit -m "feat(example): add placeholder build_info.json"
```

---

## Task 4: Create the `BuildInfo` model

**Files:**
- Create: `example/lib/build_info.dart`

- [ ] **Step 1: Write `example/lib/build_info.dart`**

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

- [ ] **Step 2: Run analyzer**

```bash
cd example && flutter analyze lib/build_info.dart
```

Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add example/lib/build_info.dart
git commit -m "feat(example): add BuildInfo model for runtime metadata"
```

---

## Task 5: Replace `lib/main.dart` with Counter + About app

**Files:**
- Modify: `example/lib/main.dart`

- [ ] **Step 1: Overwrite `example/lib/main.dart`**

```dart
import 'package:flutter/material.dart';

import 'build_info.dart';

const _env = String.fromEnvironment('ENV', defaultValue: 'dev');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_ci_tools example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Example ($_env)')),
      body: IndexedStack(
        index: _tab,
        children: const [CounterPage(), AboutPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add), label: 'Counter'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: 'About'),
        ],
      ),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('You have pushed the button this many times:'),
          Text('$_count', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => setState(() => _count++),
            icon: const Icon(Icons.add),
            label: const Text('Increment'),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BuildInfo>(
      future: BuildInfo.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'build_info.json not populated — '
                'run `dart run ci/build.dart <env>` first.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final info = snapshot.data!;
        return ListView(
          children: [
            _row('env', info.env),
            _row('buildName', info.buildName),
            _row('buildNumber', info.buildNumber.toString()),
            _row('gitHash', info.gitHash),
            _row('branch', info.branch),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('recent commits',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(info.recentCommits,
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        );
      },
    );
  }

  Widget _row(String label, String value) => ListTile(
        title: Text(label),
        subtitle: Text(value, style: const TextStyle(fontFamily: 'monospace')),
        dense: true,
      );
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd example && flutter analyze lib/
```

Expected: "No issues found!"

- [ ] **Step 3: Smoke test the app builds (debug)**

```bash
cd example && flutter build apk --debug
```

Expected: build succeeds. (This step also confirms the placeholder asset wiring works.)

- [ ] **Step 4: Commit**

```bash
git add example/lib/main.dart
git commit -m "feat(example): add Counter + About app reading build_info.json"
```

---

## Task 6: Create `ci/app_config.dart`

**Files:**
- Create: `example/ci/app_config.dart`

- [ ] **Step 1: Write `example/ci/app_config.dart`**

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
  static String get googlePlayJsonKeyPath => _env('GOOGLE_PLAY_JSON_KEY_PATH');
  static String get appStoreIssuerId => _env('APP_STORE_ISSUER_ID');
  static String get appStoreApiKeyId => _env('APP_STORE_API_KEY_ID');
  static String get appStoreApiKeyPath => _env('APP_STORE_API_KEY_PATH');
}
```

- [ ] **Step 2: Verify it imports cleanly**

Since `ci/` is not part of `lib/`, `flutter analyze` won't auto-cover it. Use `dart analyze` on the file directly:

```bash
cd example && dart analyze ci/app_config.dart
```

Expected: "No issues found!"

If `dart analyze` complains the file is not in pubspec, that's fine — the file gets analyzed once it's `import`ed by other files. Proceed regardless.

- [ ] **Step 3: Commit**

```bash
git add example/ci/app_config.dart
git commit -m "feat(example): add CI app config with env-var-driven credentials"
```

---

## Task 7: Create `ci/build_info_writer.dart`

**Files:**
- Create: `example/ci/build_info_writer.dart`

- [ ] **Step 1: Write `example/ci/build_info_writer.dart`**

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

- [ ] **Step 2: Verify analyzer**

```bash
cd example && dart analyze ci/build_info_writer.dart
```

Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add example/ci/build_info_writer.dart
git commit -m "feat(example): add writeBuildInfo helper"
```

---

## Task 8: Create `ci/test_env.dart`

**Files:**
- Create: `example/ci/test_env.dart`

- [ ] **Step 1: Write `example/ci/test_env.dart`**

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class TestEnvBuilder extends EnvBuilder {
  TestEnvBuilder() : super(exampleConfig);

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'ad-hoc';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  Future<File> buildAndroid() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
    final result = await Process.run('fvm', [
      'flutter',
      'build',
      'apk',
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

- [ ] **Step 2: Verify analyzer**

```bash
cd example && dart analyze ci/test_env.dart
```

Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add example/ci/test_env.dart
git commit -m "feat(example): add TestEnvBuilder (Pgyer + Feishu)"
```

---

## Task 9: Create `ci/prod_env.dart`

**Files:**
- Create: `example/ci/prod_env.dart`

- [ ] **Step 1: Write `example/ci/prod_env.dart`**

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'app_config.dart';
import 'build_info_writer.dart';

class ProdEnvBuilder extends EnvBuilder {
  ProdEnvBuilder() : super(exampleConfig);

  @override
  String get envName => 'prod';

  @override
  String get iosExportMethod => 'app-store';

  @override
  String get apiHost => 'https://api.example.com';

  @override
  Future<File> buildAndroid() async {
    await writeBuildInfo(
      env: envName,
      buildName: buildName,
      buildNumber: buildNumber,
      metadata: metadata,
    );
    final result = await Process.run('fvm', [
      'flutter',
      'build',
      'appbundle',
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

- [ ] **Step 2: Verify analyzer**

```bash
cd example && dart analyze ci/prod_env.dart
```

Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add example/ci/prod_env.dart
git commit -m "feat(example): add ProdEnvBuilder (Google Play + App Store + Feishu)"
```

---

## Task 10: Create `ci/build.dart` entry point

**Files:**
- Create: `example/ci/build.dart`

- [ ] **Step 1: Write `example/ci/build.dart`**

```dart
import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

import 'prod_env.dart';
import 'test_env.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run ci/build.dart <test|prod>');
    exit(64);
  }
  final EnvBuilder builder = switch (args.first) {
    'test' => TestEnvBuilder(),
    'prod' => ProdEnvBuilder(),
    _ => throw ArgumentError('Unknown env: ${args.first}'),
  };
  await builder.run();
}
```

- [ ] **Step 2: Run analyzer over the whole ci/ directory**

```bash
cd example && dart analyze ci/
```

Expected: "No issues found!"

- [ ] **Step 3: Smoke test entry-point argument parsing**

Run with no args and verify it exits 64 with the usage message:

```bash
cd example && dart run ci/build.dart
echo "exit=$?"
```

Expected stderr: `Usage: dart run ci/build.dart <test|prod>`
Expected: `exit=64`

(Don't run it with `test` or `prod` here — that would kick off the real pipeline and require credentials.)

- [ ] **Step 4: Commit**

```bash
git add example/ci/build.dart
git commit -m "feat(example): add ci/build.dart entry point"
```

---

## Task 11: Write `example/README.md`

**Files:**
- Modify: `example/README.md` (overwrite the `flutter create` default)

- [ ] **Step 1: Overwrite `example/README.md`**

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add example/README.md
git commit -m "docs(example): explain setup, env vars, and what to copy"
```

---

## Task 12: Final smoke verification

This task does not produce code — it verifies that the entire `example/`
package is in a healthy state.

- [ ] **Step 1: Run analyzer on the whole example**

```bash
cd example && flutter analyze
```

Expected: "No issues found!"

If any errors appear, fix them and re-run before proceeding.

- [ ] **Step 2: Confirm `flutter pub get` is clean**

```bash
cd example && flutter pub get
```

Expected: "Got dependencies!" with no warnings.

- [ ] **Step 3: Confirm debug APK still builds**

```bash
cd example && flutter build apk --debug
```

Expected: build succeeds.

- [ ] **Step 4: Confirm `dart run ci/build.dart` usage message works**

```bash
cd example && dart run ci/build.dart 2>&1 || true
```

Expected: `Usage: dart run ci/build.dart <test|prod>`

- [ ] **Step 5: Run the main package's tests to confirm nothing regressed**

```bash
dart test
```

Expected: all 32 tests pass.

(The main package and `example/` are independent, but this is cheap and
catches accidental edits to `lib/`.)

- [ ] **Step 6: Confirm working tree is clean**

```bash
git status
```

Expected: "nothing to commit, working tree clean" — all per-task commits
landed.

- [ ] **Step 7: Update the main `README.md` to point at the example**

Append the following line to the bottom of the repo-root `README.md`:

```markdown

## Example

A complete consumer demo lives in [`example/`](./example/) — two-env CI
pipeline, all four deploy targets, and a Flutter app that displays its own
build metadata at runtime.
```

- [ ] **Step 8: Commit the README pointer**

```bash
git add README.md
git commit -m "docs: link to example/ from main README"
```
