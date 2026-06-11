# Logging Improvements Design

Status: Accepted

## Motivation

构建日志（如 `example/build.log`）存在以下问题：

1. **并行日志交错混乱** — 两个 `PgyerUploadV2Action` 并发运行时日志互相穿插
2. **Shell 输出噪音大** — Flutter 升级提醒、pub 版本警告、Gradle/Xcode 构建输出直接透传
3. **没有层级感** — sub-step 和顶层 action 的日志在视觉上同级
4. **时间戳不统一** — 只有 shell 命令带时间戳
5. **CI 不友好** — 没有纯文本输出模式

## Design Decisions

| 决策 | 结论 |
|------|------|
| 日志级别 | `info`（始终显示）+ `verbose`（shell 透传，`--verbose` 才显示） |
| 并行日志 | 不加强制前缀，由 action 自己的日志内容区分 |
| 层级缩进 | `Pipeline._runTracked` 自动 indent/outdent，每级 2 空格 |
| 时间戳 | 所有 info 级别输出都带 `[HH:MM:SS]` |
| CI 模式 | `--no-color` CLI 参数 |
| 进度反馈 | 命令结束时显示耗时 |
| Logger 类型 | 实例类，通过 `context.logger` 访问 |

## Architecture

### Logger (实例化)

```dart
class Logger {
  final bool noColor;
  final bool verbose;
  int _indentLevel = 0;

  Logger({this.noColor = false, this.verbose = false});

  void info(String msg);
  void success(String msg);
  void warning(String msg);
  void error(String msg);
  void section(String title);   // 打印 header 并 indent++
  void closeSection(bool success, String name, Duration duration);
  void verbose(String line);    // --verbose 时输出到 stdout
  void command(String cmd);     // info 级别，无缩进
}
```

- `noColor` → ANSI 码和 emoji 替换为空
- `section()` 自动 `indent()`，`closeSection()` 自动 `outdent()`
- `verbose()` 不加时间戳和缩进，直接流式输出

### CLI 参数

`ArgsParser` 新增 `verbose` 和 `noColor` getter：

```dart
bool get verbose => has('--verbose');
bool get noColor => has('--no-color');
```

### Pipeline 注入

```dart
// Pipeline.run()
context = createContext(args); // 内部会根据 args 创建 Logger 并注入
```

```dart
// PipelineContext 新增字段
late final Logger logger; // 由 Pipeline.run() 注入
```

### ShellRunnerImpl 注入 Logger

```dart
class ShellRunnerImpl implements ShellRunner {
  final Logger logger;                 // 新增
  ShellRunnerImpl({required this.logger});

  // run() 中:
  //   logger.command(cmd)          替代 Logger.command(cmd)
  //   stdout/stderr → logger.verbose(line)
}
```

### Pipeline._runTracked 生命周期

```
logger.section(action.name);        // indent++
try {
  await action.run(context);
  logger.closeSection(true, action.name, duration);
} catch (e) {
  logger.closeSection(false, action.name, duration);
  rethrow;
}
```

### 改动文件清单

| 文件 | 改动 |
|------|------|
| `lib/src/utils/logger.dart` | 静态 → 实例，新增方法，noColor/verbose 支持 |
| `lib/src/utils/shell_runner_impl.dart` | 注入 Logger，verbose 输出替代直接 stdout/stderr |
| `lib/src/utils/shell_runner.dart` | 无变动 |
| `lib/src/pipeline.dart` | `_runTracked` 管理 indent/outdent |
| `lib/src/pipeline_context.dart` | 新增 `logger` 字段 |
| `lib/src/actions/*.dart` | `Logger.xxx()` → `context.logger.xxx()` |
| `lib/src/actions/pipeline_action.dart` | 无变动 |
| `test/*.dart` | `_FakeLogger` + 各 action test 注入 logger |

## Example Output (预期)

```
[22:03:45] 🚀 Resolve Build Version...
[22:03:45] ⚠️  No "builds/*" tag found. Seeding from 10000.
[22:03:45] ℹ️  Resolved buildNumber=10000  buildName=1.0.0
[22:03:45] ✅ Finished: Resolve Build Version (6.5s)

[22:03:45] 🚀 Clean Project...
[22:03:45]   fvm flutter clean
[22:03:52]   fvm flutter pub get
[22:03:52] ✅ Finished: Clean Project (7.0s)

[22:03:58] 🚀 Build Android...
[22:03:58]   fvm flutter build apk --build-name=1.0.0 --build-number=10000
[22:04:43] ✅ Finished: Build Android (45.6s)

[22:04:43] 🚀 Build iOS...
[22:04:43]   fvm flutter build ipa --export-method=development ...
[22:05:26] ✅ Finished: Build iOS (39.3s)

[22:05:26] 🚀 Upload to Pgyer (V2)...
[22:05:26]   ℹ️  Probing Pgyer API domains...
[22:05:26]   ℹ️  Using domain api.pgyer.com
[22:05:26]   ℹ️  Requesting COS upload token...
[22:05:26]   ℹ️  Uploading flutter_ci_tools_example.ipa (6107149 bytes) to COS...
[22:05:27]   ✅ Uploaded to COS.
[22:05:28]   ✅ Pgyer build ready: https://pgyer.com/F-ios-5t
[22:05:28] ✅ Finished: Upload to Pgyer (V2) (2.0s)

[22:05:28] 🚀 Upload to Pgyer (V2)...
[22:05:28]   ℹ️  Probing Pgyer API domains...
[22:05:28]   ℹ️  Using domain api.pgyer.com
[22:05:28]   ℹ️  Requesting COS upload token...
[22:05:28]   ℹ️  Uploading app-release.apk (43789482 bytes) to COS...
[22:05:29]   ✅ Uploaded to COS.
[22:05:30]   ✅ Pgyer build ready: https://pgyer.com/f-android-2
[22:05:30] ✅ Finished: Upload to Pgyer (V2) (2.0s)

────────────────────────────────────
执行摘要
────────────────────────────────────
✅ Resolve Build Version (6.5s)
✅ Check Git Status (25ms)
✅ Clean Project (7.0s)
✅ Build Android (45.6s)
✅ Build iOS (39.3s)
✅ Upload to Pgyer (V2) (2.0s)      ← iOS
✅ Upload to Pgyer (V2) (2.0s)      ← Android
✅ Send Feishu Build Notification (3.0s)
✅ Push Build Tag (4.8s)
────────────────────────────────────
```
