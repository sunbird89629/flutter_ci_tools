# Pipeline Lifecycle Methods + Registry

## Motivation

当前 `build.dart` 入口文件硬编码了 pipeline 的选择逻辑（switch 语句）。每新增一个 pipeline，都需要修改入口文件。pipeline 也没有自描述能力——名称、描述、帮助文档都散落在 build.dart 的 usage 字符串中。

目标：每个 pipeline 自带元数据（name/description/help），库提供 `PipelineRegistry` 自动处理 CLI 解析和帮助输出，build.dart 只需注册 pipeline 即可。

## Design

### BuildPipeline — 新增生命周期方法

在 `BuildPipeline` 抽象类上新增 3 个抽象 getter：

```dart
abstract class BuildPipeline {
  // 新增：生命周期方法
  String get name;          // CLI 选择键，如 'test'、'prod'
  String get description;   // 一行描述，用于帮助列表
  String get help;          // 详细帮助文档

  // 保留：构建环境标识
  String get envName;       // 如 'test'、'prod'，用于 build_info 和 flutter build

  // ... 其余不变
}
```

`name` 和 `envName` 职责不同：
- `name` — CLI 选择键，面向用户输入
- `envName` — 构建环境标识，面向构建系统

### PipelineRegistry

新文件 `lib/src/pipeline_registry.dart`：

```dart
class PipelineRegistry {
  final Map<String, BuildPipeline> _pipelines = {};

  void register(BuildPipeline pipeline) {
    if (_pipelines.containsKey(pipeline.name)) {
      throw ArgumentError('Pipeline "${pipeline.name}" is already registered');
    }
    _pipelines[pipeline.name] = pipeline;
  }

  Future<void> run(List<String> args);
}
```

**CLI 行为：**

| 命令 | 行为 |
|------|------|
| `dart run ci/build.dart` | 打印全局帮助（所有可用 pipeline 列表） |
| `dart run ci/build.dart test` | 执行 `TestPipeline.run()` |
| `dart run ci/build.dart test android` | 执行 `TestPipeline.runAndroidOnly()` |
| `dart run ci/build.dart test ios` | 执行 `TestPipeline.runIOSOnly()` |
| `dart run ci/build.dart test --help` | 打印 `TestPipeline.help` |

**全局帮助输出格式：**

```
Usage: dart run ci/build.dart <pipeline> [android|ios]

Available pipelines:
  test                 构建并部署到测试环境 (Pgyer)
  prod                 构建并部署到生产环境 (Google Play / App Store)

Run "dart run ci/build.dart <pipeline> --help" for pipeline-specific help.
```

### build.dart 改造

入口文件简化为注册 + 运行：

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'pipelines/prod_pipeline.dart';
import 'pipelines/test_pipeline.dart';

Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(TestPipeline())
    ..register(ProdPipeline());

  await registry.run(args);
}
```

### 子类适配

每个 pipeline 实现 3 个新 getter：

**TestPipeline：**

```dart
class TestPipeline extends BuildPipeline {
  @override
  String get name => 'test';

  @override
  String get description => '构建并部署到测试环境 (Pgyer)';

  @override
  String get help => '''
Test Pipeline
构建测试版本并上传到蒲公英。

Usage: dart run ci/build.dart test [android|ios]
  android    仅构建 Android
  ios        仅构建 iOS
不指定平台时同时构建两个平台。''';

  // ... 其余不变
}
```

**ProdPipeline：** 类似，name 为 'prod'，help 描述生产环境构建流程。

### 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `lib/src/pipeline.dart` | 修改 | BuildPipeline 加 3 个抽象 getter |
| `lib/src/pipeline_registry.dart` | 新增 | PipelineRegistry 类 |
| `lib/flutter_ci_tools.dart` | 修改 | 新增 export pipeline_registry.dart |
| `example/ci/build.dart` | 修改 | 改用 PipelineRegistry |
| `example/ci/pipelines/test_pipeline.dart` | 修改 | 实现 name/description/help |
| `example/ci/pipelines/prod_pipeline.dart` | 修改 | 实现 name/description/help |

## What Stays the Same

- `envName` — 保留，用于构建环境标识
- `run()` / `runAndroidOnly()` / `runIOSOnly()` — 不变
- `CIToolsConfig`、`BuildMetadata`、`DeployService` 等所有其他抽象类
- 现有 pipeline 的构建和部署逻辑
- `runStep()` 辅助函数
