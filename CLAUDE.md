# flutter_ci_tools

Dart package for reusable Flutter CI tooling — build orchestration, git versioning, deploy services, and structured logging. Published to pub.dev.

## Architecture

- **Pipeline** — orchestrates a sequence of Actions (`beforeBuild` → `body` → `afterBuild`)
- **PipelineAction** — single-responsibility step (build, upload, notify, etc.)
- **PipelineContext** — shared mutable state passed through all actions (buildNumber, metadata, buildArtifact)
- **PipelineRegistry** — CLI router, dispatches to named pipelines

Each pipeline is a user-authored `BuildPipeline` subclass. Pipelines decide internally what to build — no platform enum.

## Key Conventions

- **Fakes, not mocks** — tests use hand-written `_Fake*` classes implementing interfaces directly
- **Constructor injection** — all dependencies (ShellRunner, GitManager, VersionManager) injected, never instantiated internally
- **Interface + Impl** — abstract interface in `foo.dart`, implementation in `foo_impl.dart`
- **Barrel export** — all public API exported from `lib/flutter_ci_tools.dart`
- **No relative imports** — use `package:flutter_ci_tools/...` in library code

## Testing

```bash
dart test                    # run all tests
dart test test/pipeline_test.dart  # run single file
```

Test files mirror lib structure: `test/actions/<name>_test.dart` for actions, `test/<name>_test.dart` for core classes.

## Commit Style

Conventional commits: `refactor:`, `docs:`, `feat:`, `fix:`, `test:`

## Docs

- Specs and plans in `docs/superpowers/specs/` and `docs/superpowers/plans/`
- Deferred designs in `docs/superpowers/specs/deferred/`

## Deferred Requirements

When discussing requirements and a feature is deferred (not implemented now), save the design doc to `docs/superpowers/specs/deferred/YYYY-MM-DD-<topic>-design.md` with status "Deferred". Use the same format as other spec files in `docs/superpowers/specs/`.
