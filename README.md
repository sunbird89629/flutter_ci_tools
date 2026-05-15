# flutter_ci_tools

Reusable CI tooling for Flutter apps. Provides build orchestration, git-tag-based versioning, deploy services (Pgyer, Feishu, Google Play, App Store), and structured terminal logging.

## Usage

### 1. Add to `pubspec.yaml`

```yaml
dev_dependencies:
  flutter_ci_tools: ^0.1.0
```

### 2. Define your app config

```dart
// ci/my_app_config.dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';

const myAppConfig = CIToolsConfig(
  appName: 'MyApp',
  seedBuildNumber: 10000,
  pgyerApiKey: 'YOUR_PGYER_KEY',          // optional
  feishuWebhookUrl: 'https://...',        // optional
);
```

### 3. Extend `EnvBuilder`

```dart
class TestEnvBuilder extends EnvBuilder {
  TestEnvBuilder() : super(myAppConfig);

  @override String get envName => 'test';
  @override String get iosExportMethod => 'ad-hoc';
  @override String get apiHost => 'https://api.test.example.com';

  @override
  Future<File> buildAndroid() async { /* flutter build apk ... */ }

  @override
  Future<void> processArtifacts(File apk, File ipa) async {
    await uploadAndNotify(AppPlatform.android, apk);
    await uploadAndNotify(AppPlatform.ios, ipa);
  }
}
```

### 4. Run

```bash
dart run ci/build.dart test
```

## API

| Symbol | Description |
|--------|-------------|
| `CIToolsConfig` | App-global config (seed build number, Pgyer/Feishu keys) |
| `EnvBuilder` | Abstract base with full `run()` orchestration |
| `runStep` | Logs + times a pipeline step, rethrows on failure |
| `Logger` | Coloured stdout/stderr output |
| `ShellRunner` | Process runner with live streaming and capture |
| `GitManager` | Git status, branch, hash, commit history |
| `VersionManager` | `builds/*` git-tag-based build numbering |
| `BuildMetadata` | Collects branch/user/hash/commits at build time |
| `DeployService` | Upload to Pgyer, Google Play, App Store; send Feishu messages |
| `AppPlatform` | `android` / `ios` |
| `DeployTarget` | `pgyer` / `googlePlay` / `appStore` |
