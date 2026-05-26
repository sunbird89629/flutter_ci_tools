# Action-Level Status Tracking Design

**Date:** 2026-05-26
**Status:** Deferred (after architecture cleanup)
**Related:** [[2026-05-26-architecture-cleanup-design]]

## Motivation

当前 `runStep()` 在每个 Action 执行时打日志、计时、标记成功/失败，但这些信息只输出到终端，没有结构化存储。这导致：

1. **失败时无法快速定位** — 终端输出滚动后，很难回溯是哪个 Action 失败的
2. **afterBuild 无法感知执行状态** — 比如想根据"构建成功还是失败"发送不同的通知，目前做不到
3. **无法比较两次执行** — 调试时想知道"上次成功这次失败"的差异，只能靠肉眼看日志

## Design

### 核心类型定义

```dart
/// Action 执行状态。
enum ActionStatus {
  /// 执行成功。
  success,

  /// 执行失败（抛出异常）。
  failed,

  /// 被跳过（条件不满足或用户选择）。
  skipped,

  /// 被用户中断（Ctrl+C）。
  interrupted,
}

/// 单个 Action 的执行结果。
class ActionResult {
  ActionResult({
    required this.name,
    required this.status,
    required this.duration,
    this.error,
    this.stackTrace,
  });

  /// Action 名称（来自 PipelineAction.name）。
  final String name;

  /// 执行状态。
  final ActionStatus status;

  /// 执行耗时。
  final Duration duration;

  /// 如果失败，异常信息。
  final Object? error;

  /// 如果失败，堆栈信息。
  final StackTrace? stackTrace;
}
```

### 存储位置

推荐放在 **PipelineContext** 上：

```dart
class PipelineContext {
  // ... 已有字段 ...

  final List<ActionResult> actionResults = [];

  /// 获取最后一个失败的 Action（如果没有失败则返回 null）。
  ActionResult? get lastFailure =>
      actionResults.lastWhereOrNull((r) => r.status == ActionStatus.failed);

  /// 是否所有 Action 都成功。
  bool get allSucceeded =>
      actionResults.every((r) => r.status == ActionStatus.success);
}
```

备选方案：放在 Pipeline 上。但 Pipeline 不是 `runStep()` 的参数，而 PipelineContext 是——放在 Context 上更自然。

### 与 runStep 集成

当前 `runStep()` 的实现：

```dart
Future<T> runStep<T>(String name, Future<T> Function() action) async {
  Logger.section(name);
  final stopwatch = Stopwatch()..start();
  try {
    final result = await action();
    stopwatch.stop();
    Logger.success('$name (${stopwatch.elapsed.inSeconds}s)');
    return result;
  } catch (e) {
    stopwatch.stop();
    Logger.error('$name failed', e);
    rethrow;
  }
}
```

改造后：

```dart
Future<T> runStep<T>(
  String name,
  Future<T> Function() action,
  PipelineContext context,
) async {
  Logger.section(name);
  final stopwatch = Stopwatch()..start();
  try {
    final result = await action();
    stopwatch.stop();
    Logger.success('$name (${stopwatch.elapsed.inSeconds}s)');
    context.actionResults.add(ActionResult(
      name: name,
      status: ActionStatus.success,
      duration: stopwatch.elapsed,
    ));
    return result;
  } catch (e, stackTrace) {
    stopwatch.stop();
    Logger.error('$name failed', e);
    context.actionResults.add(ActionResult(
      name: name,
      status: ActionStatus.failed,
      duration: stopwatch.elapsed,
      error: e,
      stackTrace: stackTrace,
    ));
    rethrow;
  }
}
```

### 汇总表输出

Pipeline 执行完成后（无论成功失败），打印汇总表：

```dart
void _printSummary(PipelineContext context) {
  const sep = '────────────────────────────────────';
  Logger.info(sep);
  Logger.info('执行摘要');
  Logger.info(sep);
  for (final result in context.actionResults) {
    final icon = switch (result.status) {
      ActionStatus.success => '✅',
      ActionStatus.failed => '❌',
      ActionStatus.skipped => '⏭️',
      ActionStatus.interrupted => '🛑',
    };
    final time = '${result.duration.inSeconds}s';
    Logger.info('$icon ${result.name} ($time)');
  }
  Logger.info(sep);

  final failure = context.lastFailure;
  if (failure != null) {
    Logger.error('失败: ${failure.name}', failure.error);
  }
}
```

输出示例：

```
────────────────────────────────────
执行摘要
────────────────────────────────────
✅ 检查 Git 状态 (0s)
✅ 解析构建版本 (1s)
✅ 收集元数据 (2s)
✅ 清理项目 (15s)
✅ 构建 Android (45s)
❌ 上传到蒲公英 (12s)
────────────────────────────────────
失败: 上传到蒲公英
DeployException: Upload failed after 3 attempts
```

### afterBuild 感知状态

```dart
@override
Future<void> afterBuild() async {
  if (context.allSucceeded) {
    await runAction(PushBuildTagAction());
  } else {
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: '...',
      platform: AppPlatform.android,
      target: DeployTarget.pgyer,
      // 可以根据状态做不同处理
    ));
  }
  await runAction(RestoreWorkspaceAction());
}
```

## 关键设计决策

**1. ActionResult 放在 Context 还是 Pipeline？**

推荐 Context。理由：
- `runStep()` 已经接收 PipelineContext 作为参数（改造后）
- afterBuild 可以直接通过 `context.actionResults` 访问
- 如果放 Pipeline，需要额外传递引用

**2. 是否支持 skipped 状态？**

当前架构没有条件跳过 Action 的机制（body() 中用 if 判断）。`skipped` 状态为未来预留——如果引入声明式依赖验证，不满足依赖的 Action 可以被标记为 skipped。

**3. 是否持久化执行结果？**

不持久化。每次 pipeline 运行都是独立的，结果存在内存中即可。如果需要历史记录，用户可以在 afterBuild 中自行写入文件。

## 实现顺序

这个特性依赖 architecture cleanup 中对 `runStep()` 的调整。建议在 0.2.0 发布后作为后续版本实现。

## 待决问题

- [ ] `runStep()` 签名变更是否需要向后兼容？（用户可能自定义了 Pipeline 并调用 `runStep`）
- [ ] 汇总表是否应该在 `run()` 方法中自动打印，还是作为可选功能？
- [ ] `ActionResult` 是否需要暴露为公共 API，还是仅在 Pipeline 内部使用？
