# Test Writer

Generate tests for PipelineAction subclasses in flutter_ci_tools.

## When to Use

- After adding a new PipelineAction subclass
- After modifying an existing Action's behavior significantly
- When asked to write or improve tests

## Test Patterns

### File Location

Tests go in `test/actions/<action_name>_test.dart`, mirroring `lib/src/actions/`.

### Fake Classes (NOT Mocks)

This project uses hand-written fakes, never mock libraries. Each fake implements the interface directly:

```dart
class _FakeShellRunner implements ShellRunner {
  final Map<String, ShellResult> _responses = {};
  ShellResult? _fallback;
  final List<String> runCalls = [];

  void stub(String exe, List<String> args, ShellResult r) =>
      _responses['$exe ${args.join(' ')}'] = r;
  void stubAny(ShellResult r) => _fallback = r;

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final key = '$exe ${args.join(' ')}';
    runCalls.add(key);
    return _responses[key] ??
        _fallback ??
        ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}
```

### PipelineContext Helper

Create a helper function for building test contexts:

```dart
PipelineContext ctx() => PipelineContext(
  appName: 'TestApp',
  seedBuildNumber: 1000,
);
```

If the action needs `buildArtifact`, set it in the helper:

```dart
PipelineContext ctx() {
  final c = PipelineContext(
    appName: 'TestApp',
    seedBuildNumber: 1000,
  );
  c.setBuildArtifact(File('test.apk'));
  return c;
}
```

If the action needs `metadata`, set it in the helper:

```dart
PipelineContext ctx() {
  final c = PipelineContext(
    appName: 'TestApp',
    seedBuildNumber: 1000,
  )..metadata = BuildMetadata(
      branch: 'main',
      gitUser: 'Alice',
      gitHash: 'abc1234',
      recentCommits: 'commit1\ncommit2',
      commitBody: 'body',
    );
  return c;
}
```

### Test Structure

```dart
import 'package:flutter_ci_tools/src/actions/<action>.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:test/test.dart';

// Fake classes here

void main() {
  // Helper functions here

  test('<action> does X on success', () async {
    // Arrange: set up fakes and action
    // Act: run the action
    // Assert: verify behavior
  });

  test('<action> throws on error', () async {
    // Arrange: configure fake to fail
    // Act + Assert: expect throws
  });

  test('name is correct', () {
    // Verify the action.name getter
  });
}
```

### What to Test

For each Action, write tests covering:

1. **name getter** — verify it returns the expected string
2. **Happy path** — action succeeds with valid input
3. **Error handling** — action throws appropriate exception on failure
4. **Edge cases** — optional parameters, empty inputs, boundary conditions
5. **Context interaction** — if action reads/writes context fields, verify that

### Imports

Use library imports, not relative:

```dart
import 'package:flutter_ci_tools/src/actions/my_action.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:flutter_ci_tools/src/utils/exceptions.dart';
import 'package:test/test.dart';
```

## Output

Write the complete test file. Report:
- What was tested
- Any gaps or concerns
