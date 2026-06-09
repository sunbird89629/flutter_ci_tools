---
name: project-conventions
description: Project coding conventions and patterns for flutter_ci_tools
user-invocable: false
---

# flutter_ci_tools Project Conventions

This skill encodes the project's coding conventions for Claude to follow automatically.

## Architecture Patterns

### Pipeline/Action Pattern
- **Pipeline** orchestrates a sequence of Actions (`beforeBuild` → `body` → `afterBuild`)
- **PipelineAction** is a single-responsibility step (build, upload, notify, etc.)
- **PipelineContext** is shared mutable state passed through all actions
- **PipelineRegistry** is the CLI router, dispatches to named pipelines

### Dependency Injection
- All dependencies (ShellRunner, GitManager, VersionManager) injected via constructor
- Never instantiate dependencies internally
- Use `ShellRunner? shellRunner` optional parameter with `?? ShellRunnerImpl()` fallback

### Interface + Implementation
- Abstract interface in `foo.dart`
- Implementation in `foo_impl.dart`
- Example: `shell_runner.dart` (interface) + `shell_runner_impl.dart` (implementation)

## Code Style

### Imports
- Use package imports: `package:flutter_ci_tools/...`
- Never use relative imports in library code
- Test files can use relative imports for test utilities

### Naming
- Classes: PascalCase (`BuildAndroidAction`)
- Files: snake_case (`build_android_action.dart`)
- Private members: underscore prefix (`_shellRunner`)
- Constants: lowerCamelCase (`_defaultApiDomains`)

### Barrel Export
All public API must be exported from `lib/flutter_ci_tools.dart`:
```dart
export 'src/actions/build_android_action.dart';
export 'src/actions/build_ios_action.dart';
// ...
```

## Testing Conventions

### Fakes, Not Mocks
- Use hand-written `_Fake*` classes implementing interfaces directly
- Never use mock libraries (mockito, mocktail)
- Each fake records calls for verification

```dart
class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}
```

### Test File Structure
- Mirror lib structure: `test/actions/<name>_test.dart` for actions
- Core classes: `test/<name>_test.dart`
- Use `group()` for related tests
- Test names describe behavior, not implementation

### Test Coverage
For each Action, test:
1. **name getter** — verify expected string
2. **Happy path** — action succeeds
3. **Error handling** — throws appropriate exception
4. **Edge cases** — optional parameters, boundary conditions
5. **Context interaction** — reads/writes context fields correctly

## Commit Style

Use conventional commits:
- `feat:` — new feature
- `fix:` — bug fix
- `refactor:` — code change that neither fixes a bug nor adds a feature
- `docs:` — documentation only
- `test:` — adding or updating tests
- `chore:` — maintenance tasks
- `style:` — formatting, missing semicolons, etc.

## Documentation

### Dartdoc
- All public API members should have dartdoc comments
- Use `///` for public members
- Include usage examples for complex APIs
- Document constructor parameters in the class doc

### Design Docs
- Specs: `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans: `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- Deferred: `docs/superpowers/specs/deferred/YYYY-MM-DD-<topic>-design.md`

## Error Handling

### Exceptions
- Use `DeployException` for deployment-related errors
- Use `StateError` for invalid state access
- Use `GitException` for git operation failures

### Error Messages
- Include context in error messages
- Show what was expected vs what happened
- Include relevant values (file paths, API responses)

## File Organization

```
lib/
  src/
    actions/           # PipelineAction subclasses
      build_android_action.dart
      pgyer_upload_action.dart
      ...
    utils/             # Utility classes
      shell_runner.dart
      git_manager.dart
      ...
    pipeline.dart      # Pipeline base class
    pipeline_context.dart
    pipeline_registry.dart
  flutter_ci_tools.dart  # Barrel export

test/
  actions/             # Action tests
  utils/               # Utility tests
  pipeline_test.dart   # Pipeline tests
```
