# PipelineContext Design

## Problem

BuildPipeline scatters mutable state across class fields: `config` (immutable), `buildNumber` (late, set in step 1), `metadata` (late final, set in step 2). There is no mechanism for steps to pass intermediate data to later steps (e.g., a deploy URL from Android that iOS notification needs). This couples data flow to class field layout and limits composability.

## Goal

Introduce a `PipelineContext` object that:
1. Encapsulates all pipeline state (`config`, `buildNumber`, `metadata`)
2. Provides a generic key-value store for inter-step data passing
3. Maintains type safety and the existing DI pattern

## Design

### PipelineContext Class

```dart
class PipelineContext {
  PipelineContext({required this.config});

  // Immutable
  final CIToolsConfig config;
  late BuildMetadata metadata;

  // Mutable state
  late int buildNumber;
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  // Generic store
  final Map<String, dynamic> _store = {};
  void set<T>(String key, T value) => _store[key] = value;
  T get<T>(String key) => _store[key] as T;
  T? tryGet<T>(String key) => _store[key] as T?;
  bool has(String key) => _store.containsKey(key);
  T? remove<T>(String key) => _store.remove(key) as T?;
}
```

**Mutability strategy:**
- `config`: immutable (`final`) -- set at construction, never changes
- `metadata`: `late`, set once in pipeline step 2, read-only thereafter by convention
- `buildNumber`: `late`, set once in pipeline step 1
- `_store`: fully mutable, grows as steps produce intermediate results

**Store API:** string keys with generic get/set. `get<T>` throws on missing key; `tryGet<T>` returns null. This lets callers choose strict vs. lenient access.

### BuildPipeline Integration

Remove the three fields from `BuildPipeline`:
- `final CIToolsConfig config` -> `context.config`
- `late int buildNumber` -> `context.buildNumber`
- `late final BuildMetadata metadata` -> `context.metadata`

Add:
- `final PipelineContext context` -- constructed in the constructor with `PipelineContext(config: config)`
- `String get buildName => context.buildName` -- proxy

Constructor changes:
```dart
BuildPipeline(
  CIToolsConfig config, {
  // ...same optional params
}) : context = PipelineContext(config: config),
    _versionManager = versionManager ?? DefaultVersionManager(),
    // ...
```

Pipeline step references update:
```dart
// before: config.seedBuildNumber
// after:  context.config.seedBuildNumber

// before: buildNumber = await _versionManager.computeNextBuildNumber(...)
// after:  context.buildNumber = await _versionManager.computeNextBuildNumber(...)

// before: metadata = await BuildMetadata.collect(...)
// after:  context.metadata = await BuildMetadata.collect(...)
```

### Subclass Impact

Subclasses change minimally:
- Constructor passes `CIToolsConfig` to `super()` (unchanged signature)
- Internal references add `context.` prefix: `context.config`, `context.metadata`, `context.buildName`
- `deployAndroid` / `deployIOS` signatures unchanged
- `uploadToPgyerAndNotify` updates internal refs to use `context.`

### Typical Store Usage

```dart
@override
Future<void> deployAndroid(File file) async {
  final url = await deployService.uploadToPgyer(file.path, ...);
  context.set<String>('android_download_url', url);
}

@override
Future<void> deployIOS(File file) async {
  final androidUrl = context.tryGet<String>('android_download_url');
  // reference in iOS notification
}
```

### Export

Add to barrel file:
```dart
export 'src/pipeline_context.dart';
```

## Files Changed

| File | Change |
|------|--------|
| `lib/src/pipeline_context.dart` | New file |
| `lib/src/pipeline.dart` | Remove 3 fields, add `context`, update all refs |
| `lib/flutter_ci_tools.dart` | Add export |
| `example/ci/pipelines/*.dart` | Add `context.` prefix to field access |
| `test/pipeline_test.dart` | Update to use `context` |

Files NOT changed: `shell_runner.dart`, `git_manager.dart`, `deploy_service.dart`, `version_manager.dart`, `config.dart`, `build_metadata.dart`, builders.

## Testing

- `PipelineContext` unit tests: construction, store get/set/tryGet/has/remove, buildName computation, late field access before init throws
- Existing pipeline tests: update field access to use `context.`, verify same behavior
