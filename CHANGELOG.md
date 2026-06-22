## 0.0.6 (`57ab3ed`)

### ✨ Features

- `GooglePlayUploadAction` 新增可选 `File? artifact` 参数，支持并行上传时显式指定 AAB 文件 (`57ab3ed`)
- `AppStoreUploadAction` 新增可选 `File? artifact` 参数，支持并行上传时显式指定 IPA 文件 (`57ab3ed`)

## 0.0.5 (`3bb3c82`)

### ⚠️ Breaking Changes

- `PipelineAction.run()` 不再有泛型返回值 `R`，统一返回 `Future<void>`；action 间结果改走 `PipelineContext` KV bag (`3bb3c82`)
- `Logger` 从静态类改为实例类，支持 `verbose` / `noColor` / `indent`，需注入使用 (`d5acc13`)
- `buildNumber` / `buildArtifact` 迁移到 `PipelineContext` KV bag (`413f212`, `9abbc02`)
- Pgyer 的 `description` 重命名为 `buildUpdateDescription`，对齐 API 参数名 (`e73df8a`)

### ✨ Features

- `PipelineContext` 新增 KV bag（`put` / `get` / `tryGet`）与 `ContextKeys` (`66fd5d9`)
- 接入 `--verbose` 与 `--no-color` CLI 参数 (`754c3c7`)
- `PipelineAction` 新增 `description` getter，默认取 CamelCase 类名 (`6f71068`)

### ♻️ Refactoring

- Pgyer 通过 `resultKey` 把下载 URL 写入 bag，`FeishuBuildNotify` 读取 `downloadUrlKeys` (`c5d43e0`)
- `PipelineContext.logger` 贯穿各 action，`Pipeline` 增加 `section` / `closeSection` (`c8d67a3`)
- 向 `ShellRunnerImpl` / `GitManagerImpl` / `VersionManagerImpl` 注入 `Logger` (`f7a0905`, `6111dd8`)
- 移除 `runStep`，日志内联到 `Pipeline._runTracked` (`f12b2c3`)
- 移除 Logger 输出缩进 (`4a5204f`)

### 🐛 Bug Fixes

- 为 `GitManagerImpl` 单例和延迟的 `VersionManager` action 注入 `Logger` (`4d6d5d0`)

### 📚 Documentation

- KV bag 结果通道、多 key 下载 URL、日志改进的 spec 与实现计划 (`8825efa`, `6d0b109`, `cf4fa8f`, `b527077`, `e1fd33a`)

## 0.0.4 (`77fad57`)

### 🔧 Chores

- opt claude (`4d68973`)
- add Claude Code Review workflow agent (`d56f1c4`)
- add Claude PR Assistant workflow agent (`55c0deb`)

### 📚 Documentation

- add commit SHAs to CHANGELOG versions (`41c3a2c`)

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
