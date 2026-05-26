# Architecture Cleanup Design

**Date:** 2026-05-26
**Scope:** Medium refactoring — fix Action coupling, prepare for pub.dev release
**Approach:** Progressive cleanup (Approach A) — keep Pipeline/Action/Context, improve internals

## Motivation

Two goals driving this refactoring:

1. **Action coupling** — `late` fields in PipelineContext cause runtime crashes if actions are skipped; data flow is inconsistent (some via context, some via return values)
2. **pub.dev readiness** — API naming consistency, dartdoc coverage, clean public surface

## Design Decisions

### 1. PipelineContext: Sealed Type for buildNumber

**Problem:** `late int buildNumber` throws `LateInitializationError` at runtime if `ResolveBuildVersionAction` is skipped. The error message is unhelpful.

**Solution:** Replace `late int buildNumber` with a sealed type that encodes the unresolved/resolved state.

```dart
sealed class BuildVersion {}
class BuildVersionUnresolved extends BuildVersion {}
class BuildVersionResolved extends BuildVersion {
  final int value;
  BuildVersionResolved(this.value);
}
```

PipelineContext changes:

```dart
class PipelineContext {
  final String appName;
  final int seedBuildNumber;
  final Set<AppPlatform> platforms;

  BuildVersion _buildVersion = BuildVersionUnresolved();

  int get buildNumber => switch (_buildVersion) {
    BuildVersionUnresolved() => throw StateError(
      'buildNumber 尚未解析。请确保先执行 ResolveBuildVersionAction。',
    ),
    BuildVersionResolved(:final value) => value,
  };

  void resolveBuildVersion(int version) {
    _buildVersion = BuildVersionResolved(version);
  }

  String get buildName => '1.0.$buildNumber';

  // metadata stays late — always initialized first in body()
  late BuildMetadata metadata;
}
```

**Why `late` stays for `metadata`:** `CollectMetadataAction` is always the first step in `body()`. The initialization pattern is fixed and the risk is negligible.

### 2. Data Flow Unification via PipelineContext

**Problem:** Action outputs travel two different paths:
- `buildNumber` / `metadata` → PipelineContext fields
- Build artifact (File) → return value, manually passed to next action's constructor

This inconsistency forces users to remember which data goes where.

**Solution:** All inter-action data flows through PipelineContext. Actions that produce results for other actions store them in context. Actions that produce results only for the caller can still return them.

**Add `buildArtifact` to PipelineContext:**

```dart
class PipelineContext {
  // ... existing fields ...

  File? _buildArtifact;

  File get buildArtifact => _buildArtifact ??
    throw StateError('buildArtifact 尚未设置。请先执行 BuildAndroidAction 或 BuildIOSAction。');

  void setBuildArtifact(File file) => _buildArtifact = file;
}
```

**Action changes:**

```dart
// Before: returns File
class BuildAndroidAction extends PipelineAction<File> {
  @override
  Future<File> run(PipelineContext context) async {
    final file = await _build(context);
    return file;
  }
}

// After: returns void, writes to context
class BuildAndroidAction extends PipelineAction<void> {
  @override
  Future<void> run(PipelineContext context) async {
    final file = await _build(context);
    context.setBuildArtifact(file);
  }
}

// Before: takes artifact as constructor param
class PgyerUploadAction extends PipelineAction<String> {
  final File artifact;
  PgyerUploadAction({required this.artifact, ...});
  @override
  Future<String> run(PipelineContext context) async {
    // uses this.artifact
  }
}

// After: reads from context
class PgyerUploadAction extends PipelineAction<String> {
  PgyerUploadAction({...});  // no more artifact param
  @override
  Future<String> run(PipelineContext context) async {
    final artifact = context.buildArtifact;
    // ...
  }
}
```

**User Pipeline body() before vs after:**

```dart
// Before
@override
Future<void> body() async {
  await runAction(ResolveBuildVersionAction(...));
  final apk = await runAction(BuildAndroidAction(...));
  final url = await runAction(PgyerUploadAction(artifact: apk, ...));
  await runAction(FeishuBuildNotifyAction(downloadUrl: url, ...));
}

// After
@override
Future<void> body() async {
  await runAction(ResolveBuildVersionAction(...));
  await runAction(BuildAndroidAction(...));
  final url = await runAction(PgyerUploadAction(...));
  await runAction(FeishuBuildNotifyAction(downloadUrl: url, ...));
}
```

**Convention:**
- Constructor parameters = credentials and infrastructure dependencies (apiKey, shellRunner, etc.)
- PipelineContext = inter-action data (buildNumber, metadata, buildArtifact)
- Return values = results only for the immediate caller (if any)

### 3. Utils Class Rename

**Problem:** `DefaultShellRunner`, `DefaultGitManager`, `DefaultVersionManager` use a `Default` prefix that is non-standard Dart naming.

**Solution:** Rename to `*Impl` suffix and reorganize files.

| Current | Renamed | File |
|---------|---------|------|
| `DefaultShellRunner` | `ShellRunnerImpl` | `shell_runner_impl.dart` (from `default_shell_runner.dart`) |
| `DefaultGitManager` | `GitManagerImpl` | `git_manager_impl.dart` (extracted from `git_manager.dart`) |
| `DefaultVersionManager` | `VersionManagerImpl` | `version_manager_impl.dart` (extracted from `version_manager.dart`) |

Each implementation gets its own file. The abstract interface stays in the original file.

**Export changes in `lib/flutter_ci_tools.dart`:**
```dart
// Before
export 'src/utils/default_shell_runner.dart';
// After
export 'src/utils/shell_runner_impl.dart';
```

### 4. Public API Dartdoc

Add dartdoc comments to all public API surfaces:

- `PipelineAction` — base class docs, type parameter explanation
- `BuildPipeline` — lifecycle docs, usage example
- `PipelineContext` — field descriptions, sealed type explanation
- `PipelineRegistry` — CLI usage docs
- `BuildMetadata` — field descriptions
- All 15 Action classes — purpose, constructor params, context reads/writes
- `ShellRunner`, `GitManager`, `VersionManager` — interface contracts
- `ShellRunnerImpl`, `GitManagerImpl`, `VersionManagerImpl` — when to use defaults
- `Logger` — available log levels
- Exception classes — when they're thrown

### 5. CHANGELOG and Example App

- Update CHANGELOG.md with breaking changes for new version
- Update example app to use renamed classes and new data flow pattern

## Implementation Order

1. PipelineContext sealed type + buildArtifact field
2. Update BuildAndroidAction, BuildIOSAction to write to context (return void)
3. Update PgyerUploadAction, PgyerUploadV2Action, GooglePlayUploadAction, AppStoreUploadAction to read from context
4. Rename Default* classes to *Impl
5. Reorganize files (extract implementations to separate files)
6. Update barrel export
7. Update all tests
8. Add dartdoc comments
9. Update example app
10. Update CHANGELOG

## Deferred (Future TODOs)

- **Task #9:** Action declarative metadata (requiredContext, outputDescription) — enables runtime dependency validation and auto-generated --help
- **Task #10:** Action-level status tracking (ActionResult, status table) — enables failure summary and conditional afterBuild logic
