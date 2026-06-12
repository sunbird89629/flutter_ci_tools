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
| `PgyerUploadAction` | `return downloadUrl` | `context.put(ContextKeys.pgyerDownloadUrl, url)`，`run` 返回 `void` |
| `PgyerUploadV2Action` | `return downloadUrl` | `context.put(ContextKeys.pgyerDownloadUrl, url)`，`run` 返回 `void` |
| `GooglePlayUploadAction` | 读 `context.buildArtifact` | 读 `context.get<File>(ContextKeys.buildArtifact)` |
| `AppStoreUploadAction` | 读 `context.buildArtifact` | 读 `context.get<File>(ContextKeys.buildArtifact)` |
| `PushBuildTagAction` | 读 `context.buildNumber` | 读 `context.get<int>(ContextKeys.buildNumber)` |

上传 action 中以 `artifact ?? context.buildArtifact` 形式的 fallback，改为 `artifact ?? context.get<File>(ContextKeys.buildArtifact)`。

### 6. FeishuBuildNotifyAction —— 链接通过 key 读

- 构造参数 `downloadUrl` / `downloadUrls` 替换为单个 `String? downloadUrlKey`。
- `run()` 内：`final url = downloadUrlKey == null ? null : context.tryGet<String>(downloadUrlKey);`
- `_formatMessage` 用该 `url`（为 null 时不显示下载行，行为同现状 GP/AppStore 通知）。
- 调用方：
  ```dart
  FeishuBuildNotifyAction(target: DeployTarget.pgyer,
                          downloadUrlKey: ContextKeys.pgyerDownloadUrl);
  // Google Play / App Store：不传 downloadUrlKey → 无下载链接
  ```

> 说明：原 `downloadUrls`（多链接列表）当前无调用方使用，本次简化为单链接 key。若未来需要多链接，可另加 `List<String>` key + `tryGet<List<String>>`，不在本次范围。

### 7. 调用方 / 示例更新

- `example/ci/pipelines/android_test_pipeline.dart`：删除 `final pgyerUrl = await runAction(...)` 的局部变量捕获，改为：
  ```dart
  await runAction(PgyerUploadAction(apiKey: ctx.pgyerApiKey));
  await runAction(FeishuBuildNotifyAction(
    webhookUrl: ctx.feishuWebhookUrl,
    target: DeployTarget.pgyer,
    downloadUrlKey: ContextKeys.pgyerDownloadUrl,
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
  - `FeishuBuildNotifyAction`：传 `downloadUrlKey` 且 bag 有值时消息含链接；不传 key 时消息无链接
- **Pipeline** (`test/pipeline_test.dart` / `pipeline_parallel_test.dart`)：`runAction` / `runParallelActions` 不再有返回值，断言改为通过 context 读取产出物。

## Out of Scope

- 多下载链接（`List<String>`）通知 —— 当前无调用方，留待需要时再加。
- typed key / 类型化容器 —— 本次明确选用字符串 key bag。
- 把构造配置或注入基础设施（`git`/`logger`/`args` 等）迁入 bag —— 保持字段。
