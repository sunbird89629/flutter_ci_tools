# Explicit Artifact for Upload Actions + Parallel Upload

**Date:** 2026-06-09
**Status:** In Progress
**Related:** [[2026-05-25-remove-service-fields-from-context-design]], [[2026-05-22-pipeline-context-design]], [[2026-05-22-pipeline-actions-design]]

## Motivation

`PipelineContext` 只有一个 `buildArtifact` 槽，每次 `BuildAndroidAction` /
`BuildIOSAction` 调用 `setBuildArtifact()` 会覆盖前值；所有 upload action
（`PgyerUploadV2Action` / `GooglePlayUploadAction` / `AppStoreUploadAction`）
都从这个槽读 `context.buildArtifact`。

这导致一类 pipeline 无法表达：**同一次 run 里产出多个 artifact 并各自上传**。
典型场景是 hitfinds_flutter 的 StorePipeline——旧 `StoreEnvBuilder` 用
`Future.wait([_uploadAndroid(aab), _uploadIOS(ipa)])` **并行**上传 aab 和 ipa，
迁移到 v0.0.2 后被迫改成「build aab → 传 → build ipa → 传」**串行**，损失了并行加速。

另外，`FeishuBuildNotifyAction` 目前只支持单个 `downloadUrl`，无法在一条通知里展示多个平台的链接。

根因有两个，需分别解决：

1. **artifact 归属** — upload action 只能读单槽，无法指定「传哪个文件」。
2. **执行模型** — `BuildPipeline.runAction()` 串行 `await`，无并行入口。

只解决 (1) 能恢复正确性（仍串行）；要恢复并行需同时解决 (2)。

## 设计准则：传参通道（广播 vs 点对点）

action 之间传参有两条通道，**不应统一成一条**，而是按数据特征分流：

| 数据特征 | 通道 | 例子 |
|---|---|---|
| **广播型**：本次 run 的共享事实，多个下游都读 | `PipelineContext` | `metadata`、`buildNumber`、`args` |
| **点对点**：A 产出、B 消费的一次性管线值 | 显式返回值 / 构造参数 | `pgyerUrl → notify`、`artifact → upload` |

准则一句话：**「多人读的共享配置」进 context；「一对一接力的管线值」走显式传。**

### 为什么不把所有传参都塞进 context

曾考虑让所有 action 一律走 context 以求「单一心智模型」，否决，代价有四：

1. **丢编译期保证** — 返回值接力是类型安全的（漏接上一步则编译报错）；全走 context
   会把所有传参降级成运行时 `late` / `StateError`，即把 `buildArtifact` / `buildNumber`
   现有的「忘了前置 action 就运行时炸」模式蔓延到全局。
2. **单槽冲突 / context 膨胀** — 即本文档要解决的根因；点对点值塞进 context 单槽会互相
   覆盖，具名多槽又让 context 沦为「什么都装的大袋子」，并行更无从表达。
3. **隐藏依赖** — 输入写在构造函数里一眼可见；藏进 `run()` 读 context 则违背
   constructor injection / 显式接口约定。
4. **并行 + 可测试性变差** — 共享可变 context + 并行写 = 竞态；显式传值天然适合并行，
   单测也无需预先 setup 一大袋 context 状态。

### 对本设计的指导

`buildArtifact` 本质是**点对点**（build 产出 → 特定 upload 消费），却被放进 context 单槽，
于是撞上「多 artifact / 并行」的墙。因此正确方向不是往 context 里塞更多东西，而是把
`buildArtifact` 抽出来走**显式传值**——即下文「变更 1（upload 显式 File）」与「变更 3（build action 返回 `File`）」。
context 单槽语义保留，仅不再是唯一来源。

## Design

### 变更 1：upload action 支持显式 File（向后兼容）

三个 upload action 各加一个可选 `File? artifact` 构造参数，`run()` 里
「传了用传的，没传退回 context」：

```dart
class PgyerUploadV2Action extends PipelineAction<String> {
  PgyerUploadV2Action({
    required this.apiKey,
    this.description,
    this.artifact,                 // ← 新增，可选
    List<String>? apiDomains,
    Future<bool> Function(String domain)? probeDomain,
    ShellRunner? shellRunner,
  }) : // ... 其余不变 ...

  /// 显式指定要上传的文件；为 null 时退回 `context.buildArtifact`。
  final File? artifact;

  @override
  Future<String> run(PipelineContext context) async {
    final file = artifact ?? context.buildArtifact;   // ← 唯一改动点
    // ... 用 file 替代原来的 context.buildArtifact ...
  }
}
```

- 老代码不传 `artifact` → 行为完全不变（**零破坏**）。
- `PgyerUploadAction` 同样改法。
- 解决「哪个文件传到哪」的正确性，使 upload 不再依赖单槽。

### 变更 2：BuildPipeline 新增并行入口

当前 `runAction()` 负责：追加 `executedActions`、计时、记 `ActionStatus`、
失败时记 error/stackTrace。并行执行需要把「追踪单个 action」的逻辑抽出来复用：

```dart
abstract class BuildPipeline {
  /// 串行执行（现有，行为不变）。
  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    return _runTracked(action);
  }

  /// 并行执行多个 action，全部完成后返回；任一失败时其余仍跑完，
  /// 失败状态各自记录（沿用 _printSummary 的逐条展示）。
  /// 返回 List<R>，按输入顺序对应每个 action 的结果。
  Future<List<R>> runParallel<R>(List<PipelineAction<R>> actions) async {
    executedActions.addAll(actions);
    return Future.wait(actions.map(_runTracked));
  }

  /// 抽出的单 action 追踪逻辑（计时 + 状态 + 错误）。
  Future<R> _runTracked<R>(PipelineAction<R> action) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await runStep(action.name, () => action.run(context));
      stopwatch.stop();
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
      return result;
    } catch (e, st) {
      stopwatch.stop();
      action
        ..status = ActionStatus.failed
        ..duration = stopwatch.elapsed
        ..error = e
        ..stackTrace = st;
      rethrow;
    }
  }
}
```

### 变更 3：build action 返回 `File`（向后兼容）

`BuildAndroidAction` / `BuildIOSAction` 从 `PipelineAction<void>` 改为 `PipelineAction<File>`，
同时**仍然调用 `context.setBuildArtifact()`**，确保现有代码不受影响：

```dart
class BuildAndroidAction extends PipelineAction<File> {
  // ... 构造函数不变 ...

  @override
  Future<File> run(PipelineContext context) async {
    // ... 构建逻辑不变 ...
    final file = File(outputPath);
    context.setBuildArtifact(file);  // 仍写 context，保持向后兼容
    return file;  // 新增：同时返回
  }
}

class BuildIOSAction extends PipelineAction<File> {
  // ... 构造函数不变 ...

  @override
  Future<File> run(PipelineContext context) async {
    // ... 构建逻辑不变 ...
    final file = _findIpa();
    context.setBuildArtifact(file);  // 仍写 context，保持向后兼容
    return file;  // 新增：同时返回
  }
}
```

### 变更 4：FeishuBuildNotifyAction 支持多个下载链接（向后兼容）

新增 `List<String>? downloadUrls` 参数，同时保留 `downloadUrl` 单值参数（向后兼容）：

```dart
class FeishuBuildNotifyAction extends PipelineAction<void> {
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.target,
    this.downloadUrl,  // 保留，向后兼容
    this.downloadUrls, // 新增：多个链接
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  final String webhookUrl;
  final DeployTarget target;
  final String? downloadUrl;
  final List<String>? downloadUrls;

  @override
  Future<void> run(PipelineContext context) async {
    final urls = downloadUrls ?? (downloadUrl != null ? [downloadUrl!] : null);
    // ... 使用 urls 拼接消息 ...
    // 如果是多个链接，消息里列出来：
    // Android: https://...
    // iOS: https://...
  }
}
```

### 两者合用后的 TestEnvPipeline

```dart
@override
Future<void> body() async {
  await runAction(ResolveBuildVersionAction());
  await runAction(CheckGitStatusAction());
  await runAction(CleanProjectAction());

  // 构建，显式拿到两个文件
  final androidFile = await runAction(BuildAndroidAction(
    envName: 'test',
    buildType: AndroidBuildType.apk,
  ));
  final iosFile = await runAction(BuildIOSAction(
    envName: 'test',
    exportMethod: 'development',
  ));

  // 并行上传
  final urls = await runParallel([
    PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: androidFile),
    PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: iosFile),
  ]);

  // 一条通知包含两个链接
  await runAction(FeishuBuildNotifyAction(
    webhookUrl: feishuWebhookUrl,
    target: DeployTarget.pgyer,
    downloadUrls: urls,
  ));

  await runAction(PushBuildTagAction());
}
```

## 影响范围

- `PgyerUploadAction` / `PgyerUploadV2Action` — 新增可选 `File? artifact` 字段与 fallback 逻辑（向后兼容）。
- `BuildPipeline` — 新增 `runParallel()`，抽出 `_runTracked()`（`runAction` 行为不变）。
- `BuildAndroidAction` / `BuildIOSAction` — 返回 `File`（`PipelineAction<void>` → `PipelineAction<File>`，同时保留 `setBuildArtifact`）。
- `FeishuBuildNotifyAction` — 新增可选 `List<String>? downloadUrls`（向后兼容）。
- 测试 — 新增「传 File / 不传退回 context」「runParallel 状态与计时正确」「并行中一个失败、另一个仍完成」「多个下载链接通知格式正确」用例，沿用 `_Fake*` 风格。
- 不影响：`PipelineContext` 单槽语义保持不变（仅不再是唯一来源）。

## 待决问题（已解决）

- [x] build action 是否改为返回 `File`（`PipelineAction<File>`）？是。
- [x] `runParallel` 的失败语义：用 `Future.wait`（首个失败即抛，其余继续跑到完成）是否够用？是。
- [x] `_printSummary` 的执行顺序展示——并行 action 在 `executedActions` 里按注册顺序排列，但实际完成顺序不同；摘要是否需要标注「并行组」？暂时不需要，现有摘要已够用。
- [x] 是否值得为「多 artifact」在 `PipelineContext` 里提供具名多槽？不需要，显式传 File 已足够。
