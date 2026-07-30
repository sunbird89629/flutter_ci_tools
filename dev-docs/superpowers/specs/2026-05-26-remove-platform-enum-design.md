# Remove AppPlatform Enum & writeBuildInfo

**Date:** 2026-05-26
**Scope:** Small refactoring — remove platform enum, simplify PipelineContext, delete unused code

## Motivation

1. `AppPlatform` 枚举限制了工具的扩展能力 — 平台应该是用户定义的，不是框架硬编码的
2. `PipelineContext.platforms` 增加了 context 的复杂度 — pipeline 应自行决定构建什么
3. `writeBuildInfo` 是 example app 特有逻辑，不属于框架，且增加了 context 字段的暴露需求
4. `FeishuBuildNotifyAction.platform` 参数耦合了平台枚举

CLI args 透传方案已设计但 deferred，见 [[2026-05-26-cli-args-passthrough-design]]。

## Changes

### 删除

| 文件 | 内容 |
|------|------|
| `example/ci/build_info_writer.dart` | 整个文件 |
| `lib/src/pipeline.dart` | `AppPlatform` 枚举 |
| `lib/src/pipeline_context.dart` | `platforms` 字段 |
| `lib/src/actions/feishu_build_notify_action.dart` | `platform` 字段、构造参数、import |
| `lib/src/pipeline_registry.dart` | `_parsePlatforms()` 方法 |

### 修改签名

**`BuildPipeline`** (`lib/src/pipeline.dart`)

```dart
// Before
PipelineContext createContext(Set<AppPlatform> platforms);
Future<void> run(Set<AppPlatform> platforms) async { ... }

// After
PipelineContext createContext();
Future<void> run() async { ... }
```

**`PipelineContext`** (`lib/src/pipeline_context.dart`)

```dart
// Before
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
  });
  final Set<AppPlatform> platforms;
  // ...
}

// After
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
  });
  // platforms removed
}
```

**`FeishuBuildNotifyAction`** (`lib/src/actions/feishu_build_notify_action.dart`)

```dart
// Before
FeishuBuildNotifyAction({
  required this.webhookUrl,
  required this.platform,
  required this.target,
  this.downloadUrl,
  ShellRunner? shellRunner,
});

// After
FeishuBuildNotifyAction({
  required this.webhookUrl,
  required this.target,
  this.downloadUrl,
  ShellRunner? shellRunner,
});
```

消息格式变更：

```dart
// Before
'🚀 ${context.appName} 新版本 ${context.buildNumber} (${platform.label} · ${target.label})'

// After
'🚀 ${context.appName} 新版本 ${context.buildNumber} (${target.label})'
```

**`PipelineRegistry`** (`lib/src/pipeline_registry.dart`)

```dart
// Before
final platforms = _parsePlatforms(args);
if (platforms == null) { ... }
await pipeline.run(platforms);

// After
await pipeline.run();
```

交互式选择同理：`await list[choice - 1].run();`

### Example Pipelines

**`TestPipeline`** / **`ProdPipeline`** — 移除 `context.platforms.contains(...)` 分支，硬编码两个平台都构建：

```dart
@override
Future<void> body() async {
  await runAction(ResolveBuildVersionAction());
  await runAction(CollectMetadataAction());
  await runAction(CheckGitStatusAction());
  await runAction(CleanProjectAction());

  // 硬编码：两个平台都构建
  await _buildAndroid();
  await _buildIos();

  await runAction(PushBuildTagAction());
}
```

`TestPipeline` 和 `ProdPipeline` 的 `_buildAndroid()` / `_buildIos()` 方法各自包含构建和部署逻辑。

**`AndroidTestPipeline`** — 保持只构建 Android，不受影响。

### 测试文件

所有测试中：
- `Set<AppPlatform>` 参数移除（`run({AppPlatform.android})` → `run()`）
- `platforms: <AppPlatform>{}` 从 `PipelineContext` 构造中移除
- `FeishuBuildNotifyAction` 测试移除 `platform: AppPlatform.android`
- 删除 `AppPlatform` 相关 import

## Implementation Order

1. 删除 `example/ci/build_info_writer.dart`
2. 从 `pipeline.dart` 删除 `AppPlatform` 枚举
3. 从 `PipelineContext` 删除 `platforms` 字段
4. 修改 `BuildPipeline.run()` 和 `createContext()` 签名
5. 从 `FeishuBuildNotifyAction` 删除 `platform` 参数
6. 简化 `PipelineRegistry`
7. 更新 example pipelines
8. 更新所有测试
9. 更新 barrel export（如有需要）
