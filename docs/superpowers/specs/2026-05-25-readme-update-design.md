# README Update Design

## Goal

Update `README.md` to reflect the new Pipeline/Action architecture after the
major refactoring that replaced `CIToolsConfig` + `EnvBuilder` with
`PipelineContext` + `BuildPipeline` + `PipelineAction`.

## Approach

**Example-first (Approach C):** Show a working pipeline upfront in "Quick Start",
then expand into step-by-step Usage, API table, and Example link.

## Structure

```
# flutter_ci_tools
  (one-liner description — updated to mention pipeline/action architecture)

## Quick Start
  1. Entry point — ci/build.dart (PipelineRegistry + register + run)
  2. Define a pipeline (BuildPipeline subclass with body() composing actions)

## Usage
  1. Define your PipelineContext (subclass with shared config)
  2. Create a BuildPipeline (implement body(), use runAction)
  3. Register & run (CLI examples: both platforms, single platform, interactive)

## API
  Table with 10 core symbols:
  - PipelineContext, BuildPipeline, PipelineAction<R>, PipelineRegistry
  - runStep, Logger, ShellRunner, GitManager, VersionManager, BuildMetadata

  One-paragraph list of all built-in actions (no individual rows).

## Example
  Link to example/ with brief description (three pipelines, all deploy targets).
```

## Removed from README

- **Debug section** ("Debug Your Build Script in VS Code") — move to
  `docs/debugging-vscode.md` with identical content (text + image references).

## Key Changes from Current README

| Old | New |
|-----|-----|
| `CIToolsConfig` | `PipelineContext` (subclass) |
| `EnvBuilder` with `buildAndroid()`/`buildIos()`/`processArtifacts()` | `BuildPipeline` with `body()` composing `PipelineAction`s |
| `DeployService` | Individual actions: `PgyerUploadAction`, `GooglePlayAction`, etc. |
| `AppPlatform` / `DeployTarget` enums in API table | `AppPlatform` kept; `DeployTarget` is now action-specific |
| No registry | `PipelineRegistry` for CLI routing + interactive selection |
| Step 4: Debug in README | Moved to `docs/debugging-vscode.md` |

## Files to Create/Modify

1. **Modify** `README.md` — rewrite per structure above
2. **Create** `docs/debugging-vscode.md` — move debug section from README
