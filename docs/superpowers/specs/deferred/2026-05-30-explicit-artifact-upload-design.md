# Explicit Artifact for Upload Actions + Parallel Upload

**Date:** 2026-05-30
**Status:** Deferred
**Related:** [[2026-05-25-remove-service-fields-from-context-design]], [[2026-05-22-pipeline-context-design]], [[2026-05-22-pipeline-actions-design]]

## Motivation

`PipelineContext` 只有一个 `buildArtifact` 槽，每次 `BuildAndroidAction` /
`BuildIOSAction` 调用 `setBuildArtifact()` 会覆盖前值；所有上传 action
（`PgyerUploadV2Action` / `GooglePlayUploadAction` / `AppStoreUploadAction`）
都从这个槽读 `context.buildArtifact`。

这导致一类 pipeline 无法表达：**同一次 run 里产出多个 artifact 并各自上传**。
典型场景是 hitfinds_flutter 的 StorePipeline——旧 `StoreEnvBuilder` 用
`Future.wait([_uploadAndroid(aab), _uploadIOS(ipa)])` **并行**上传 aab 和 ipa，
迁移到 v0.0.2 后被迫改成「build aab → 传 → build ipa → 传」**串行**，损失了并行加速。

根因有两个，需分别解决：

1. **artifact 归属** — upload action 只能读单槽，无法指定「传哪个文件」。
2. **执行模型** — `BuildPipeline.runAction()` 串行 `await`，无并行入口。

只解决 (1) 能恢复正确性（仍串行）；要恢复并行需同时解决 (2)。

## Design

### 变更 1：upload action 支持显式 File（向后兼容）

三个 upload action 各加一个可选 `File? artifact` 构造参数，`run()` 里
「传了用传的，没传退回 context」：

```dart
class GooglePlayUploadAction extends PipelineAction<void> {
  GooglePlayUploadAction({
    required this.packageName,
    required this.jsonKeyPath,
    this.artifact,                 // ← 新增，可选
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// 显式指定要上传的文件；为 null 时退回 `context.buildArtifact`。
  final File? artifact;

  @override
  Future<void> run(PipelineContext context) async {
    final file = artifact ?? context.buildArtifact;   // ← 唯一改动点
    // ... 用 file 替代原来的 context.buildArtifact ...
  }
}
```

- 老代码不传 `artifact` → 行为完全不变（**零破坏**）。
- `PgyerUploadV2Action`、`AppStoreUploadAction` 同样改法。
- 解决「哪个文件传到哪」的正确性，使 upload 不再依赖单槽。

### 变更 2：BuildPipeline 新增并行入口

当前 `runAction()` 负责：追加 `executedActions`、计时、记 `ActionStatus`、
失败时记 error/stackTrace。并行执行需要把「追踪单个 action」的逻辑抽出来复用：

```dart
abstract class BuildPipeline {
  /// 串行执行（现有）。
  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    return _runTracked(action);
  }

  /// 并行执行多个 action，全部完成后返回；任一失败时其余仍跑完，
  /// 失败状态各自记录（沿用 _printSummary 的逐条展示）。
  Future<void> runParallel(List<PipelineAction> actions) async {
    executedActions.addAll(actions);
    await Future.wait(actions.map(_runTracked));
  }

  /// 抽出的单 action 追踪逻辑（计时 + 状态 + 错误）。
  Future<R> _runTracked<R>(PipelineAction<R> action) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await runStep(action.name, () => action.run(context));
      stopwatch.stop();
      action..status = ActionStatus.success..duration = stopwatch.elapsed;
      return result;
    } catch (e, st) {
      stopwatch.stop();
      action..status = ActionStatus.failed..duration = stopwatch.elapsed
            ..error = e..stackTrace = st;
      rethrow;
    }
  }
}
```

### 两者合用后的 StorePipeline

```dart
final aab = await runAction(BuildAndroidAction(
    envName: 'product', buildType: AndroidBuildType.appbundle));   // 见“待决问题”
await runAction(SwapInfoPlistAction());
final ipa = await runAction(BuildIOSAction(
    envName: 'product', exportMethod: 'app-store'));

await runParallel([
  GooglePlayUploadAction(packageName: …, jsonKeyPath: …, artifact: aab),
  AppStoreUploadAction(issuerId: …, apiKeyId: …, apiKeyPath: …, artifact: ipa),
]);
```

> 注意：要拿到 `aab` / `ipa` 的 `File`，build action 需返回它。当前
> `BuildAndroidAction` / `BuildIOSAction` 是 `PipelineAction<void>`，只写 context。
> 见待决问题第 1 条。

## 影响范围

- `GooglePlayUploadAction` / `AppStoreUploadAction` / `PgyerUploadV2Action`
  — 新增可选 `File? artifact` 字段与 fallback 逻辑（向后兼容）。
- `BuildPipeline` — 新增 `runParallel()`，抽出 `_runTracked()`（`runAction` 行为不变）。
- `BuildAndroidAction` / `BuildIOSAction` — 若要支持显式传值，需返回 `File`
  （`PipelineAction<void>` → `PipelineAction<File>`，同时保留 `setBuildArtifact`）。
- 测试 — 新增「传 File / 不传退回 context」「runParallel 状态与计时正确」「并行中
  一个失败、另一个仍完成」用例，沿用 `_Fake*` 风格。
- 不影响：`PipelineContext` 单槽语义保持不变（仅不再是唯一来源）。

## 待决问题

- [ ] build action 是否改为返回 `File`（`PipelineAction<File>`）？这是「显式传值」
      最干净的取数方式，但改了所有 build action 的类型参数与现有调用点。
      备选：pipeline body 里 build 后立刻 `final f = context.buildArtifact` 捞出来，
      但要赶在下一个 build 覆盖前，易错。
- [ ] `runParallel` 的失败语义：用 `Future.wait`（首个失败即抛，其余继续跑到完成）
      是否够用？是否需要 `eagerError: false` + 聚合多个失败？
- [ ] `_printSummary` 的执行顺序展示——并行 action 在 `executedActions` 里按
      注册顺序排列，但实际完成顺序不同；摘要是否需要标注「并行组」？
- [ ] 是否值得为「多 artifact」在 `PipelineContext` 里提供具名多槽
      （如 `Map<String, File>`），还是显式传 File 已足够、不必动 context？
      倾向后者——保持 context 简单，并行性交给 pipeline 编排层。
