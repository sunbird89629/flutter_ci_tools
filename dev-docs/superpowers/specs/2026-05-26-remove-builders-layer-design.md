# 移除 Builder 层重构设计

## 背景

当前 `lib/src/builders/` 下的 `AndroidBuilder` / `IOSBuilder` 是 `BuildAndroidAction` / `BuildIOSAction` 的底层封装，呈一对一关系且无其他消费者。两层之间的间接没有带来可复用性，反而增加了文件数量与测试维护成本。

## 目标

将两个 Builder 类的实现下沉到对应 Action 中，去掉中间层。

## 改动清单

### 删除

- `lib/src/builders/android_builder.dart`
- `lib/src/builders/ios_builder.dart`
- 空目录 `lib/src/builders/`
- `test/android_builder_test.dart`
- `test/ios_builder_test.dart`
- `lib/flutter_ci_tools.dart` 中两条 `export 'src/builders/...'` —— **这是破坏性 API 变更**，需在 commit message 中明确说明

### 修改

**`BuildAndroidAction`** (`lib/src/actions/build_android_action.dart`)

- 构造函数注入点：`AndroidBuilder?` → `ShellRunner?`，默认 `DefaultShellRunner()`
- `run()` 内联：根据 `buildType` 选 `apk` / `appbundle` 子命令，调用 `fvm flutter build <sub> --build-name=… --build-number=… --dart-define=ENV=…`，返回对应的 `File`
- 保留 `AndroidBuildType` 枚举与 `name` getter

**`BuildIOSAction`** (`lib/src/actions/build_ios_action.dart`)

- 构造函数注入点：`IOSBuilder?` → `ShellRunner?`
- `run()` 内联 `buildIpa` 调用 + 私有 `_findIpa()` 方法（含原有 `StateError` 校验）
- 保留 `name` getter

### 测试改造

**`test/actions/build_android_action_test.dart`** 与 **`test/actions/build_ios_action_test.dart`**

- 移除 `_FakeAndroidBuilder` / `_FakeIOSBuilder`
- 改用 `_FakeShellRunner`（断言传入的 `fvm flutter build …` 命令字符串）
- 从原 `test/android_builder_test.dart` / `test/ios_builder_test.dart` 搬运 shell 命令断言，覆盖率不丢

## 非目标

- 不改 `PipelineContext`、`PipelineAction` 接口
- 不动其他 Action
- 不引入新的抽象层

## 兼容性

公开 API 移除 `AndroidBuilder` / `IOSBuilder` 的 export，commit message 标注 `BREAKING CHANGE`。

## 验证

- `dart test` 全绿
- `dart analyze` 无新增告警
