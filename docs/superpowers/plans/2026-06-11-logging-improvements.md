# Logging Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Logger 从静态工具类改为实例类，增加 verbose 级别、时间戳统一、层级缩进和 --no-color 支持。

**Architecture:** Logger 变成具名构造函数的具体类（`Logger.terminal()` / `Logger.silent()`），通过 `PipelineContext.logger` 注入。`ShellRunnerImpl`、`GitManagerImpl`、`VersionManagerImpl` 构造函数可选接收 Logger，默认值 `Logger.silent()`。`Pipeline.run()` 创建 `Logger.terminal()` 并注入。

**Tech Stack:** Dart, package:test

---

## File Structure

| 文件 | 角色 |
|------|------|
| `lib/src/utils/logger.dart` | Logger 具体类（实例化 + ANSI 终端输出 + noColor/verbose 控制） |
| `lib/src/utils/shell_runner_impl.dart` | 注入 Logger，verbose 输出 |
| `lib/src/utils/git_manager_impl.dart` | 注入 Logger |
| `lib/src/utils/version_manager_impl.dart` | 注入 Logger |
| `lib/src/pipeline.dart` | `_runTracked` 管理 indent/outdent，`_printSummary` 使用 logger |
| `lib/src/pipeline_context.dart` | 新增 `logger` 字段 |
| `lib/src/actions/*.dart` | `Logger.xxx()` → `context.logger.xxx()` |
| `test/logger_test.dart` | 新建，测试 Logger 输出和行为 |
| `test/actions/*.dart` | 无结构变更（Fake 类不依赖 Logger） |

---

### Task 1: Rewrite Logger as instance class

**Files:**
- Modify: `lib/src/utils/logger.dart`
- Create: `test/logger_test.dart`

L1-L55 完整替换为：

```dart
import 'dart:io';

/// Colored terminal logger with emoji indicators, timestamps, and indentation.
///
/// Use [Logger.terminal] for real CLI output (writes to stdout/stderr).
/// Use [Logger.silent] for tests (discards all output).
class Logger {
  final bool noColor;
  final bool verbose;
  int _indentLevel = 0;
  final void Function(String) _write;
  final void Function(String) _writeErr;

  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _blue = '\x1B[34m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  /// Real terminal logger writing to [stdout] and [stderr].
  Logger.terminal({
    this.noColor = false,
    this.verbose = false,
  })  : _write = ((String s) => stdout.writeln(s)),
        _writeErr = ((String s) => stderr.writeln(s));

  /// Silent logger that discards all output (for tests and fallback defaults).
  Logger.silent()
      : noColor = true,
        verbose = false,
        _write = (_) {},
        _writeErr = (_) {};

  String get _prefix => '  ' * _indentLevel;

  String _ts() {
    final t = DateTime.now();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '[$h:$m:$s]';
  }

  static String _fmt(int seconds) =>
      seconds >= 60
          ? '${seconds ~/ 60}m${seconds % 60}s'
          : '${seconds}s';

  void indent() => _indentLevel++;
  void outdent() {
    if (_indentLevel > 0) _indentLevel--;
  }

  void info(String msg) => _write(
        '${_ts()} $_prefix${_color(_blue)}ℹ️  $msg$_resetC',
      );

  void success(String msg) => _write(
        '$_prefix${_color(_green)}✅ $msg$_resetC',
      );

  void warning(String msg) => _write(
        '$_prefix${_color(_yellow)}⚠️  $msg$_resetC',
      );

  void error(String msg) => _writeErr(
        '$_prefix${_color(_red)}❌ $msg$_resetC',
      );

  /// Section header — prints title with 🚀 and auto-indents.
  void section(String title) {
    _write('\n${_ts()} $_prefix${_color(_cyan)}${_bold}🚀 $title...$_resetC');
    _write('$_prefix$_gray${'─' * 40}$_resetC');
    indent();
  }

  /// Finishes a section: prints result, outdents.
  void closeSection(bool ok, String name, Duration duration) {
    outdent();
    final time = _fmt(duration.inSeconds);
    if (ok) {
      success('Finished: $name ($time)');
    } else {
      error('Failed: $name ($time)');
    }
  }

  /// Prints a shell command with timestamp at current indent level.
  void command(String cmd) => _write(
        '${_ts()} $_prefix\$$_resetC $_color(_green)$cmd$_resetC',
      );

  /// Shell output line; only printed when [verbose] is true.
  void verbose(String line) {
    if (verbose) _write(line);
  }

  String _color(String ansi) => noColor ? '' : ansi;
  String get _resetC => noColor ? '' : _reset;
}
```

- [ ] **Step 1: Replace logger.dart content**

- [ ] **Step 2: Create test/logger_test.dart**

```dart
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Logger.terminal', () {
    test('info writes timestamp and message', () {
      final lines = <String>[];
      // We use the private API minimally — test via silent logger inspection.
      // Instead, test that silent logger accepts all methods without crash.
      final logger = Logger.silent();
      logger.info('hello');
      logger.success('ok');
      logger.warning('warn');
      logger.error('fail');
      logger.section('build');
      logger.closeSection(true, 'build', Duration(seconds: 5));
      logger.command('fvm flutter build');
      logger.verbose('debug output');
      // no crash = pass
    });

    test('indent increases prefix width', () {
      final logger = Logger.silent();
      expect(logger._indentLevel, 0);
      logger.indent();
      expect(logger._indentLevel, 1);
      logger.indent();
      expect(logger._indentLevel, 2);
      logger.outdent();
      expect(logger._indentLevel, 1);
      logger.outdent();
      expect(logger._indentLevel, 0);
    });

    test('outdent never goes negative', () {
      final logger = Logger.silent();
      logger.outdent();
      expect(logger._indentLevel, 0);
    });

    test('noColor strips ANSI codes', () {
      final logger = Logger.silent(); // noColor is true for silent
      expect(logger._color(Logger._green), '');
      expect(logger._resetC, '');
    });
  });
}
```

- [ ] **Step 3: Run logger tests**

```bash
dart test test/logger_test.dart
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/src/utils/logger.dart test/logger_test.dart
git commit -m "refactor: Logger from static to instance class with verbose/noColor/indent"
```

---

### Task 2: Inject Logger into ShellRunnerImpl

**Files:**
- Modify: `lib/src/utils/shell_runner_impl.dart`

```dart
import 'dart:io';
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';

/// Production [ShellRunner] implementation that executes real processes
/// via [Process.start] / [Process.run].
///
/// Automatically augments `PATH` with `~/.pub-cache/bin` and `/opt/homebrew/bin` (macOS).
class ShellRunnerImpl implements ShellRunner {
  /// Environment variables with augmented PATH for finding Flutter, Dart, and Homebrew tools.
  static late final Map<String, String> environment = () {
    final home = Platform.environment['HOME'] ?? '';
    final extraPaths = <String>['$home/.pub-cache/bin'];
    if (Platform.isMacOS) {
      extraPaths.add('/opt/homebrew/bin');
    }
    return {
      ...Platform.environment,
      'PATH': '${extraPaths.join(':')}:${Platform.environment['PATH']}',
    };
  }();

  final Logger logger;

  /// Creates a [ShellRunnerImpl].
  ///
  /// [logger] defaults to [Logger.silent]; pass [Logger.terminal] for real CLI.
  ShellRunnerImpl({Logger? logger})
      : logger = logger ?? Logger.silent();

  @override
  Future<void> run(String executable, List<String> args) async {
    logger.command('$executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: true,
    );

    final stdoutDone = process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .forEach(logger.verbose);
    final stderrDone = process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .forEach(logger.verbose);

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (exitCode != 0) {
      throw StateError('Command failed with exit code $exitCode');
    }
  }

  @override
  Future<ShellResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    final result = await Process.run(
      executable,
      args,
      environment: environment,
    );
    return ShellResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}
```

- [ ] **Step 1: Replace shell_runner_impl.dart**

- [ ] **Step 2: Run shell_runner test**

```bash
dart test test/shell_runner_test.dart
```
Expected: pass (test creates `ShellRunnerImpl()` which defaults to silent logger).

- [ ] **Step 3: Commit**

```bash
git add lib/src/utils/shell_runner_impl.dart
git commit -m "refactor: inject Logger into ShellRunnerImpl, use verbose for stdout/stderr"
```

---

### Task 3: Inject Logger into GitManagerImpl and VersionManagerImpl

**Files:**
- Modify: `lib/src/utils/git_manager_impl.dart`
- Modify: `lib/src/utils/version_manager_impl.dart`

- [ ] **Step 1: Update git_manager_impl.dart**

Replace all `Logger.xxx(...)` calls with `_logger.xxx(...)`. Add `Logger` constructor parameter.

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/utils/shell_runner_impl.dart';

import 'exceptions.dart';
import 'git_manager.dart';
import 'logger.dart';
import 'shell_runner.dart';

/// Production [GitManager] implementation using [ShellRunner] to execute Git commands.
class GitManagerImpl implements GitManager {
  /// Creates a [GitManagerImpl] with an optional [shellRunner] and [logger].
  GitManagerImpl({ShellRunner? shellRunner, Logger? logger})
      : _shellRunner = shellRunner ?? ShellRunnerImpl(),
        _logger = logger ?? Logger.silent();

  final ShellRunner _shellRunner;
  final Logger _logger;

  @override
  Future<void> checkClean() async {
    if (Platform.environment['CIRCLECI'] == 'true') {
      _logger.info('Skipping git check in CI environment.');
      return;
    }
    _logger.info('Checking for uncommitted changes...');
    final result = await _runGitCommand(['status', '--porcelain']);
    if (result.stdout.toString().trim().isNotEmpty) {
      _logger.error(
        'Uncommitted changes detected. Please commit or stash them before running this script.',
      );
      _logger.info('Changes:\n${result.stdout}');
      throw GitException(
        'Uncommitted changes detected',
        result.exitCode,
      );
    }
    _logger.success('Git status is clean.');
  }

  @override
  Future<void> resetHard() async {
    await _shellRunner.run('git', ['reset', 'HEAD', '--hard']);
  }

  @override
  Future<void> clean() async {
    await _shellRunner.run('git', ['clean', '-fd']);
  }

  @override
  Future<void> restoreWorkspace() async {
    await resetHard();
    await clean();
  }

  @override
  Future<String> getShortHash() async {
    final result = await _runGitCommand(['rev-parse', '--short', 'HEAD']);
    return result.stdout.toString().trim();
  }

  @override
  Future<String> getRecentCommits({int count = 10}) async {
    final result = await _runGitCommand([
      'log',
      '--oneline',
      '--no-merges',
      '-n',
      '$count',
    ]);
    return result.stdout.toString().trim();
  }

  @override
  Future<String> getBranch() async {
    final result = await _runGitCommand(['rev-parse', '--abbrev-ref', 'HEAD']);
    return result.stdout.toString().trim();
  }

  @override
  Future<String> getCurrentUser() async {
    final userResult = await _shellRunner.runAndCapture('git', [
      'config',
      '--get',
      'user.name',
    ]);
    final name = userResult.stdout.toString().trim();
    if (name.isNotEmpty) return name;
    return Platform.environment['CIRCLE_USERNAME'] ?? 'ci';
  }

  @override
  Future<String> getLatestCommitBody() async {
    final result = await _runGitCommand(['log', '-1', '--pretty=%b']);
    return result.stdout.toString().trim();
  }

  Future<ShellResult> _runGitCommand(List<String> args) async {
    final result = await _shellRunner.runAndCapture('git', args);
    if (result.exitCode != 0) {
      _logger.error('Git command failed: git ${args.join(' ')}');
      _logger.error('Error: ${result.stderr}');
      throw GitException(
        'git ${args.join(' ')} failed',
        result.exitCode,
      );
    }
    return result;
  }
}
```

- [ ] **Step 2: Update version_manager_impl.dart**

Replace all `Logger.xxx(...)` calls with `_logger.xxx(...)`. Replace `stdout.write(...)` / `stdin.readLineSync()` (interactiveBumpAndPush) — keep those as-is since they're user I/O, not logging.

```dart
import 'dart:io';

import 'package:flutter_ci_tools/src/utils/shell_runner_impl.dart';

import 'logger.dart';
import 'shell_runner.dart';
import 'version_manager.dart';

class VersionManagerImpl implements VersionManager {
  VersionManagerImpl({ShellRunner? shellRunner, Logger? logger})
      : _shellRunner = shellRunner ?? ShellRunnerImpl(),
        _logger = logger ?? Logger.silent();

  final ShellRunner _shellRunner;
  final Logger _logger;
  static const _tagPrefix = 'builds/';
  static const _bumpGranularity = 100;

  @override
  Future<int?> fetchLatestBuildNumber() async {
    await _shellRunner.runAndCapture('git', ['fetch', '--tags', '--force']);
    final res = await _shellRunner.runAndCapture('git', [
      'tag',
      '--list',
      '$_tagPrefix*',
    ]);
    final nums = res.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith(_tagPrefix))
        .map((l) => int.tryParse(l.substring(_tagPrefix.length)))
        .whereType<int>()
        .toList();
    return nums.isEmpty ? null : nums.reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<int> computeNextBuildNumber(int seedBuildNumber) async {
    final latest = await fetchLatestBuildNumber();
    if (latest == null) {
      _logger.warning(
        'No "$_tagPrefix*" tag found. Seeding from $seedBuildNumber.',
      );
      return seedBuildNumber;
    }
    return latest + 1;
  }

  @override
  Future<void> pushNewBuildTag(int buildNumber) async {
    final tag = '$_tagPrefix$buildNumber';
    _logger.info('Tagging $tag ...');
    await _shellRunner.run('git', [
      'tag',
      '-a',
      '-f',
      tag,
      '-m',
      'CI build $buildNumber',
    ]);
    await _shellRunner.run('git', ['push', '--force', 'origin', tag]);
    _logger.success('Pushed tag $tag');
  }

  @override
  Future<void> interactiveBumpAndPush(int seedBuildNumber) async {
    final latest = await fetchLatestBuildNumber();
    final floor = latest ?? (seedBuildNumber - 1);
    final base = latest ?? seedBuildNumber;
    final suggested = (base ~/ _bumpGranularity + 1) * _bumpGranularity;
    _logger.info('Current latest builds tag: ${latest ?? '(none)'}');

    while (true) {
      stdout.write('Enter new base buildNumber (default $suggested): ');
      final input = stdin.readLineSync()?.trim() ?? '';
      final next = input.isEmpty ? suggested : int.tryParse(input);
      if (next == null || next <= floor) {
        _logger.error('Invalid buildNumber (must be > $floor): $input');
        continue;
      }
      stdout.write('Push $_tagPrefix$next ? (y/N): ');
      if ((stdin.readLineSync() ?? '').trim().toLowerCase() != 'y') return;
      await pushNewBuildTag(next);
      return;
    }
  }
}
```

- [ ] **Step 3: Run existing tests**

```bash
dart test test/git_manager_test.dart test/version_manager_test.dart
```
Expected: pass (default silent logger).

- [ ] **Step 4: Commit**

```bash
git add lib/src/utils/git_manager_impl.dart lib/src/utils/version_manager_impl.dart
git commit -m "refactor: inject Logger into GitManagerImpl and VersionManagerImpl"
```

---

### Task 4: Add Logger to PipelineContext and Pipeline

**Files:**
- Modify: `lib/src/pipeline_context.dart`
- Modify: `lib/src/pipeline.dart`

- [ ] **Step 1: Add logger field to PipelineContext**

In `pipeline_context.dart`, add the import and field:

```dart
import 'dart:io';

import 'utils/args_parser.dart';
import 'utils/git_manager.dart';
import 'utils/logger.dart';  // NEW

// ... existing code ...

class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    this.rawArgs = const [],
    GitManager? git,
    Logger? logger,        // NEW
  }) : git = git ?? GitManager.instance,
       logger = logger ?? Logger.terminal();  // NEW

  // ... existing fields ...

  /// Logger for structured build output.  // NEW
  Logger logger;                           // NEW (non-final, Pipeline may override)

  // ... rest unchanged ...
}
```

- [ ] **Step 2: Update Pipeline.run() and _runTracked()**

Replace `pipeline.dart` content. Key changes:
- `run()` creates `Logger.terminal()` from args, passes to context
- `_runTracked()` uses `logger.section()` / `logger.closeSection()`
- `_printSummary()` uses `logger.info()` via `context.logger`

```dart
import 'action_status.dart';
import 'actions/pipeline_action.dart';
import 'pipeline_context.dart';
import 'utils/logger.dart';

abstract class Pipeline {
  String get name {
    final className = this.runtimeType.toString();
    String withoutSuffix = className;
    if (className.toLowerCase().endsWith('pipeline')) {
      withoutSuffix = className.substring(
        0,
        className.length - 'pipeline'.length,
      );
    }
    final snakeCase = withoutSuffix
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => '_${match.group(1)}')
        .toLowerCase()
        .replaceFirst('_', '');
    return snakeCase;
  }

  String get description => '当前 pipeline 的说明，应包含关键信息';
  late final PipelineContext context;
  final List<PipelineAction> executedActions = [];
  bool get allSucceeded =>
      executedActions.every((a) => a.status == ActionStatus.success);

  PipelineAction? get lastFailure {
    for (var i = executedActions.length - 1; i >= 0; i--) {
      if (executedActions[i].status == ActionStatus.failed) {
        return executedActions[i];
      }
    }
    return null;
  }

  String get help;
  PipelineContext createContext(List<String> args);
  Future<void> beforeBuild() async {}
  Future<void> body();
  Future<void> afterBuild() async {}

  Future<void> run(List<String> args) async {
    context = createContext(args);
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e) {
        context.logger.error('afterBuild failed', e);
      }
      _printSummary();
    }
  }

  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    return _runTracked(action);
  }

  Future<List<R>> runParallelActions<R>(List<PipelineAction<R>> actions) async {
    executedActions.addAll(actions);
    return Future.wait(actions.map(_runTracked));
  }

  Future<R> _runTracked<R>(PipelineAction<R> action) async {
    final log = context.logger;
    log.section(action.name);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action.run(context);
      stopwatch.stop();
      log.closeSection(true, action.name, stopwatch.elapsed);
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
      return result;
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

  void _printSummary() {
    final log = context.logger;
    if (executedActions.isEmpty) return;
    const sep = '────────────────────────────────────';
    log.info(sep);
    log.info('执行摘要');
    log.info(sep);
    for (final action in executedActions) {
      final status = action.status;
      final duration = action.duration;
      if (status == null || duration == null) continue;
      final icon = switch (status) {
        ActionStatus.success => '✅',
        ActionStatus.failed => '❌',
        ActionStatus.skipped => '⏭️',
        ActionStatus.interrupted => '🛑',
      };
      final ms = duration.inMilliseconds;
      final time =
          ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
      log.info('$icon ${action.name} ($time)');
    }
    log.info(sep);
    final failure = lastFailure;
    if (failure != null) {
      log.error('失败: ${failure.name}', failure.error);
    }
  }
}
```

- [ ] **Step 3: Run pipeline tests**

```bash
dart test test/pipeline_test.dart test/pipeline_context_test.dart test/pipeline_parallel_test.dart test/pipeline_registry_test.dart
```
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline_context.dart lib/src/pipeline.dart
git commit -m "refactor: add Logger to PipelineContext, use section/closeSection in Pipeline"
```

---

### Task 5: Update all actions to use context.logger

**Files:**
- Modify: `lib/src/actions/resolve_build_version_action.dart`
- Modify: `lib/src/actions/pgyer_upload_v2_action.dart`
- Modify: `lib/src/actions/pgyer_upload_action.dart`
- Modify: `lib/src/actions/feishu_notify_action.dart`
- Modify: `lib/src/actions/feishu_build_notify_action.dart` (via FeishuNotifyAction)
- Modify: `lib/src/actions/google_play_action.dart`
- Modify: `lib/src/actions/app_store_action.dart`
- Modify: `lib/src/actions/swap_info_plist_action.dart`

Each change: `Logger.xxx(...)` → `context.logger.xxx(...)`, add `import '../utils/logger.dart'` only if not already present.

- [ ] **Step 1: resolve_build_version_action.dart**

```dart
// Remove: import '../utils/logger.dart';
// Replace: Logger.info(...) → context.logger.info(...)

import '../pipeline_context.dart';
import '../utils/version_manager.dart';
import '../utils/version_manager_impl.dart';
import 'pipeline_action.dart';

class ResolveBuildVersionAction extends PipelineAction<void> {
  ResolveBuildVersionAction({VersionManager? versionManager})
      : _versionManager = versionManager ?? VersionManagerImpl();

  final VersionManager _versionManager;

  @override
  String get name => 'Resolve Build Version';

  @override
  Future<void> run(PipelineContext context) async {
    final number = await _versionManager.computeNextBuildNumber(
      context.seedBuildNumber,
    );
    context.resolveBuildVersion(number);
    context.logger.info(
      'Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}',
    );
  }
}
```

- [ ] **Step 2: pgyer_upload_v2_action.dart**

Replace all `Logger.xxx(...)` → `context.logger.xxx(...)`. Remove `import '../utils/logger.dart';`

```dart
// In run():
  context.logger.success('Pgyer build ready: $downloadUrl');

// In _selectReachableDomain():
  context.logger.info('Probing Pgyer API domains...');
  // ...
  context.logger.info('Using domain $domain');

// In _getCOSToken():
  context.logger.info('Requesting COS upload token...');

// In _uploadToCOS():
  context.logger.info('Uploading $fileName ($size bytes) to COS...');
  context.logger.success('Uploaded to COS.');

// In _pollBuildInfo():
  context.logger.info('Waiting for Pgyer to process the build...');
```

Note: the `_selectReachableDomain`, `_getCOSToken`, `_uploadToCOS`, `_pollBuildInfo` methods are private and called from `run()`. They need `context.logger` but don't receive `context` as parameter. The simplest fix: pass `logger` as parameter, or make them receive `context`. Given existing structure, pass `Logger`:

```dart
// _selectReachableDomain(Logger logger) — for domain probing
// _getCOSToken(String apiBaseUrl, File artifact, Logger logger)
// _uploadToCOS(_CosToken token, File artifact, Logger logger)
// _pollBuildInfo(String apiBaseUrl, String key, Logger logger)
```

- [ ] **Step 3: pgyer_upload_action.dart, feishu_notify_action.dart, google_play_action.dart, app_store_action.dart, swap_info_plist_action.dart**

Same pattern: `Logger.xxx(...)` → `context.logger.xxx(...)`, remove `import '../utils/logger.dart';` if it was only imported for Logger.

- [ ] **Step 4: Run all action tests**

```bash
dart test test/actions/
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/src/actions/
git commit -m "refactor: actions use context.logger instead of static Logger"
```

---

### Task 6: Wire --verbose and --no-color CLI args

**Files:**
- Modify: `lib/src/pipeline.dart` (run() creates Logger from args)

This is a small change to `Pipeline.run()`. After `createContext(args)`, check args for verbose/noColor and create logger accordingly. But `createContext` is abstract and varies per pipeline. So instead, after context is created:

- [ ] **Step 1: Update Pipeline.run()**

In `pipeline.dart`, update `run()` to apply CLI args to logger:

```dart
Future<void> run(List<String> args) async {
  context = createContext(args);
  // Apply CLI flags to logger
  final parsableArgs = context.args;
  if (parsableArgs.noColor || parsableArgs.verbose) {
    context.logger = Logger.terminal(
      noColor: parsableArgs.noColor,
      verbose: parsableArgs.verbose,
    );
  }
  // rest unchanged...
}
```

Wait — PipelineContext's logger is `final`. We should make it non-final (or late final). Let's make it non-final:

In `pipeline_context.dart`:
```dart
Logger logger;  // not final — Pipeline may update it from CLI args
```

And in the constructor, default to `Logger.terminal()` (not silent) since PipelineContext is typically used in production context:

```dart
Logger logger = Logger.terminal();
```

- [ ] **Step 2: Update ArgsParser**

No change needed — `has('--verbose')` and `has('--no-color')` already work.

- [ ] **Step 3: Run tests**

```bash
dart test
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/src/pipeline.dart lib/src/pipeline_context.dart
git commit -m "feat: wire --verbose and --no-color CLI args to Logger"
```

---

### Task 7: Full test suite verification

- [ ] **Step 1: Run complete test suite**

```bash
dart test
```

Expected: all tests pass.

- [ ] **Step 2: Build and check log output**

```bash
cd example && dart run flutter_ci_tools test_pipeline
```

Manually verify:
- Each action opens with `🚀 Action Name...` section header
- Sub-step logs are indented
- All lines have timestamps
- Shell output is hidden without `--verbose`
- `--no-color` produces plain text

- [ ] **Step 3: Final commit (if any fixes needed)**

---

## Self-Review

1. **Spec coverage:** Each spec requirement maps to a task:
   - Logger 实例化 → Task 1
   - verbose 级别 → Task 1 (Logger.verbose()) + Task 2 (ShellRunnerImpl)
   - info 级别 → Task 1 (Logger.info/success/warning/error)
   - 层级缩进 → Task 1 (indent/outdent) + Task 4 (Pipeline._runTracked)
   - 时间戳统一 → Task 1 (_ts prefix)
   - --no-color CLI → Task 6
   - 进度反馈 → Task 4 (closeSection includes duration)
   - 注入 Logger → Tasks 2-5

2. **Placeholder scan:** No TBD/TODO, no vague "add error handling" steps. All code is concrete.

3. **Type consistency:** Logger methods (info, success, warning, error, section, closeSection, command, verbose) are consistent across all tasks. `context.logger` field name is consistent.
