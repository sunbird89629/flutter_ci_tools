# Pipeline Context Result Channel Design

Status: Accepted

## Motivation

当前 action 的产出数据存在**两条并存的通道**，相互不一致，让人困惑：

1. **Context 通道** — `buildArtifact`、`buildNumber` 通过 `PipelineContext` 的 typed 字段传递（`setBuildArtifact` / `resolveBuildVersion`）。
2. **返回值通道** — `PgyerUploadAction` 这类 action 通过 `runAction` 的泛型返回值 `R` 把下载链接送回 `body` 作用域，再由 `body` 手动喂给下游 action 的构造函数。

```dart
// 现状：返回值通道导致 body 里手动线程化
final pgyerUrl = await runAction(PgyerUploadAction(...));
await runAction(FeishuBuildNotifyAction(downloadUrl: pgyerUrl));
```

双通道的问题：

- **不一致** — 同样是「action 产出物」，有的进 context 有的走返回值，没有统一心智模型。
- **不利于并行/重排** — 返回值要在 `body` 里按顺序捕获，`runParallelActions` 与乱序场景下传递困难；context 作为共享状态更灵活。

**目标**：去掉返回值通道，所有 action 产出物统一写入 `PipelineContext`，让 context 成为唯一的状态通道。

## Design Decisions

| 决策 | 结论 |
|------|------|
| 存储形态 | 字符串 key 的 KV bag（`Map<String, Object?>`），不用 typed 字段或类型化容器 |
| 泛型 R | 彻底去掉。`PipelineAction` 不再泛型，`run()` 一律返回 `Future<void>` |
| 迁移边界 | 只迁 **action 产出物**（`buildNumber`、`buildArtifact`、下载链接）。构造配置与注入基础设施保持字段 |
| 便捷 getter | 不保留 `buildNumber`/`buildArtifact` getter，到处用 `get`/`put`。例外：`buildName` 作为派生计算 getter 保留 |
| 缺失行为 | `get<T>(key)` 缺失抛 `StateError`（延续守卫语义）；`tryGet<T>(key)` 返 `null` 用于可选值 |
| key 管理 | 库结果的 key 用集中常量 `ContextKeys`，上下游引用同一常量，避免拼错 |
| 通知取链接 | `FeishuBuildNotifyAction` 根据指定 key 从 bag 读下载链接，不再由 `body` 线程化 |

## Architecture

### 1. PipelineAction —— 去掉泛型 R

```dart
abstract class PipelineAction {              // 不再 <R>
  String get name;
  String get description;
  ActionStatus? status;
  Duration? duration;
  Object? error;
  StackTrace? stackTrace;
  bool get hasRun => status != null;
  Future<void> run(PipelineContext context); // 一律 void
}
```

`name`/`description` 的默认实现保持不变。

### 2. Pipeline —— runAction 不再有返回值

```dart
Future<void> runAction(PipelineAction action);
Future<void> runParallelActions(List<PipelineAction> actions);
```

- `_runTracked` 返回 `void`。
- 计时、状态记录（`status`/`duration`/`error`/`stackTrace`）、section 日志、`_printSummary` 逻辑全部不变。
- `executedActions` 已是 `List<PipelineAction>`，无需改动。

### 3. PipelineContext —— 加 KV bag，移除 typed 产出物

```dart
final Map<String, Object?> _bag = {};

void put(String key, Object? value) => _bag[key] = value;

T get<T>(String key) {
  if (!_bag.containsKey(key)) {
    throw StateError("context 中尚未设置 '$key'，请确认相关 action 已先执行。");
  }
  return _bag[key] as T;
}

T? tryGet<T>(String key) => _bag[key] as T?;
```

**移除**：

- `BuildVersion` / `BuildVersionUnresolved` / `BuildVersionResolved` sealed 类族
- `_buildVersion` 字段、`buildNumber` getter、`resolveBuildVersion`
- `_buildArtifact` 字段、`buildArtifact` getter、`setBuildArtifact`

**保留为派生 getter**（纯计算、无存储，不算违反「纯 get/put」）：

```dart
String get buildName {
  final str = get<int>(ContextKeys.buildNumber).toString();
  return '${str[0]}.${str[1]}.${str[2]}';
}
```

**保留为字段**（非 action 产出物）：`appName`、`seedBuildNumber`、`rawArgs`、`args`、`git`、`logger`、`projectRoot`、`pubspecName`、`pubspecVersion`。

### 4. ContextKeys —— 集中常量

新文件 `lib/src/context_keys.dart`，由 barrel `lib/flutter_ci_tools.dart` 导出。

```dart
class ContextKeys {
  ContextKeys._();

  static const buildNumber = 'buildNumber';
  static const buildArtifact = 'buildArtifact';
  static const pgyerDownloadUrl = 'pgyerDownloadUrl';
}
```

### 5. Action 迁移

| Action | 旧行为 | 新行为 |
|---|---|---|
| `ResolveBuildVersionAction` | `context.resolveBuildVersion(n)` | `context.put(ContextKeys.buildNumber, n)` |
| `BuildAndroidAction` | 返回 `File` + `setBuildArtifact(file)` | 只 `context.put(ContextKeys.buildArtifact, file)`，`run` 返回 `void` |
| `BuildIOSAction` | 返回 `File` + `setBuildArtifact(file)` | 只 `context.put(ContextKeys.buildArtifact, file)`，`run` 返回 `void` |
| `PgyerUploadAction` | `return downloadUrl` | `context.put(resultKey, url)`，`run` 返回 `void`（`resultKey` 默认 `ContextKeys.pgyerDownloadUrl`） |
| `PgyerUploadV2Action` | `return downloadUrl` | `context.put(resultKey, url)`，`run` 返回 `void`（`resultKey` 默认 `ContextKeys.pgyerDownloadUrl`） |
| `GooglePlayUploadAction` | 读 `context.buildArtifact` | 读 `context.get<File>(ContextKeys.buildArtifact)` |
| `AppStoreUploadAction` | 读 `context.buildArtifact` | 读 `context.get<File>(ContextKeys.buildArtifact)` |
| `PushBuildTagAction` | 读 `context.buildNumber` | 读 `context.get<int>(ContextKeys.buildNumber)` |

上传 action 中以 `artifact ?? context.buildArtifact` 形式的 fallback，改为 `artifact ?? context.get<File>(ContextKeys.buildArtifact)`。

#### Pgyer action 的 `resultKey`

`PgyerUploadAction` / `PgyerUploadV2Action` 新增可选构造参数 `String resultKey`，默认 `ContextKeys.pgyerDownloadUrl`。`run()` 末尾把下载链接 `context.put(resultKey, url)`。这样**并行上传多个产物**时，各 upload 可写入不同 key，互不覆盖（见 `test_env_pipeline`）。

### 6. FeishuBuildNotifyAction —— 链接通过 key 列表读

> 设计修订（2026-06-12）：原计划用单个 `downloadUrlKey`。但 `test_env_pipeline` 实际会并行上传两个产物、用一条通知带两个链接（旧 `downloadUrls` 参数）。故采用 key **列表**，保留多链接能力。

- 构造参数 `downloadUrl` / `downloadUrls` 替换为 `List<String>? downloadUrlKeys`。
- `run()` 内从每个 key 读链接、过滤 null：
  ```dart
  final urls = downloadUrlKeys == null
      ? const <String>[]
      : downloadUrlKeys
          .map((k) => context.tryGet<String>(k))
          .whereType<String>()
          .toList();
  ```
- `_formatMessage` 渲染（沿用现有 UX）：0 个不显示下载行；1 个显示 `🔗 下载: <url>`；多个显示编号列表 `🔗 下载链接:` + `  1. ...`。
- 调用方：
  ```dart
  // 单链接
  FeishuBuildNotifyAction(target: DeployTarget.pgyer,
      downloadUrlKeys: [ContextKeys.pgyerDownloadUrl]);
  // Google Play / App Store：不传 downloadUrlKeys → 无下载链接
  ```

### 7. 调用方 / 示例更新

- `example/ci/pipelines/android_test_pipeline.dart`：删除 `final pgyerUrl = await runAction(...)` 的局部变量捕获，改为：
  ```dart
  await runAction(PgyerUploadAction(apiKey: ctx.pgyerApiKey));
  await runAction(FeishuBuildNotifyAction(
    webhookUrl: ctx.feishuWebhookUrl,
    target: DeployTarget.pgyer,
    downloadUrlKeys: [ContextKeys.pgyerDownloadUrl],
  ));
  ```
- `example/ci/pipelines/test_env_pipeline.dart`：并行上传两个产物、一条通知带两个链接。产物用局部变量捕获，上传写入不同 `resultKey`：
  ```dart
  const androidUrlKey = 'pgyerAndroidUrl';
  const iosUrlKey = 'pgyerIosUrl';

  await runAction(BuildAndroidAction(...));
  final androidFile = context.get<File>(ContextKeys.buildArtifact);
  await runAction(BuildIOSAction(...));
  final iosFile = context.get<File>(ContextKeys.buildArtifact);

  await runParallelActions([
    PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: androidFile,
        resultKey: androidUrlKey),
    PgyerUploadV2Action(apiKey: pgyerApiKey, artifact: iosFile,
        resultKey: iosUrlKey),
  ]);
  await runAction(FeishuBuildNotifyAction(
    webhookUrl: feishuWebhookUrl,
    target: DeployTarget.pgyer,
    downloadUrlKeys: [androidUrlKey, iosUrlKey],
  ));
  ```
- `prod_pipeline.dart`：`FeishuBuildNotifyAction` 调用无需传 key（GP/AppStore 无链接），其余不变。

## Testing

沿用项目「手写 `_Fake*` 假实现」与「测试镜像 lib 结构」约定。

- **PipelineContext** (`test/pipeline_context_test.dart`)：
  - `get<T>` 命中返回值、缺失抛 `StateError`
  - `tryGet<T>` 缺失返 `null`、命中返值
  - `buildName` 在 `put(buildNumber, n)` 后正确派生；未设置时访问抛 `StateError`
  - 删除针对 `resolveBuildVersion` / `setBuildArtifact` 的旧用例，改为 `put`
- **迁移的 action**：
  - 写入型（`ResolveBuildVersionAction`、`BuildAndroid/IOS`、`Pgyer*`）断言执行后 `context.get(对应 key)` 为预期值
  - 读取型（`GooglePlay`、`AppStore`、`PushBuildTag`）测试用 `context.put(key, ...)` 预置状态
  - `FeishuBuildNotifyAction`：`downloadUrlKeys` 含一个 key 且 bag 有值 → 单链接；含多个 key → 编号列表；不传 → 无下载行
  - `PgyerUploadAction` / `V2`：默认写 `ContextKeys.pgyerDownloadUrl`；传 `resultKey` 时写入该 key
- **Pipeline** (`test/pipeline_test.dart` / `pipeline_parallel_test.dart`)：`runAction` / `runParallelActions` 不再有返回值，断言改为通过 context 读取产出物。

## Out of Scope

- typed key / 类型化容器 —— 本次明确选用字符串 key bag。
- 把构造配置或注入基础设施（`git`/`logger`/`args` 等）迁入 bag —— 保持字段。

> 修订记录（2026-06-12）：初稿曾把「多下载链接通知」列为 Out of Scope，理由是「无调用方」。复核发现 `test_env_pipeline` 正是调用方（并行上传两产物 + 一条双链接通知）。已改为 §6 的 `downloadUrlKeys` 列表 + Pgyer `resultKey` 方案，保留多链接能力。
