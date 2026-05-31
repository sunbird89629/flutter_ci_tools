# PipelineContext 工具方法 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `PipelineContext` 增加 `projectRoot`、`pubspecName`、`pubspecVersion` 三个惰性工具 getter。

**Architecture:** 全部落在 `lib/src/pipeline_context.dart` 内（方案 B），用 `late final` 惰性求值：`projectRoot` 从 `Directory.current` 向上找 `pubspec.yaml`，pubspec 字段用轻量正则解析。不引入新依赖、不引入可注入组件。

**Tech Stack:** Dart, `dart:io`, `package:test`。

---

## File Structure

- **Modify** `lib/src/pipeline_context.dart` — 给 `PipelineContext` 加三个 `late final` getter 及私有辅助方法。`dart:io` 已 import。
- **Create** `test/pipeline_context_test.dart` — 单元测试。

---

### Task 1: projectRoot — 向上查找 pubspec.yaml

**Files:**
- Test: `test/pipeline_context_test.dart`
- Modify: `lib/src/pipeline_context.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/pipeline_context_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

PipelineContext _ctx() =>
    PipelineContext(appName: 'demo', seedBuildNumber: 100000);

void main() {
  group('projectRoot', () {
    test('定位到含 pubspec.yaml 的包根目录', () {
      final root = _ctx().projectRoot;
      expect(File('${root.path}/pubspec.yaml').existsSync(), isTrue);
    });

    test('从嵌套子目录向上查找', () {
      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_');
      try {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: tmp_pkg\n');
        final nested = Directory('${tmp.path}/a/b/c')..createSync(recursive: true);
        Directory.current = nested;
        // canonicalize 消除 macOS /private/var 与 /var 符号链接差异
        expect(
          _ctx().projectRoot.resolveSymbolicLinksSync(),
          equals(tmp.resolveSymbolicLinksSync()),
        );
      } finally {
        Directory.current = original;
        tmp.deleteSync(recursive: true);
      }
    });

    test('找不到 pubspec.yaml 时抛 StateError', () {
      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_empty_');
      try {
        Directory.current = tmp;
        expect(() => _ctx().projectRoot, throwsStateError);
      } finally {
        Directory.current = original;
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `dart test test/pipeline_context_test.dart -n projectRoot`
Expected: 编译/运行失败 —— `PipelineContext` 没有 `projectRoot` getter。

- [ ] **Step 3: 实现 projectRoot**

在 `lib/src/pipeline_context.dart` 的 `PipelineContext` 类内（`setBuildArtifact` 之后、类结束前）加入：

```dart
  /// Flutter 项目根目录。
  ///
  /// 从 [Directory.current] 起逐级向上查找含 `pubspec.yaml` 的目录。
  /// 到文件系统根仍未找到则抛 [StateError]。
  late final Directory projectRoot = _findProjectRoot();

  Directory _findProjectRoot() {
    var dir = Directory.current.absolute;
    while (true) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw StateError(
          '未找到 pubspec.yaml：从 ${Directory.current.path} 向上查找至文件系统根均无结果。',
        );
      }
      dir = parent;
    }
  }
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `dart test test/pipeline_context_test.dart -n projectRoot`
Expected: PASS（3 个测试全过）。

- [ ] **Step 5: 提交**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart
git commit -m "feat: add projectRoot lookup to PipelineContext"
```

---

### Task 2: pubspecName / pubspecVersion — 轻量正则解析

**Files:**
- Test: `test/pipeline_context_test.dart`
- Modify: `lib/src/pipeline_context.dart`

- [ ] **Step 1: 写失败测试**

在 `test/pipeline_context_test.dart` 的 `main()` 内、`projectRoot` group 之后追加：

```dart
  group('pubspec 字段', () {
    test('读取本包 name 与 version', () {
      final ctx = _ctx();
      expect(ctx.pubspecName, equals('flutter_ci_tools'));
      expect(ctx.pubspecVersion, equals('0.1.0'));
    });

    test('字段缺失时抛 StateError', () {
      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_noname_');
      try {
        // 只写 version，不写 name
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('version: 9.9.9\n');
        Directory.current = tmp;
        expect(() => _ctx().pubspecName, throwsStateError);
      } finally {
        Directory.current = original;
        tmp.deleteSync(recursive: true);
      }
    });
  });
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `dart test test/pipeline_context_test.dart -n "pubspec 字段"`
Expected: 编译/运行失败 —— 没有 `pubspecName` / `pubspecVersion` getter。

- [ ] **Step 3: 实现 pubspec 字段解析**

在 `lib/src/pipeline_context.dart` 的 `PipelineContext` 类内，紧接 `_findProjectRoot()` 之后加入：

```dart
  /// `pubspec.yaml` 的 `name` 字段。
  late final String pubspecName = _readPubspecField('name');

  /// `pubspec.yaml` 的 `version` 字段（原始字符串，如 `"0.1.0"`）。
  late final String pubspecVersion = _readPubspecField('version');

  late final String _pubspecContent =
      File('${projectRoot.path}/pubspec.yaml').readAsStringSync();

  String _readPubspecField(String key) {
    final match = RegExp('^$key:\\s*(.+)\$', multiLine: true)
        .firstMatch(_pubspecContent);
    if (match == null) {
      throw StateError('pubspec.yaml 中未找到字段：$key。');
    }
    var value = match.group(1)!;
    // 去掉行尾注释
    final hash = value.indexOf('#');
    if (hash != -1) value = value.substring(0, hash);
    value = value.trim();
    // 去掉首尾引号
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
```

- [ ] **Step 4: 运行全部测试，确认通过**

Run: `dart test test/pipeline_context_test.dart`
Expected: PASS（projectRoot 3 个 + pubspec 字段 2 个全过）。

- [ ] **Step 5: 跑整包测试确认无回归**

Run: `dart test`
Expected: 全部通过。

- [ ] **Step 6: 提交**

```bash
git add lib/src/pipeline_context.dart test/pipeline_context_test.dart
git commit -m "feat: add pubspecName/pubspecVersion to PipelineContext"
```

---

## Self-Review

- **Spec coverage:** projectRoot（Task 1）、pubspecName/pubspecVersion（Task 2）、StateError 错误处理（两个 Task 的失败测试）、向上查找与缺失场景测试（Task 1/2）—— 全覆盖。Out-of-scope 项未实现，符合 spec。
- **Placeholder scan:** 无 TBD/TODO，所有步骤含完整代码与命令。
- **Type consistency:** `projectRoot`/`pubspecName`/`pubspecVersion`/`_readPubspecField`/`_findProjectRoot`/`_pubspecContent` 命名在 plan 内一致。
