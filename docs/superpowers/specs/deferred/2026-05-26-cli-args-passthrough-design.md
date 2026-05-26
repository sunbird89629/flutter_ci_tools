# CLI Args Pass-Through to PipelineContext

**Date:** 2026-05-26
**Status:** Deferred
**Related:** [[2026-05-26-architecture-cleanup-design]]

## Motivation

当前 `PipelineRegistry._parsePlatforms()` 硬编码了 "android"/"ios" 两个平台选项，限制了工具的扩展能力。用户期望：

1. **平台由用户定义** — 框架不定义平台枚举，用户传什么就是什么
2. **命令行参数透传** — pipeline 运行时能访问用户传入的所有原始参数
3. **pipeline 自行决策** — 每个 pipeline 决定如何解释这些参数

## Design

### 核心变更

`PipelineContext` 新增一个通用的命令行参数存储：

```dart
class PipelineContext {
  // ... 已有字段 ...

  /// 用户通过命令行传入的原始参数。
  ///
  /// 第一个参数是 pipeline 名称，后续参数由 pipeline 自行解释。
  /// 例如 `dart run ci/build.dart test android --debug`
  /// 会得到 `['test', 'android', '--debug']`。
  final List<String> rawArgs;
}
```

### PipelineRegistry 变更

```dart
// Before
Set<AppPlatform>? _parsePlatforms(List<String> args) {
  if (args.length <= 1) return AppPlatform.values.toSet();
  switch (args[1]) {
    case 'android': return {AppPlatform.android};
    case 'ios': return {AppPlatform.ios};
    default: return null;
  }
}

// After — 不再解析平台，直接透传
Future<void> run(List<String> args, ...) async {
  // ...
  await pipeline.run(args);  // 透传原始参数
}
```

### BuildPipeline 变更

```dart
abstract class BuildPipeline {
  // ...

  PipelineContext createContext(List<String> args);

  Future<void> run(List<String> args) async {
    context = createContext(args);
    try {
      await beforeBuild();
      await body();
    } finally {
      // ...
    }
  }
}
```

### Pipeline 自行解释参数

```dart
class TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(List<String> args) => ExampleAppContext(args: args);

  @override
  Future<void> body() async {
    // 自行决定构建哪些平台
    final platforms = context.args.where((a) => ['android', 'ios'].contains(a)).toSet();
    if (platforms.isEmpty || platforms.contains('android')) {
      // build android...
    }
    if (platforms.isEmpty || platforms.contains('ios')) {
      // build ios...
    }
  }
}
```

## 影响范围

- `PipelineContext` — 新增 `rawArgs` 字段
- `PipelineRegistry` — 删除 `_parsePlatforms()`，透传 args
- `BuildPipeline` — `run()` 和 `createContext()` 签名变更
- `PipelineAction` — `run()` 签名不变（仍接收 PipelineContext）
- 所有 Pipeline 子类 — 适配新的 `createContext()` 签名
- 所有测试 — 适配签名变更

## 待决问题

- [ ] `rawArgs` 是否应该暴露为 `Map<String, String>` 解析后的形式，还是保持原始 `List<String>`？
- [ ] 是否需要提供参数解析工具类（如 `ArgsParser`），还是让用户自行处理？
- [ ] 交互式选择模式下，args 为空列表，pipeline 需要有合理的默认行为
