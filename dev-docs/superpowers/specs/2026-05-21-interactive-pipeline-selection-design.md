# Interactive Pipeline Selection

## Motivation

当前 `PipelineRegistry` 在无参数时打印帮助并退出。用户希望有一个交互式选择界面，通过序号选择 pipeline。

## Design

### Help 输出加序号

`_printUsage()` 输出格式变更：

```
Available pipelines:
  1. test                 构建并部署到测试环境 (Pgyer)
  2. prod                 构建并部署到生产环境 (Google Play / App Store)
  3. android_test         android 测试环境版本构建，用于测试脚本的功能
```

### 交互式选择

`run()` 方法在 `args.isEmpty` 时不再 `exit(64)`，改为：

1. 打印带序号的 pipeline 列表 + `0. 退出`
2. 读取用户输入（stdin.readLineSync）
3. 有效序号 → 执行对应 pipeline.run()
4. `0` → exit(0)
5. 无效输入 → 重新提示

交互模式仅支持选择 pipeline 并执行 `run()`，不支持 platform 参数。需要 platform 过滤时使用 CLI 参数。

### 文件变更

| 文件 | 变更 |
|------|------|
| `lib/src/pipeline_registry.dart` | 修改 `_printUsage()` 加序号，`run()` 加交互逻辑 |
| `test/pipeline_registry_test.dart` | 更新测试 |

## What Stays the Same

- CLI 参数模式行为不变（`dart run ci/build.dart test` 仍然直接执行）
- `--help` 行为不变
- `register()` 和 `pipelines` getter 不变
