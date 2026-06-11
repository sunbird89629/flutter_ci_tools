## 0.0.3 (`5537664`)

### Bug Fixes

- **remove hardcoded secrets, redact logs, use HTTPS, harden shell execution**
  - Replace hardcoded Pgyer API key and Feishu webhook URL with env var reads
  - Redact sensitive args (`_api_key`, `password`, `secret`, `token`) in shell command logs
  - Move Pgyer API key from URL query param to POST form body
  - Mask App Store API key ID in log output
  - Use HTTPS instead of HTTP for Pgyer V2 API calls
  - Disable `runInShell` to prevent shell metacharacter injection
  - Use `Directory.systemTemp.createTempSync()` for secure temp file creation

## 0.0.2 (`48c8bde`)

### Breaking Changes

- `PipelineContext.buildNumber` is no longer a `late int` field. Use `resolveBuildVersion()` to set it; accessing before resolution throws `StateError` with a descriptive message.
- `BuildAndroidAction` and `BuildIOSAction` now return `void` instead of `File`. The build artifact is stored in `context.buildArtifact`.
- `PgyerUploadAction`, `PgyerUploadV2Action`, `GooglePlayUploadAction`, and `AppStoreUploadAction` no longer accept an `artifact` constructor parameter. They read from `context.buildArtifact` instead.
- `DefaultShellRunner` renamed to `ShellRunnerImpl`.
- `DefaultGitManager` renamed to `GitManagerImpl`.
- `DefaultVersionManager` renamed to `VersionManagerImpl`.

### Added

- `PipelineContext.buildArtifact` / `setBuildArtifact()` for passing build artifacts between actions.
- `BuildVersion` sealed type for type-safe build number state tracking.
- Dartdoc comments on all public API surfaces.

## 0.0.1 (`edecffb`)

- Initial release: Logger, ShellRunner, GitManager, VersionManager, BuildMetadata, DeployService, EnvBuilder (abstract), CIToolsConfig.
