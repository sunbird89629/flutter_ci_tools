# Docs & Example Cleanup

**Date:** 2026-06-11
**Status:** Deferred
**Related:** [[2026-05-26-architecture-cleanup-design]]

## Motivation

项目经历多次重构后（`BuildPipeline` → `Pipeline`、`runStep` 删除、`description` → `buildUpdateDescription`、artifact 返回值模式），README 和 example 中有多处过时引用，容易误导新用户。

## 问题清单

### README.md

- [ ] 代码示例中 `class TestPipeline extends BuildPipeline` 应改为 `extends Pipeline`
- [ ] API 表中删除 `runStep` 条目
- [ ] `PgyerUploadAction` 示例中 `description:` 应改为 `buildUpdateDescription:`
- [ ] 示例还在用 `context.buildArtifact` 老模式，应更新为 Action 直接 return File 的模式
- [ ] 执行摘要输出示例中 `ResolveBuildVersionAction` 等完整类名太冗长，实际现在是 `action.name`

### Example 项目

- [ ] `test_env_pipeline.dart` 硬编码了 pgyerApiKey 和 feishuWebhookUrl（安全问题，应使用 env var）
- [ ] `example/README.md` 中引用了 `BuildPipeline`（已改名）
- [ ] 补充 `beforeBuild` 的使用示例
- [ ] `build_info.dart` 文件不在 example/lib 中？需确认

### 其他

- [ ] `doc/` 目录只有一个 `debugging-vscode.md`，缺少使用指南
- [ ] pub.dev 展示页缺少 screenshots 或 GIF
