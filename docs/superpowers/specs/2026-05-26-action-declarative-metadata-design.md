# Action Declarative Metadata Design

**Date:** 2026-05-26
**Status:** Deferred (after architecture cleanup)
**Related:** [[2026-05-26-architecture-cleanup-design]]

## Motivation

Currently, Action 类只暴露 `name` 和 `run()` 方法。用户要了解一个 Action 的用途、依赖和产出，必须阅读源码。这导致：

1. **CLI --help 无法自动生成** — PipelineRegistry 只能打印 pipeline 名称和描述，无法展示每个 Action 的详细信息
2. **运行时错误不友好** — 如果漏掉前置 Action（如 `ResolveBuildVersionAction`），得到的是 `StateError` 而非"你漏了哪一步"的提示
3. **API 文档需要手写** — pub.dev 上的文档只能靠手动维护的 dartdoc，无法从代码自动推导

## Design

### 方案：为 PipelineAction 增加声明式元数据属性

```dart
abstract class PipelineAction<R> {
  /// Action 的简短名称，用于日志和状态展示。
  String get name;

  /// Action 的详细描述，用于 --help 和文档。
  String get description;

  /// 这个 Action 依赖 PipelineContext 中的哪些字段。
  /// 用于运行前验证和文档生成。
  List<String> get requiredContext;

  /// 这个 Action 产出什么，用于文档生成。
  String get outputDescription;

  /// 执行 Action。
  Future<R> run(PipelineContext context);
}
```

### 具体 Action 示例

```dart
class BuildAndroidAction extends PipelineAction<void> {
  @override
  String get name => '构建 Android';

  @override
  String get description => '使用 fvm flutter build 构建 APK 或 AAB，产物存入 context.buildArtifact';

  @override
  List<String> get requiredContext => ['buildNumber', 'buildName'];

  @override
  String get outputDescription => 'context.buildArtifact — APK 或 AAB 文件';

  @override
  Future<void> run(PipelineContext context) async { ... }
}
```

```dart
class PgyerUploadAction extends PipelineAction<String> {
  @override
  String get name => '上传到蒲公英';

  @override
  String get description => '将构建产物上传到蒲公英分发平台，返回下载链接';

  @override
  List<String> get requiredContext => ['buildArtifact'];

  @override
  String get outputDescription => '下载 URL (String)';

  @override
  Future<String> run(PipelineContext context) async { ... }
}
```

```dart
class FeishuBuildNotifyAction extends PipelineAction<void> {
  @override
  String get name => '发送飞书构建通知';

  @override
  String get description => '向飞书群发送构建完成通知，包含版本号、分支、下载链接等';

  @override
  List<String> get requiredContext => ['buildNumber', 'buildName', 'metadata'];

  @override
  String get outputDescription => '无';

  @override
  Future<void> run(PipelineContext context) async { ... }
}
```

### 关键设计决策

**1. abstract getter vs 可选 mixin？**

推荐 **abstract getter**。理由：
- 强制所有 Action 提供元数据，保证一致性
- pub.dev 评分要求公共 API 有文档注释，abstract getter 天然强制
- 如果用 mixin，用户可能忘记实现，导致 --help 输出不完整

代价：每个 Action 需要多写 4 个 getter。但这正好是文档——一举两得。

**2. `requiredContext` 用 String 还是类型安全的枚举？**

推荐 **String**。理由：
- PipelineContext 的字段名本身就是 String（代码中的属性名）
- 枚举需要和 PipelineContext 字段同步维护，容易遗漏
- String 在运行前验证时可以给出清晰的错误信息："缺少 buildNumber，请先执行 ResolveBuildVersionAction"

**3. 运行前验证**

Pipeline 的 `run()` 方法可以在执行 `body()` 前，遍历所有已注册的 Action，检查它们的 `requiredContext` 是否会在 pipeline 中被满足。这需要 Action 声明自己的依赖，也需要知道哪些 Action 会提供哪些字段。

简化方案：不做编译期验证，只在运行时——当 `StateError` 被抛出时，利用 `requiredContext` 信息给出更好的错误提示。

## 用途

### 自动生成 --help

```dart
// PipelineRegistry 中
void printPipelineHelp(BuildPipeline pipeline) {
  print('${pipeline.name}: ${pipeline.description}');
  print('');
  for (final action in pipeline.actions) {
    print('  ${action.name}');
    print('    ${action.description}');
    print('    需要: ${action.requiredContext.join(", ")}');
    print('    产出: ${action.outputDescription}');
    print('');
  }
}
```

但这要求 Pipeline 暴露它会执行的 Action 列表——可能需要一个 `List<PipelineAction> get actions` getter。

### 改进的错误信息

```dart
int get buildNumber => switch (_buildVersion) {
  BuildVersionUnresolved() => throw StateError(
    'buildNumber 尚未解析。'
    '请确保 Pipeline body() 中包含 ResolveBuildVersionAction。'
    '\n\n提示: 以下 Action 需要 buildNumber: '
    '${_dependentActions("buildNumber").join(", ")}',
  ),
  BuildVersionResolved(:final value) => value,
};
```

## 实现顺序

这个特性依赖 architecture cleanup 完成后的 PipelineContext 和 Action 接口。建议在 0.2.0 发布后作为 0.3.0 的一部分实现。

## 待决问题

- [ ] Pipeline 是否需要暴露 `List<PipelineAction> get actions` 以支持 --help 生成？
- [ ] `requiredContext` 中的字符串是否需要标准化（如用常量而非字面量）？
