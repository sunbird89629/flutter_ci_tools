# CLI Args Pass-Through to PipelineContext

**Date:** 2026-05-27
**Status:** Active

## Motivation

每个 pipeline 是用户自己写的，用户决定构建哪些平台、使用哪些参数。框架不应该硬编码参数解析逻辑，而应该透传原始参数，让 pipeline 自行解释。

## Design

### 1. PipelineContext 新增 rawArgs

```dart
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.rawArgs,
  });

  final String appName;
  final int seedBuildNumber;

  /// 用户通过命令行传入的完整原始参数。
  /// 例如 `dart run ci/build.dart test android --debug`
  /// 会得到 `['test', 'android', '--debug']`。
  final List<String> rawArgs;

  /// 便捷参数解析器。
  late final ArgsParser args = ArgsParser(rawArgs);
}
```

### 2. ArgsParser 工具类

新增 `lib/src/utils/args_parser.dart`：

```dart
/// 简单的命令行参数解析工具。
class ArgsParser {
  ArgsParser(this.args);

  /// 原始参数列表。
  final List<String> args;

  /// 是否包含某个参数（精确匹配）。
  bool has(String arg) => args.contains(arg);

  /// 获取 `--key=value` 形式的值。
  String? getOption(String key) {
    final prefix = '$key=';
    for (final arg in args) {
      if (arg.startsWith(prefix)) return arg.substring(prefix.length);
    }
    return null;
  }

  /// 获取第一个非 `--` 开头的 positional 参数。
  String? get positional {
    for (final arg in args) {
      if (!arg.startsWith('--')) return arg;
    }
    return null;
  }

  /// 获取所有非 `--` 开头的 positional 参数。
  List<String> get positionalArgs =>
      args.where((a) => !a.startsWith('--')).toList();
}
```

### 3. BuildPipeline 签名变更

```dart
abstract class BuildPipeline {
  PipelineContext createContext(List<String> args);

  Future<void> run(List<String> args) async {
    context = createContext(args);
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e) {
        Logger.error('afterBuild failed', e);
      }
    }
  }
}
```

### 4. PipelineRegistry 透传

```dart
// run() 中
await pipeline.run(args);

// 交互式选择中
await list[choice - 1].run([]);
```

交互式选择时 args 为空列表，pipeline 需要有合理的默认行为。

### 5. Example Pipeline 用法

```dart
class TestPipeline extends BuildPipeline {
  @override
  PipelineContext createContext(List<String> args) => ExampleAppContext(args: args);

  @override
  Future<void> body() async {
    // 用户传什么就构建什么，没传就两个都构建
    final buildAndroid = context.args.has('android') || !context.args.has('ios');
    final buildIos = context.args.has('ios') || !context.args.has('android');

    if (buildAndroid) { /* ... */ }
    if (buildIos) { /* ... */ }
  }
}
```

## 影响范围

| 文件 | 变更 |
|------|------|
| `lib/src/utils/args_parser.dart` | 新增 |
| `lib/src/pipeline_context.dart` | 新增 `rawArgs` 字段 |
| `lib/src/pipeline.dart` | `run()` 和 `createContext()` 接收 `List<String>` |
| `lib/src/pipeline_registry.dart` | 透传 args |
| `lib/flutter_ci_tools.dart` | 导出 `ArgsParser` |
| `example/ci/pipelines/*.dart` | 适配新签名 |
| 所有测试 | 适配新签名 |

## 测试计划

- `ArgsParser` 单元测试：`has()`、`getOption()`、`positional`、`positionalArgs`
- `PipelineContext` 测试：`rawArgs` 和 `args` 访问
- `PipelineRegistry` 测试：args 透传到 pipeline
- 现有测试适配：所有 `PipelineContext` 构造加 `rawArgs: []`
