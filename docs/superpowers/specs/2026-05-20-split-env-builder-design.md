# Split EnvBuilder into Platform Builders + Pipeline

## Motivation

`EnvBuilder` currently builds both Android and iOS in one class. The fixed `run()` pipeline always builds both platforms, and build logic, deploy logic, and notification logic are all mixed in the same class hierarchy. This design has two problems:

1. **Can't build a single platform** — no way to say "just build Android today"
2. **Poor separation of concerns** — one class handles building, deploying, notifying, and pipeline orchestration

## Design

Split `EnvBuilder` into three layers:

- **AndroidBuilder / IOSBuilder** — pure, stateless builders that only run `flutter build` and return a `File`
- **BuildPipeline** — abstract orchestrator that holds shared state (buildNumber, metadata), coordinates the build-deploy flow, and provides deploy/notification helpers
- **Concrete pipelines** (TestPipeline, ProdPipeline) — provide env-specific config and deploy targets

### File Changes

```
lib/src/
├── env_builder.dart          → deleted
├── builders/
│   ├── android_builder.dart  → new
│   └── ios_builder.dart      → new
├── pipeline.dart             → new
├── config.dart               → unchanged
├── build_metadata.dart       → unchanged
├── deploy_service.dart       → unchanged
├── git_manager.dart          → unchanged
├── version_manager.dart      → unchanged
├── shell_runner.dart         → unchanged
├── logger.dart               → unchanged
└── exceptions.dart           → unchanged

example/ci/
├── prod_env.dart             → rewritten as ProdPipeline
├── test_env.dart             → rewritten as TestPipeline
├── build.dart                → updated entry point
├── app_config.dart           → unchanged
└── build_info_writer.dart    → unchanged
```

### AndroidBuilder

- Stateless, only dependency is `ShellRunner` (injectable)
- `buildApk({buildName, buildNumber, envName})` → `File` (APK)
- `buildAppBundle({buildName, buildNumber, envName})` → `File` (AAB)
- Does NOT: resolve versions, write build info, clean project, deploy, or notify

### IOSBuilder

- Stateless, only dependency is `ShellRunner` (injectable)
- `buildIpa({buildName, buildNumber, envName, exportMethod})` → `File` (IPA)
- Does NOT: resolve versions, clean project, deploy, or notify

### BuildPipeline (abstract)

Holds all shared state and dependencies via constructor injection:

- `config`, `versionManager`, `gitManager`, `deployService`, `shellRunner`
- `androidBuilder`, `iosBuilder`
- Shared state: `buildNumber`, `buildName` (derived), `metadata`

Abstract members (subclass provides):

- `envName`, `iosExportMethod`, `apiHost`
- `deployAndroid(File file)` — upload + notify for Android
- `deployIOS(File file)` — upload + notify for iOS
- `androidBuildType` — `apk` or `appbundle`
- `shouldSwapInfoPlist` (default `false`)
- `beforeBuild()` — hook for writeBuildInfo, swap Info.plist, etc.

Concrete helpers (provided by base):

- `run()` — full pipeline: version → metadata → git check → beforeBuild → clean → build Android → build iOS → deploy → push tag (with `runStep` wrapping each step)
- `runAndroidOnly()` — single-platform variant
- `runIOSOnly()` — single-platform variant
- `uploadToPgyerAndNotify(platform, file)` — Pgyer upload + Feishu notification
- `buildFeishuMessage({platform, target, downloadUrl})` — message formatting

### Concrete Pipelines

**TestPipeline:**
- `envName` = `test`, `iosExportMethod` = `development`, `androidBuildType` = `apk`
- `beforeBuild` → `writeBuildInfo()`
- `deployAndroid` → `uploadToPgyerAndNotify`
- `deployIOS` → `uploadToPgyerAndNotify`

**ProdPipeline:**
- `envName` = `prod`, `iosExportMethod` = `app-store`, `androidBuildType` = `appbundle`
- `shouldSwapInfoPlist` = `true`
- `beforeBuild` → `writeBuildInfo()` + swap Info.plist
- `deployAndroid` → Google Play upload + Feishu notify
- `deployIOS` → App Store upload + Feishu notify

### Entry Point

```dart
// build.dart
// Usage: dart run ci/build.dart <test|prod> [android|ios]
// Optional second argument enables single-platform builds
```

### Testability

- `AndroidBuilder` and `IOSBuilder` can be tested in isolation with a fake `ShellRunner`
- `BuildPipeline` can be tested with fake builders, version manager, git manager, and deploy service
- Existing test fakes (`_FakeVersionManager`, `_FakeGitManager`, `_FakeDeployService`, `_FakeShellRunner`) are reused

## What Stays the Same

- `CIToolsConfig`, `BuildMetadata`, `DeployService`, `GitManager`, `VersionManager`, `ShellRunner`, `Logger`
- `runStep()` helper (moves to `pipeline.dart`)
- `AppPlatform` and `DeployTarget` enums
- `findIpaFile()` logic (moves into `IOSBuilder`)
- `buildName` formatting logic
- `buildFeishuMessage()` formatting
- Pgyer upload with retry logic
