# Pipeline Context Result Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让所有 action 产出物统一写入 `PipelineContext` 的字符串 key KV bag，去掉 `runAction` 的泛型返回值通道。

**Architecture:** `PipelineContext` 新增 `Map<String, Object?>` bag，暴露 `put` / `get<T>`（缺失抛 `StateError`）/ `tryGet<T>`（缺失返 `null`）。库结果 key 集中在 `ContextKeys` 常量类。逐组迁移（buildNumber → buildArtifact → 下载链接），最后去掉 `PipelineAction<R>` 泛型，`run()` 一律 `Future<void>`。

**Tech Stack:** Dart, `package:test`，手写 `_Fake*` 假实现（沿用现有约定）。

**执行约定：** 每个 action 测试文件镜像 `lib` 结构；提交用 conventional commits；每个 Task 结束 `dart test` 必须全绿。

---

## File Structure

| 文件 | 责任 | 本计划动作 |
|---|---|---|
| `lib/src/context_keys.dart` | 库结果的 key 常量 | **新建** |
| `lib/src/pipeline_context.dart` | 共享状态 + KV bag | 加 bag API；移除 `BuildVersion`/`buildNumber`/`buildArtifact` typed 槽；`buildName` 改派生自 bag |
| `lib/src/actions/pipeline_action.dart` | action 抽象基类 | 去掉 `<R>`，`run` 返回 `Future<void>` |
| `lib/src/pipeline.dart` | 执行壳 | `runAction`/`runParallelActions` 去泛型，返回 `void` |
| `lib/src/actions/resolve_build_version_action.dart` | 写 buildNumber | `put(ContextKeys.buildNumber, n)` |
| `lib/src/actions/build_android_action.dart` / `build_ios_action.dart` | 写 buildArtifact，读 buildNumber/buildName | `put(buildArtifact)`，读 `get<int>(buildNumber)`，返回 `void` |
| `lib/src/actions/google_play_action.dart` / `app_store_action.dart` | 读 buildArtifact | `get<File>(ContextKeys.buildArtifact)` |
| `lib/src/actions/push_build_tag_action.dart` | 读 buildNumber | `get<int>(ContextKeys.buildNumber)` |
| `lib/src/actions/pgyer_upload_action.dart` / `pgyer_upload_v2_action.dart` | 上传，产出下载链接 | 读 `get<File>(buildArtifact)`，`put(resultKey, url)`（默认 `pgyerDownloadUrl`），返回 `void` |
| `lib/src/actions/feishu_build_notify_action.dart` | 通知 | `downloadUrl`/`downloadUrls` → `downloadUrlKeys`(List)，逐 key `tryGet<String>` |
| `example/ci/pipelines/test_env_pipeline.dart` | 示例 | 局部变量捕获两产物，并行上传写不同 `resultKey`，通知用 `downloadUrlKeys` |
| `lib/flutter_ci_tools.dart` | barrel | 导出 `context_keys.dart` |
| `example/ci/pipelines/android_test_pipeline.dart` | 示例 | 去掉 `pgyerUrl` 局部变量，通知传 key |
| `test/**` | 测试 | 同步迁移断言 |

---

## Task 1: PipelineContext 加 KV bag + ContextKeys（additive，旧 API 不动）

**Files:**
- Create: `lib/src/context_keys.dart`
- Modify: `lib/flutter_ci_tools.dart` (barrel export)
- Modify: `lib/src/pipeline_context.dart`
- Test: `test/pipeline_context_test.dart`

本任务只**新增** bag API 与 `ContextKeys`，不删除任何旧字段，保持全绿。

- [ ] **Step 1: 写失败测试 —— bag 的 put/get/tryGet**

在 `test/pipeline_context_test.dart` 的 `main()` 内、`group('PipelineContext', ...)` 之后追加新 group：

```dart
  group('KV bag', () {
    late PipelineContext ctx;
    setUp(() {
      ctx = PipelineContext(appName: 'TestApp', seedBuildNumber: 12000);
    });

    test('get returns the value put under a key', () {
      ctx.put('k', 42);
      expect(ctx.get<int>('k'), 42);
    });

    test('get throws StateError with key name when key absent', () {
      expect(
        () => ctx.get<int>('missing'),
        throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('missing'))),
      );
    });

    test('tryGet returns null when key absent', () {
      expect(ctx.tryGet<String>('missing'), isNull);
    });

    test('tryGet returns the value when present', () {
      ctx.put('url', 'https://x');
      expect(ctx.tryGet<String>('url'), 'https://x');
    });
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `dart test test/pipeline_context_test.dart -n "KV bag"`
Expected: 编译失败 / FAIL —— `PipelineContext` 没有 `put`/`get`/`tryGet`。

- [ ] **Step 3: 在 PipelineContext 实现 bag API**

在 `lib/src/pipeline_context.dart` 的 class 体内（紧跟 `late final ArgsParser args = ...` 之后）插入：

```dart
  final Map<String, Object?> _bag = {};

  /// Stores [value] under [key] for later retrieval by downstream actions.
  void put(String key, Object? value) => _bag[key] = value;

  /// Returns the value stored under [key].
  ///
  /// Throws [StateError] if [key] was never set — signalling that a producing
  /// action must run earlier in the pipeline body.
  T get<T>(String key) {
    if (!_bag.containsKey(key)) {
      throw StateError("context 中尚未设置 '$key'，请确认相关 action 已先执行。");
    }
    return _bag[key] as T;
  }

  /// Returns the value stored under [key], or `null` if it was never set.
  T? tryGet<T>(String key) => _bag[key] as T?;
```

- [ ] **Step 4: 新建 ContextKeys**

Create `lib/src/context_keys.dart`:

```dart
/// Centralised string keys for values stored in [PipelineContext]'s KV bag.
///
/// Library actions write and read their results through these constants so
/// producers and consumers never disagree on a raw string literal.
class ContextKeys {
  ContextKeys._();

  /// Resolved build number (`int`). Written by `ResolveBuildVersionAction`.
  static const buildNumber = 'buildNumber';

  /// Build artifact (`File`). Written by `BuildAndroidAction` / `BuildIOSAction`.
  static const buildArtifact = 'buildArtifact';

  /// Pgyer download URL (`String`). Written by `PgyerUploadAction` / V2.
  static const pgyerDownloadUrl = 'pgyerDownloadUrl';
}
```

- [ ] **Step 5: barrel 导出**

在 `lib/flutter_ci_tools.dart` 顶部 export 区按字母序加入：

```dart
export 'src/context_keys.dart';
```

- [ ] **Step 6: 运行测试确认通过**

Run: `dart test`
Expected: 全部 PASS（旧 API 未动，新 bag 测试通过）。

- [ ] **Step 7: 提交**

```bash
git add lib/src/context_keys.dart lib/src/pipeline_context.dart lib/flutter_ci_tools.dart test/pipeline_context_test.dart
git commit -m "feat: add KV bag (put/get/tryGet) and ContextKeys to PipelineContext"
```

---

## Task 2: 迁移 buildNumber 到 bag

把 `buildNumber` 的写入方、读取方、`buildName` 派生、以及旧 `BuildVersion` 槽全部切到 bag。原子完成，保持全绿。

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Modify: `lib/src/actions/resolve_build_version_action.dart`
- Modify: `lib/src/actions/build_android_action.dart`
- Modify: `lib/src/actions/build_ios_action.dart`
- Modify: `lib/src/actions/push_build_tag_action.dart`
- Modify: `lib/src/actions/feishu_build_notify_action.dart`
- Test: `test/pipeline_context_test.dart`, `test/actions/resolve_build_version_action_test.dart`, `test/actions/build_android_action_test.dart`, `test/actions/build_ios_action_test.dart`, `test/actions/push_build_tag_action_test.dart`, `test/actions/feishu_build_notify_action_test.dart`

- [ ] **Step 1: 改测试到新 API（先让测试反映目标）**

在所有 test 文件里，把 `..resolveBuildVersion(N)` 替换为 `..put(ContextKeys.buildNumber, N)`，并在文件顶部 import 加：

```dart
import 'package:flutter_ci_tools/src/context_keys.dart';
```

具体替换点：
- `test/actions/build_android_action_test.dart:26` `..resolveBuildVersion(12001)` → `..put(ContextKeys.buildNumber, 12001)`
- `test/actions/build_ios_action_test.dart:26` 同上
- `test/actions/push_build_tag_action_test.dart:32` `..resolveBuildVersion(12042)` → `..put(ContextKeys.buildNumber, 12042)`
- `test/actions/feishu_build_notify_action_test.dart` 所有 `..resolveBuildVersion(12042)` → `..put(ContextKeys.buildNumber, 12042)`

在 `test/actions/resolve_build_version_action_test.dart` 把第 40 行断言：

```dart
    expect(context.buildNumber, 12001);
```

改为：

```dart
    expect(context.get<int>(ContextKeys.buildNumber), 12001);
```

并加 `import 'package:flutter_ci_tools/src/context_keys.dart';`。

在 `test/pipeline_context_test.dart` 把 `group('buildNumber (sealed)', ...)` 整段（第 76–107 行）替换为：

```dart
    group('buildNumber via bag', () {
      test('get throws StateError when buildNumber absent', () {
        expect(
          () => ctx.get<int>(ContextKeys.buildNumber),
          throwsA(isA<StateError>()),
        );
      });

      test('returns value after put', () {
        ctx.put(ContextKeys.buildNumber, 12001);
        expect(ctx.get<int>(ContextKeys.buildNumber), 12001);
      });

      test('buildName formats buildNumber correctly', () {
        ctx.put(ContextKeys.buildNumber, 12001);
        expect(ctx.buildName, '1.2.0');
      });

      test('buildName handles zeros', () {
        ctx.put(ContextKeys.buildNumber, 10000);
        expect(ctx.buildName, '1.0.0');
      });

      test('buildName handles triple digits', () {
        ctx.put(ContextKeys.buildNumber, 12345);
        expect(ctx.buildName, '1.2.3');
      });
    });
```

并在该测试文件顶部 import 加 `import 'package:flutter_ci_tools/src/context_keys.dart';`。

- [ ] **Step 2: 运行测试确认失败**

Run: `dart test test/pipeline_context_test.dart test/actions/resolve_build_version_action_test.dart`
Expected: 编译失败 —— context 仍有 `resolveBuildVersion`/`buildNumber`，但 action 还没改成写 bag，断言不匹配。

- [ ] **Step 3: PipelineContext 移除 BuildVersion 槽，buildName 派生自 bag**

在 `lib/src/pipeline_context.dart`：

1. 删除顶部的 `BuildVersion` sealed 类族（`sealed class BuildVersion` / `BuildVersionUnresolved` / `BuildVersionResolved` 三段，约第 7–17 行）。
2. 删除 `_buildVersion` 字段、`buildNumber` getter、`resolveBuildVersion`（约第 54–74 行）。
3. 把 `buildName` getter 改为读 bag：

```dart
  /// Human-readable build name derived from the resolved build number
  /// (e.g. `"1.2.0"`). Requires `ResolveBuildVersionAction` to have run.
  String get buildName {
    final str = get<int>(ContextKeys.buildNumber).toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }
```

4. 顶部 import 区加 `import 'context_keys.dart';`。

- [ ] **Step 4: ResolveBuildVersionAction 写 bag**

在 `lib/src/actions/resolve_build_version_action.dart`：

- import 区加 `import '../context_keys.dart';`
- `run` 内把 `context.resolveBuildVersion(number);` 改为 `context.put(ContextKeys.buildNumber, number);`
- log 行改为不依赖已删的 getter：

```dart
    context.put(ContextKeys.buildNumber, number);
    context.logger.info(
      'Resolved buildNumber=$number  buildName=${context.buildName}',
    );
```

- [ ] **Step 5: build/push/feishu 读 bag**

- `lib/src/actions/build_android_action.dart`：import 加 `import '../context_keys.dart';`；`run` 内 `--build-number=${context.buildNumber}` → `--build-number=${context.get<int>(ContextKeys.buildNumber)}`（`--build-name=${context.buildName}` 不变）。
- `lib/src/actions/build_ios_action.dart`：同样改 `--build-number=...`，import 加 context_keys。
- `lib/src/actions/push_build_tag_action.dart`：import 加 context_keys；`return vm.pushNewBuildTag(context.buildNumber);` → `return vm.pushNewBuildTag(context.get<int>(ContextKeys.buildNumber));`
- `lib/src/actions/feishu_build_notify_action.dart`：import 加 context_keys；`_formatMessage` 内 `'🚀 ${context.appName} 新版本 ${context.buildNumber} ...'` 与 `'versionCode: ${context.buildNumber}'` 两处 `context.buildNumber` → `context.get<int>(ContextKeys.buildNumber)`（`context.buildName` 不变）。

- [ ] **Step 6: 运行测试确认通过**

Run: `dart test`
Expected: 全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "refactor: migrate buildNumber to PipelineContext KV bag"
```

---

## Task 3: 迁移 buildArtifact 到 bag

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Modify: `lib/src/actions/build_android_action.dart`, `build_ios_action.dart`
- Modify: `lib/src/actions/pgyer_upload_action.dart`, `pgyer_upload_v2_action.dart`
- Modify: `lib/src/actions/google_play_action.dart`, `app_store_action.dart`
- Test: `test/pipeline_context_test.dart`, `test/actions/build_android_action_test.dart`, `test/actions/build_ios_action_test.dart`, `test/actions/google_play_action_test.dart`, `test/actions/app_store_action_test.dart`, `test/actions/pgyer_upload_action_test.dart`, `test/actions/pgyer_upload_v2_action_test.dart`

> 本任务中 `BuildAndroidAction`/`BuildIOSAction` 从 `PipelineAction<File>` 改为 `PipelineAction<void>`（泛型 R 仍存在，下任务才删）。Pgyer 仍返回 `String`（其返回值在 Task 4 处理），本任务只改 Pgyer 读 artifact 的方式。

- [ ] **Step 1: 改测试到新 API**

- `test/actions/google_play_action_test.dart:27` `c.setBuildArtifact(File('build/app-release.aab'));` → `c.put(ContextKeys.buildArtifact, File('build/app-release.aab'));`，import 加 context_keys。
- `test/actions/app_store_action_test.dart:27` `c.setBuildArtifact(File('build/ios/ipa/app.ipa'));` → `c.put(ContextKeys.buildArtifact, File('build/ios/ipa/app.ipa'));`，import 加 context_keys。
- `test/actions/pgyer_upload_action_test.dart:39` `c.setBuildArtifact(File('test.apk'));` → `c.put(ContextKeys.buildArtifact, File('test.apk'));`，import 加 context_keys。
- `test/actions/pgyer_upload_v2_action_test.dart`：所有 `..setBuildArtifact(apk)` / `..setBuildArtifact(File('test.apk'))`（第 95/109/128 行）→ `..put(ContextKeys.buildArtifact, apk)` 等，import 加 context_keys。
- `test/actions/build_android_action_test.dart`：`run` 现返回 `void`。把：

  ```dart
    final result = await action.run(context);
    ...
    expect(context.buildArtifact.path,
        'build/app/outputs/flutter-apk/app-release.apk');
    expect(result.path, context.buildArtifact.path);
  ```

  改为：

  ```dart
    await action.run(context);
    expect(context.get<File>(ContextKeys.buildArtifact).path,
        'build/app/outputs/flutter-apk/app-release.apk');
  ```

  另一处（第 58–61 行）`expect(context.buildArtifact.path, ...)` → `expect(context.get<File>(ContextKeys.buildArtifact).path, ...)`。import 加 `dart:io`（若未引）与 context_keys。
- `test/actions/build_ios_action_test.dart`：把对 `run` 返回值/`context.buildArtifact` 的断言改为 `context.get<File>(ContextKeys.buildArtifact)`；第 62 行 `await expectLater(action.run(context), throwsStateError);`（IPA 目录不存在）保持不变。import 加 context_keys。
- `test/pipeline_context_test.dart`：把 `group('buildArtifact', ...)`（第 109–122 行）替换为：

  ```dart
    group('buildArtifact via bag', () {
      test('get throws StateError when artifact absent', () {
        expect(
          () => ctx.get<File>(ContextKeys.buildArtifact),
          throwsA(isA<StateError>()),
        );
      });

      test('returns file after put', () {
        final file = File('test.apk');
        ctx.put(ContextKeys.buildArtifact, file);
        expect(ctx.get<File>(ContextKeys.buildArtifact), file);
      });
    });
  ```

- [ ] **Step 2: 运行测试确认失败**

Run: `dart test test/actions/build_android_action_test.dart test/pipeline_context_test.dart`
Expected: 编译失败 —— `setBuildArtifact`/`buildArtifact` 仍在但 build action 仍返回 File、context group 已改。

- [ ] **Step 3: PipelineContext 移除 buildArtifact 槽**

在 `lib/src/pipeline_context.dart` 删除 `_buildArtifact` 字段、`buildArtifact` getter、`setBuildArtifact`（约第 82–98 行）。`dart:io` import 若不再被其它代码使用可保留（`_findProjectRoot` 仍用 `File`/`Directory`，保留）。

- [ ] **Step 4: build action 写 bag、返回 void**

`lib/src/actions/build_android_action.dart`：

```dart
class BuildAndroidAction extends PipelineAction<void> {
  ...
  @override
  Future<void> run(PipelineContext context) async {
    final (subcommand, outputPath) = switch (buildType) { ... };  // 不变
    await _shellRunner.run('fvm', [ ... ]);                       // 不变
    final file = File(outputPath);
    context.put(ContextKeys.buildArtifact, file);
  }
}
```

`lib/src/actions/build_ios_action.dart`：

```dart
class BuildIOSAction extends PipelineAction<void> {
  ...
  @override
  Future<void> run(PipelineContext context) async {
    await _shellRunner.run('fvm', [ ... ]);   // 不变
    final file = _findIpa();
    context.put(ContextKeys.buildArtifact, file);
  }
  // _findIpa() 不变
}
```

- [ ] **Step 5: 上传 action 读 bag**

- `lib/src/actions/google_play_action.dart`：import 加 context_keys；`final artifact = context.buildArtifact;` → `final artifact = context.get<File>(ContextKeys.buildArtifact);`
- `lib/src/actions/app_store_action.dart`：同上替换。
- `lib/src/actions/pgyer_upload_action.dart`：import 加 context_keys；`final file = artifact ?? context.buildArtifact;` → `final file = artifact ?? context.get<File>(ContextKeys.buildArtifact);`（`run` 仍返回 `String`，本任务不动返回值）。
- `lib/src/actions/pgyer_upload_v2_action.dart`：import 加 context_keys；`final file = artifact ?? context.buildArtifact;`（第 70 行）→ `final file = artifact ?? context.get<File>(ContextKeys.buildArtifact);`

- [ ] **Step 6: 运行测试确认通过**

Run: `dart test`
Expected: 全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "refactor: migrate buildArtifact to PipelineContext KV bag"
```

---

## Task 4: 迁移 Pgyer 下载链接到 bag + FeishuBuildNotify 改读 key

**Files:**
- Modify: `lib/src/actions/pgyer_upload_action.dart`, `pgyer_upload_v2_action.dart`
- Modify: `lib/src/actions/feishu_build_notify_action.dart`
- Modify: `example/ci/pipelines/android_test_pipeline.dart`, `example/ci/pipelines/test_env_pipeline.dart`
- Test: `test/actions/pgyer_upload_action_test.dart`, `test/actions/pgyer_upload_v2_action_test.dart`, `test/actions/feishu_build_notify_action_test.dart`

- [ ] **Step 1: 改 Pgyer 测试 —— 断言写入 bag 而非返回值**

`test/actions/pgyer_upload_action_test.dart`：把每处 `final url = await action.run(...); expect(url, '...')` 改为运行后从 context 读。例如第 55–56 行：

```dart
    final url = await action.run(ctx());
    expect(url, 'https://www.pgyer.com/abc123');
```

→

```dart
    final context = ctx();
    await action.run(context);
    expect(context.get<String>(ContextKeys.pgyerDownloadUrl),
        'https://www.pgyer.com/abc123');
```

对第 84–85、143–144、160–162 行做同样改造（用各自已有的 `context` 变量或新建一个）。失败用例（第 99、113 行 `throwsA(isA<DeployException>())`）不变。

`test/actions/pgyer_upload_v2_action_test.dart`：同样把对 `run` 返回 URL 的断言改为 `context.get<String>(ContextKeys.pgyerDownloadUrl)`。

- [ ] **Step 2: 改 Feishu 测试 —— 用 downloadUrlKeys（key 列表）**

`test/actions/feishu_build_notify_action_test.dart`（文件顶部 import 加 context_keys）：

- 第一个用例（单链接）：在 context 上 `..put(ContextKeys.pgyerDownloadUrl, 'https://example.com/dl')`（与已有的 `..put(ContextKeys.buildNumber, 12042)` 链式），把 action 构造的 `downloadUrl: 'https://example.com/dl',` 改为 `downloadUrlKeys: [ContextKeys.pgyerDownloadUrl],`。断言 `contains('https://example.com/dl')` 不变。
- 「formats message with multiple downloadUrls」用例：改为通过两个 key 读多链接。把该用例改写为：

```dart
  test('formats message with multiple download URLs via keys', () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )
      ..put(ContextKeys.buildNumber, 12042)
      ..put('urlA', 'https://example.com/a')
      ..put('urlB', 'https://example.com/b');

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: DeployTarget.pgyer,
      downloadUrlKeys: ['urlA', 'urlB'],
      shellRunner: shell,
    );
    await action.run(context);

    expect(shell.lastJson, contains('https://example.com/a'));
    expect(shell.lastJson, contains('https://example.com/b'));
    expect(shell.lastJson, contains('🔗 下载链接'));
  });
```

- 新增一个「无 key 时不含下载行」用例：

```dart
  test('omits download line when no downloadUrlKeys provided', () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )..put(ContextKeys.buildNumber, 12042);

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: DeployTarget.pgyer,
      shellRunner: shell,
    );
    await action.run(context);

    expect(shell.lastJson, isNot(contains('🔗 下载')));
  });
```

- [ ] **Step 3: 运行测试确认失败**

Run: `dart test test/actions/feishu_build_notify_action_test.dart`
Expected: 编译失败 —— `FeishuBuildNotifyAction` 还没有 `downloadUrlKeys` 参数。

- [ ] **Step 4: Pgyer action 写 bag（可选 resultKey）、返回 void**

`lib/src/actions/pgyer_upload_action.dart`：

- 类声明 `class PgyerUploadAction extends PipelineAction<String>` → `extends PipelineAction<void>`。
- `run` 签名 `Future<String> run(...)` → `Future<void> run(...)`。
- 构造函数加可选 `String resultKey` 参数（默认 `ContextKeys.pgyerDownloadUrl`）并存为字段：

```dart
  PgyerUploadAction({
    required this.apiKey,
    this.buildUpdateDescription,
    this.artifact,
    this.resultKey = ContextKeys.pgyerDownloadUrl,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Context key under which the download URL is stored. Defaults to
  /// [ContextKeys.pgyerDownloadUrl]; override when uploading multiple
  /// artifacts in parallel so each URL lands under a distinct key.
  final String resultKey;
```

- 成功分支：

```dart
      if (response['code'] == 0) {
        final url = 'https://www.pgyer.com/${response['data']['buildKey']}';
        context.logger.success('Upload successful! Download URL: $url');
        context.put(resultKey, url);
        return;
      }
```

`lib/src/actions/pgyer_upload_v2_action.dart`：

- 类声明 `extends PipelineAction<String>` → `extends PipelineAction<void>`。
- `run` 签名 `Future<String>` → `Future<void>`。
- 构造函数同样加 `this.resultKey = ContextKeys.pgyerDownloadUrl,` 与 `final String resultKey;`（doc 同上）。
- 末尾：

```dart
    final downloadUrl = 'https://$webDomain/$shortcutUrl';
    log.success('Pgyer build ready: $downloadUrl');
    context.put(resultKey, downloadUrl);
```

（删除原 `return downloadUrl;`）

- [ ] **Step 5: FeishuBuildNotifyAction 改用 downloadUrlKeys（key 列表）**

> 设计修订：`test_env_pipeline` 并行上传两个产物、一条通知带两个链接。故用 key **列表**而非单 key，保留多链接渲染。

`lib/src/actions/feishu_build_notify_action.dart`：

- import 加 `import '../context_keys.dart';`
- 构造参数与字段：删除 `downloadUrl` / `downloadUrls`，新增：

```dart
  FeishuBuildNotifyAction({
    required this.webhookUrl,
    required this.target,
    this.downloadUrlKeys,
    ShellRunner? shellRunner,
  }) : _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Feishu bot webhook URL.
  final String webhookUrl;

  /// Deploy destination label (Pgyer, Google Play, or App Store).
  final DeployTarget target;

  /// Context keys to read download URLs from; absent/empty keys are skipped.
  /// `null` means no download line is shown.
  final List<String>? downloadUrlKeys;
  final ShellRunner _shellRunner;
```

- `_formatMessage` 内把读 url 的逻辑改为（沿用现有单/多链接 UX）：

```dart
    final urls = downloadUrlKeys == null
        ? const <String>[]
        : downloadUrlKeys!
            .map((k) => context.tryGet<String>(k))
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList();
    if (urls.isNotEmpty) {
      lines.add(sep);
      if (urls.length == 1) {
        lines.add('🔗 下载: ${urls.single}');
      } else {
        lines.add('🔗 下载链接:');
        for (var i = 0; i < urls.length; i++) {
          lines.add('  ${i + 1}. ${urls[i]}');
        }
      }
    }
```

（删除原 `downloadUrls ?? (...)` 的多链接块）

- [ ] **Step 6: 更新示例 pipeline**

**`example/ci/pipelines/android_test_pipeline.dart`**（单链接）：

```dart
    final pgyerUrl = await runAction(PgyerUploadAction(
      apiKey: ctx.pgyerApiKey,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: ctx.feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrl: pgyerUrl,
    ));
```

→

```dart
    await runAction(PgyerUploadAction(
      apiKey: ctx.pgyerApiKey,
    ));
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: ctx.feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrlKeys: [ContextKeys.pgyerDownloadUrl],
    ));
```

**`example/ci/pipelines/test_env_pipeline.dart`**（并行上传两产物 + 一条双链接通知）。Task 3 已把它改成用局部变量捕获两个产物。本步把两个并行上传写入**不同** `resultKey`，通知用 `downloadUrlKeys` 读两个 key。把 `body()` 的上传+通知段改为：

```dart
    const androidUrlKey = 'pgyerAndroidUrl';
    const iosUrlKey = 'pgyerIosUrl';

    // 并行上传（各写入不同 key，避免覆盖）
    await runParallelActions([
      PgyerUploadV2Action(
          apiKey: pgyerApiKey, artifact: androidFile, resultKey: androidUrlKey),
      PgyerUploadV2Action(
          apiKey: pgyerApiKey, artifact: iosFile, resultKey: iosUrlKey),
    ]);

    // 一条通知包含两个链接
    await runAction(FeishuBuildNotifyAction(
      webhookUrl: feishuWebhookUrl,
      target: DeployTarget.pgyer,
      downloadUrlKeys: [androidUrlKey, iosUrlKey],
    ));
```

（即：删除原 `final urls = await runParallelActions([...])` 的返回值捕获与 `downloadUrls: urls`；`androidFile`/`iosFile` 的局部捕获在 Task 3 已就位，保持不变。）

（`prod_pipeline.dart` 的 `FeishuBuildNotifyAction` 不传 url，无需改。）

- [ ] **Step 7: 运行测试确认通过**

Run: `dart test`
Expected: 全部 PASS。

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "refactor: migrate Pgyer download URL to KV bag; FeishuBuildNotify reads by key"
```

---

## Task 5: 去掉 PipelineAction 泛型 R

此时所有库 action 都是 `PipelineAction<void>`，可安全移除泛型。

**Files:**
- Modify: `lib/src/actions/pipeline_action.dart`
- Modify: `lib/src/pipeline.dart`
- Modify: 所有 `lib/src/actions/*.dart` 中 `extends PipelineAction<void>` → `extends PipelineAction`
- Test: `test/pipeline_test.dart`, `test/pipeline_parallel_test.dart`, `test/actions/pipeline_action_test.dart`

- [ ] **Step 1: 改测试到非泛型 API**

`test/actions/pipeline_action_test.dart`：`class _TestAction extends PipelineAction<void>` → `extends PipelineAction`（`run` 已是 `Future<void>`，其余不变）。

`test/pipeline_test.dart`：
- `class _RecordingAction extends PipelineAction<void>` → `extends PipelineAction`。
- 删除 `_SimpleAction`（泛型 `<String>`）类、`_ValuePipeline` 类，以及 `'runAction returns the action result'` 测试（第 197–202 行）。
- `_FailActionPipeline` 用了 `_SimpleAction`，改用 `_RecordingAction`：

```dart
  @override
  Future<void> body() async {
    await runAction(_RecordingAction('ok-action', []));
    await runAction(_RecordingAction('will-fail', [], willThrow: true));
  }
```

`test/pipeline_parallel_test.dart`：
- `_TestAction`/`_FailingAction` 改为非泛型、记录到 bag 而非返回值：

```dart
class _TestAction extends PipelineAction {
  _TestAction(this.value, {this.delay = Duration.zero});
  final int value;
  final Duration delay;
  @override
  Future<void> run(PipelineContext context) async {
    await Future.delayed(delay);
    context.put('parallel-$value', value);
  }
}

class _FailingAction extends PipelineAction {
  @override
  Future<void> run(PipelineContext context) async {
    throw StateError('oops');
  }
}
```

- 第一个用例去掉对返回值的断言：

```dart
      await pipeline.runParallelActions([
        _TestAction(1, delay: const Duration(milliseconds: 50)),
        _TestAction(2, delay: const Duration(milliseconds: 10)),
        _TestAction(3, delay: const Duration(milliseconds: 30)),
      ]);

      expect(pipeline.executedActions.length, 3);
      expect(pipeline.allSucceeded, isTrue);
```

（删除 `final results = ...` 与 `expect(results, [1, 2, 3]);`）

- [ ] **Step 2: 运行测试确认失败**

Run: `dart test test/actions/pipeline_action_test.dart`
Expected: 编译失败 —— `PipelineAction` 仍是泛型，`extends PipelineAction`（无类型实参）在 base 仍要求 `<R>` 时报错；或反之。以编译错误为准。

- [ ] **Step 3: PipelineAction 去泛型**

`lib/src/actions/pipeline_action.dart`：

```dart
abstract class PipelineAction {
  String get name => this.runtimeType.toString();

  String get description {
    final className = runtimeType.toString();
    return className
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .toLowerCase()
        .trim();
  }

  ActionStatus? status;
  Duration? duration;
  Object? error;
  StackTrace? stackTrace;

  bool get hasRun => status != null;

  /// Executes this action against [context]. Results are written into
  /// [context] via [PipelineContext.put]; this method returns no value.
  Future<void> run(PipelineContext context);
}
```

（doc 注释第 4–7 行关于 `[R]` 的描述同步删掉。）

- [ ] **Step 4: Pipeline 去泛型**

`lib/src/pipeline.dart`：

```dart
  /// Runs [action] with section logging, timing, and status recording.
  Future<void> runAction(PipelineAction action) async {
    executedActions.add(action);
    return _runTracked(action);
  }

  /// Runs multiple actions in parallel, recording each one's status.
  Future<void> runParallelActions(List<PipelineAction> actions) async {
    executedActions.addAll(actions);
    await Future.wait(actions.map(_runTracked));
  }

  Future<void> _runTracked(PipelineAction action) async {
    final log = context.logger;
    log.section(action.name);
    final stopwatch = Stopwatch()..start();
    try {
      await action.run(context);
      stopwatch.stop();
      log.closeSection(true, action.name, stopwatch.elapsed);
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
    } catch (e, stackTrace) {
      stopwatch.stop();
      log.closeSection(false, action.name, stopwatch.elapsed);
      action
        ..status = ActionStatus.failed
        ..duration = stopwatch.elapsed
        ..error = e
        ..stackTrace = stackTrace;
      rethrow;
    }
  }
```

- [ ] **Step 5: 所有 action 去类型实参**

把以下文件里的 `extends PipelineAction<void>` 改为 `extends PipelineAction`：
`resolve_build_version_action.dart`, `build_android_action.dart`, `build_ios_action.dart`, `pgyer_upload_action.dart`, `pgyer_upload_v2_action.dart`, `google_play_action.dart`, `app_store_action.dart`, `push_build_tag_action.dart`, `feishu_build_notify_action.dart`, `feishu_notify_action.dart`, `check_git_status_action.dart`, `clean_project_action.dart`, `swap_info_plist_action.dart`, `restore_workspace_action.dart`。

快速核对命令（应无输出）：

```bash
grep -rn "PipelineAction<" lib/
```

- [ ] **Step 6: 运行全部测试确认通过**

Run: `dart test`
Expected: 全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "refactor: drop generic R from PipelineAction; run() returns Future<void>"
```

---

## Task 6: 收尾验证

- [ ] **Step 1: 静态分析无警告**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 2: 示例工程编译检查**

Run: `cd example && dart analyze ci/ && cd ..`
Expected: 无错误（确认示例 pipeline 改动正确）。

- [ ] **Step 3: 全量测试**

Run: `dart test`
Expected: 全绿。

- [ ] **Step 4: 残留旧 API 扫描（应无输出）**

Run:

```bash
grep -rn "setBuildArtifact\|resolveBuildVersion\|\.buildArtifact\b\|context.buildNumber\|PipelineAction<\|downloadUrls" lib/ example/ci/ test/
```

Expected: 无输出（`buildName` 保留，不在扫描列；如有命中需修正）。

---

## Self-Review Notes

- **Spec 覆盖**：bag 形态（Task 1）、去泛型 R（Task 5）、迁移边界只动产出物（Task 2–4，config/infra 字段未触）、`buildName` 派生 getter（Task 2 Step 3）、`get` 抛错 / `tryGet` 返 null（Task 1）、集中常量 `ContextKeys`（Task 1）、通知读 key 列表 `downloadUrlKeys` + Pgyer `resultKey`（Task 4，支持 `test_env` 并行多链接）—— 均有对应任务。
- **类型一致**：全程 `get<T>` / `put` / `tryGet<T>`、`ContextKeys.{buildNumber,buildArtifact,pgyerDownloadUrl}`、`resultKey`、`downloadUrlKeys`（List），命名贯穿一致。
- **绿色边界**：Task 1 additive；Task 2–4 在保留泛型 R 的前提下把 action 逐组改为 `<void>`；Task 5 才移除泛型 —— 每个 Task 结束 `dart test` 全绿。
