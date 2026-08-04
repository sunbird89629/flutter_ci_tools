## 0.1.3

### 🐛 Bug Fixes

- `FeishuBuildNotifyAction` 补上 `maxAttempts` / `retryDelay` 并透传给
  `FeishuNotifyAction`。此前这两个参数只存在于 `FeishuNotifyAction` 上，而所有
  流水线用的都是 `FeishuBuildNotifyAction`，等于**够不着**，只能吃默认值

## 0.1.2

### ♻️ Refactoring

- `FeishuNotifyAction` 去掉 curl 自带的 `--retry`：它会与外层重试相乘（3×3=9 次
  请求、最坏约 2.5 分钟），且内部重试静默、日志上看不出试了几次。改为只保留
  外层重试，请求数降到 3 次、最坏约 51 秒，每次失败都有明确日志

## 0.1.1

### ✨ Features

- `FeishuNotifyAction` 大幅加固：新增 `maxAttempts` / `retryDelay` 参数，curl 补上
  `-sS -f --connect-timeout 5 --max-time 15 --retry 2 --retry-connrefused`，
  并解析响应体识别飞书的「HTTP 200 + 非零 code」业务错误；webhook 为空时跳过。
  明确保证**永不抛异常**，通知失败不影响已产出的构建产物

### 🐛 Bug Fixes

- `pipeline_context_test` 不再写死版本号，改为校验 semver 形态（0.0.4 → 0.1.0 时曾误报失败）

## 0.1.0 (`5c0cac1`)

### ✨ Features

- `PgyerUploadV2Action` 新增 `maxRetries` 参数 (`900d7c3`)
- `GooglePlayUploadAction` / `AppStoreUploadAction` 新增 `maxRetries` 参数 (`00bc0a1`)

### 📚 Documentation

- README 新增 SVG hero、执行摘要与终端截图，嵌入 3 张截图并补充 status badges (#5, #6, #7, #8)
- 用户文档移至 `doc/`，开发计划移至 `dev-docs/` (`84a2a6d`)

### 🔧 Chores

- pubspec 补充 `homepage` / `issue_tracker` 字段，版本对齐为 0.1.0 (`5c0cac1`)

## 0.0.7 (`ba11c51`)

### ♻️ Refactoring

- `ShellRunner` 新增 `setLogger` 方法，支持延迟 Logger 注入；各 action 在 `run()` 开头调用 `_shellRunner.setLogger(context.logger)`，`ShellRunnerImpl` 不再要求构造时传入 Logger (`ba11c51`)

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
