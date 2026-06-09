# Dart Doc Checker

Check public API documentation coverage for flutter_ci_tools.

## When to Use

- Before publishing a new version to pub.dev
- After adding or modifying public API members
- When preparing a PR for review

## What to Check

### 1. Public Library Exports

Read `lib/flutter_ci_tools.dart` and verify all exported symbols have dartdoc.

### 2. Classes and Enums

Every public class, enum, and mixin must have a `///` doc comment:

```dart
/// Sends the standard "new build" message to Feishu.
///
/// Reads `context.buildName`, `context.buildNumber`, and `context.git` to
/// format the message text.
class FeishuBuildNotifyAction extends PipelineAction<void> {
```

### 3. Public Methods and Properties

Every public method and property getter/setter should have dartdoc:

```dart
/// Runs [action] wrapped in [runStep], records status and timing.
/// Returns the action's typed result.
Future<R> runAction<R>(PipelineAction<R> action) async {
```

### 4. Constructor Parameters

Named parameters should be documented in the constructor doc:

```dart
/// Creates a Pgyer upload action.
///
/// [apiKey] is the Pgyer API key for authentication.
/// [description] is an optional build description shown on Pgyer.
/// [artifact] optionally specifies the file to upload.
PgyerUploadAction({
  required this.apiKey,
  this.description,
  this.artifact,
});
```

### 5. Enum Values

Each enum value should have a doc comment:

```dart
enum DeployTarget {
  /// Pgyer beta distribution platform.
  pgyer('Pgyer'),

  /// Google Play Store.
  googlePlay('Google Play');
```

## Output Format

Report findings in this format:

```
## Dartdoc Coverage Report

### ✅ Well Documented
- `PipelineAction` - complete dartdoc
- `PipelineContext` - complete dartdoc

### ⚠️ Missing Documentation
- `SomeClass.method()` - no doc comment
- `AnotherEnum.value` - no doc comment

### 📊 Summary
- Total public API members: 42
- Documented: 38 (90%)
- Missing: 4
```

## Auto-Fix

If asked to fix, add appropriate dartdoc comments following the patterns above. Do NOT add placeholder comments like `/// Does something` — write meaningful descriptions.

## What NOT to Document

- Private members (`_prefixed`)
- Override methods that simply delegate (e.g., `@override String toString()`)
- Test-only classes
