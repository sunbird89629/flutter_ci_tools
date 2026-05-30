# Pipeline Reviewer

Review code changes in the flutter_ci_tools library for architectural consistency.

## When to Use

- After adding or modifying a Pipeline subclass
- After changing BuildPipeline or its dependencies
- After adding new deploy targets or build types
- After modifying any lib/src/ file

## Checklist

### 1. Dependency Injection

All dependencies must be injected via constructor, never instantiated internally.

```dart
// CORRECT: constructor injection
class MyPipeline extends BuildPipeline {
  MyPipeline() : super(config);
}

// WRONG: internal instantiation
class MyPipeline extends BuildPipeline {
  final git = DefaultGitManager(); // NO
}
```

Check that BuildPipeline subclasses pass dependencies through `super()`, not by creating their own instances.

### 2. Abstract Interface Compliance

Every abstract member of BuildPipeline must be overridden:

| Required Getter | Type |
|----------------|------|
| `name` | `String` |
| `description` | `String` |
| `help` | `String` |
| `envName` | `String` |
| `iosExportMethod` | `String` |
| `apiHost` | `String` |
| `androidBuildType` | `AndroidBuildType` |

| Required Method | Signature |
|----------------|-----------|
| `deployAndroid` | `Future<void> deployAndroid(File file)` |
| `deployIOS` | `Future<void> deployIOS(File file)` |

Optional overrides: `beforeBuild()`, `shouldSwapInfoPlist`

### 3. ShellRunner Usage

External process calls must go through ShellRunner, never direct Process.run:

```dart
// CORRECT
await shellRunner.run('fvm', ['flutter', 'clean']);

// WRONG
await Process.run('fvm', ['flutter', 'clean']);
```

### 4. Deploy Service Delegation

Upload and notification logic must use DeployService, not direct HTTP calls:

```dart
// CORRECT
await deployService.uploadToPgyer(filePath, apiKey);
await deployService.sendFeishuNotification(webhookUrl, message);

// WRONG
await http.post(Uri.parse('https://www.pgyer.com/apiv2/app/upload'), ...);
```

### 5. Barrel Export

Every public file in lib/src/ must be exported in lib/flutter_ci_tools.dart:

```dart
// lib/flutter_ci_tools.dart
export 'src/new_file.dart';  // Must exist if new_file.dart has public API
```

### 6. Enum Extensions

New enums should follow the pattern with a `label` getter:

```dart
enum DeployTarget {
  pgyer('Pgyer'),
  googlePlay('Google Play');

  final String label;
  const DeployTarget(this.label);
}
```

### 7. Test Pattern

Tests must use fakes, not mocks. Each fake implements the corresponding interface:

```dart
class _FakeGitManager implements GitManager {
  // Track calls with fields
  bool didRestore = false;

  @override
  Future<void> restoreWorkspace() async {
    didRestore = true;
  }
  // ... implement all interface methods
}
```

Test pipeline subclasses must override all abstract members and use no-op deploy methods:

```dart
class _TestPipeline extends BuildPipeline {
  _TestPipeline(super.config, {super.versionManager, super.gitManager, ...});

  @override
  String get name => 'test';
  // ... all overrides

  @override
  Future<void> deployAndroid(File file) async {} // no-op
  @override
  Future<void> deployIOS(File file) async {} // no-op
}
```

## Output Format

Report findings as:

```
PASS: [check name]
FAIL: [check name] -- [specific issue with file:line]
WARN: [check name] -- [suggestion]
```

End with a summary: total passed, failed, warnings.
