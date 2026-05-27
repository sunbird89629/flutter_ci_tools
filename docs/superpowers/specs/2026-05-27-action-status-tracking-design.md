# Action-Level Status Tracking Design

**Date:** 2026-05-27
**Status:** Approved
**Supersedes:** [[deferred/2026-05-26-action-status-tracking-design]]

## Motivation

当前 `runStep()` 在每个 Action 执行时打日志、计时、标记成功/失败，但这些信息只输出到终端，没有结构化存储。这导致：

1. **失败时无法快速定位** — 终端输出滚动后，很难回溯是哪个 Action 失败的
2. **afterBuild 无法感知执行状态** — 比如想根据"构建成功还是失败"发送不同的通知，目前做不到
3. **无法比较两次执行** — 调试时想知道"上次成功这次失败"的差异，只能靠肉眼看日志

## Design

### 核心枚举 — `lib/src/action_status.dart`

```dart
/// Action 执行状态。
enum ActionStatus {
  success,
  failed,
  skipped,
  interrupted,
}
```

独立文件，职责单一。通过 barrel export 导出为公共 API。

### PipelineAction 变更 — `lib/src/actions/pipeline_action.dart`

在 `PipelineAction<R>` 上增加可变执行状态字段：

```dart
abstract class PipelineAction<R> {
  String get name;

  // 执行状态（run 之后才有值）
  ActionStatus? status;
  Duration? duration;
  Object? error;
  StackTrace? stackTrace;

  /// 是否已执行过。
  bool get hasRun => status != null;

  Future<R> run(PipelineContext context);
}
```

**设计决策：状态存在 Action 上而非 PipelineContext**

- 每个 Action 自然拥有自己的 name、status、duration、error
- `afterBuild` 可以通过遍历 `executedActions` 查询结果
- 职责更内聚：Action 定义"做什么"，同时持有"做得怎样"
- PipelineContext 保持为构建配置/元数据的容器，不混入执行状态

### BuildPipeline 变更 — `lib/src/pipeline.dart`

#### 已执行 Action 列表

```dart
abstract class BuildPipeline {
  // ... 已有字段 ...

  /// 按执行顺序记录所有已执行的 Action。
  final List<PipelineAction> executedActions = [];

  /// 是否所有 Action 都成功。
  bool get allSucceeded =>
      executedActions.every((a) => a.status == ActionStatus.success);

  /// 最后一个失败的 Action，没有失败则返回 null。
  PipelineAction? get lastFailure =>
      executedActions.lastWhereOrNull((a) => a.status == ActionStatus.failed);
}
```

#### runAction — 计时 + 状态记录

```dart
Future<R> runAction<R>(PipelineAction<R> action) async {
  executedActions.add(action);
  final stopwatch = Stopwatch()..start();
  try {
    final result = await runStep(action.name, () => action.run(context));
    stopwatch.stop();
    action
      ..status = ActionStatus.success
      ..duration = stopwatch.elapsed;
    return result;
  } catch (e, stackTrace) {
    stopwatch.stop();
    action
      ..status = ActionStatus.failed
      ..duration = stopwatch.elapsed
      ..error = e
      ..stackTrace = stackTrace;
    rethrow;
  }
}
```

**职责划分：**
- `runAction` — 负责计时（Stopwatch）、状态记录、调用 `runStep` 记日志
- `runStep` — 只负责 Logger 输出（section / success / error）

#### run — 自动打印汇总

```dart
Future<void> run(Set<AppPlatform> platforms) async {
  context = createContext(platforms);
  try {
    await beforeBuild();
    await body();
  } finally {
    try {
      await afterBuild();
    } catch (e) {
      Logger.error('afterBuild failed', e);
    }
    _printSummary();
  }
}
```

#### 汇总表输出

```dart
void _printSummary() {
  const sep = '────────────────────────────────────';
  Logger.info(sep);
  Logger.info('执行摘要');
  Logger.info(sep);
  for (final action in executedActions) {
    final icon = switch (action.status!) {
      ActionStatus.success => '✅',
      ActionStatus.failed => '❌',
      ActionStatus.skipped => '⏭️',
      ActionStatus.interrupted => '🛑',
    };
    final time = '${action.duration!.inSeconds}s';
    Logger.info('$icon ${action.name} ($time)');
  }
  Logger.info(sep);
  final failure = lastFailure;
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

### runStep 简化 — `lib/src/pipeline.dart`

```dart
Future<T> runStep<T>(String name, Future<T> Function() action) async {
  Logger.section(name);
  try {
    final result = await action();
    Logger.success('Finished: $name');
    return result;
  } catch (e) {
    Logger.error('Failed: $name', e);
    rethrow;
  }
}
```

去掉 `DateTime.now()` 计时，只保留日志。计时职责移至 `runAction`。

### afterBuild 感知状态

```dart
@override
Future<void> afterBuild() async {
  if (allSucceeded) {
    await runAction(PushBuildTagAction());
  } else {
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: '...',
      status: lastFailure?.error.toString(),
    ));
  }
  await runAction(RestoreWorkspaceAction());
}
```

### 公共 API 导出

在 `lib/flutter_ci_tools.dart` 增加：

```dart
export 'src/action_status.dart';
```

`PipelineAction` 已通过 `pipeline_action.dart` 导出，新增的字段自然对用户可见。

## 关键设计决策

**1. 状态存在 Action 上还是 PipelineContext？**

存在 Action 上。理由：
- 每个 Action 自然拥有自己的执行状态，职责更内聚
- PipelineContext 保持为构建配置/元数据容器
- `afterBuild` 通过遍历 `executedActions` 查询结果
- 避免了泛型 `PipelineAction<R>` 的 `R` 不同导致无法统一存储的问题

**2. 计时在 runStep 还是 runAction？**

在 `runAction`。理由：
- `runStep` 是通用日志包装器，不感知 `PipelineAction`
- 状态需要写入 Action 字段，这在 `runAction` 中更自然
- `runStep` 保持简单，只负责 Logger 输出

**3. 汇总表在哪里打印？**

在 `BuildPipeline.run()` 的 `finally` 块中自动打印。覆盖 `body()` 成功、`body()` 失败、`afterBuild` 失败所有场景。

**4. 是否支持 skipped 状态？**

当前架构没有条件跳过机制。`skipped` 和 `interrupted` 状态先定义好，为未来预留，暂时不会被触发。

## 测试策略

- `test/action_status_test.dart` — 枚举值验证
- `test/pipeline_test.dart` — 扩展现有测试：
  - 成功 Action 的 `status` / `duration` 被正确记录
  - 失败 Action 的 `status` / `error` / `stackTrace` 被正确记录
  - `executedActions` 按执行顺序记录
  - `allSucceeded` / `lastFailure` 正确反映状态
  - 汇总表在 pipeline 结束后打印
- 现有 Action 测试不需要改动（直接调用 `action.run(context)`，不涉及 `runAction`）
