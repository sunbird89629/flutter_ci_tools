# PipelineContext 工具方法 — Design

Date: 2026-05-31
Status: Approved (ready for implementation plan)

## Goal

给 `PipelineContext` 增加若干便捷工具方法，让 actions 不必各自硬编码路径假设。
首批实现两类：

- **projectRoot** — 当前 Flutter 项目根目录。
- **pubspec 信息** — 读取 `pubspec.yaml` 的 `name` 与 `version` 字段。

## Why

目前所有 action 都假设当前工作目录就是项目根（如 `build_ios_action.dart` 直接
用相对路径 `build/ios/ipa`），项目里没有任何统一的"项目根目录"或"读 pubspec"
工具。把这类能力收敛到 `PipelineContext` 上，作为所有 action 的共享入口。

## Scope

### In scope

- 在 `lib/src/pipeline_context.dart` 的 `PipelineContext` 上新增三个惰性 getter：
  `projectRoot`、`pubspecName`、`pubspecVersion`。
- 对应的单元测试 `test/pipeline_context_test.dart`。

### Out of scope（YAGNI，本次不做）

- `pathFromRoot(...)` 路径拼接辅助。
- 临时目录 / 临时文件辅助。
- 注入式 `ProjectLocator`（interface + impl）。本次按"方案 B"直接落在
  `PipelineContext` 内，不引入新的可注入组件。
- 引入 `package:yaml`。本次用轻量正则解析。

## Design

全部改动集中在 `lib/src/pipeline_context.dart`，给 `PipelineContext` 加三个
`late final` getter（惰性求值，不访问就不碰文件系统）：

```dart
/// Flutter 项目根目录：从 Directory.current 向上递归查找含 pubspec.yaml 的目录。
late final Directory projectRoot = _findProjectRoot();

/// pubspec.yaml 的 name 字段。
late final String pubspecName = _readPubspecField('name');

/// pubspec.yaml 的 version 字段（原始字符串，如 "0.1.0"）。
late final String pubspecVersion = _readPubspecField('version');
```

实现要点：

- `_findProjectRoot()`：从 `Directory.current` 起逐级向上查找 `pubspec.yaml`；
  到文件系统根仍未找到则抛 `StateError`（中文提示，沿用文件内既有风格）。
- `_pubspecContent`：`late final`，从 `projectRoot/pubspec.yaml` 读一次并缓存。
- `_readPubspecField(key)`：用正则 `^<key>:\s*(.+)$`（multiline，行首无缩进表示
  顶层字段）匹配；对结果 `trim()`，去掉行尾 `#` 注释和首尾引号；找不到则抛
  `StateError`。

## Error Handling

- `projectRoot` 找不到 `pubspec.yaml`：抛 `StateError`，提示当前目录及向上未找到。
- `pubspecName` / `pubspecVersion` 字段缺失：抛 `StateError`，提示字段名。

## Testing

`test/pipeline_context_test.dart`：

- `projectRoot` 能定位到本包根目录（`dart test` 运行时 cwd 即含 pubspec）。
- `pubspecName == 'flutter_ci_tools'`，`pubspecVersion == '0.1.0'`。
- 临时目录构造嵌套子目录场景，验证向上查找能力。
- 无 pubspec 的目录下访问 `projectRoot` 抛 `StateError`。

注：涉及 `Directory.current` 的测试需在用例内临时切换 cwd 并在结束时恢复。
