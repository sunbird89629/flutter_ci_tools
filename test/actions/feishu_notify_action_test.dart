import 'package:flutter_ci_tools/src/actions/feishu_notify_action.dart';
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  _FakeShellRunner({this.results = const []});

  /// 依次返回的结果；用完后重复最后一个。空列表表示一律成功。
  final List<ShellResult> results;

  int calls = 0;
  String? lastJson;
  String? lastUrl;
  List<String> lastArgs = const [];

  @override
  void setLogger(Logger logger) {}

  @override
  Future<void> run(String exe, List<String> args) async {}

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final dIdx = args.indexOf('-d');
    if (dIdx >= 0 && dIdx + 1 < args.length) lastJson = args[dIdx + 1];
    lastUrl = args.last;
    lastArgs = args;
    final index = calls;
    calls++;
    if (results.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }
    return results[index < results.length ? index : results.length - 1];
  }
}

PipelineContext _context() =>
    PipelineContext(appName: 'TestApp', seedBuildNumber: 1000);

FeishuNotifyAction _action(
  _FakeShellRunner shell, {
  int maxAttempts = 3,
  String url = 'https://open.feishu.cn/hook',
}) =>
    FeishuNotifyAction(
      webhookUrl: url,
      message: 'hello world',
      maxAttempts: maxAttempts,
      retryDelay: Duration.zero,
      shellRunner: shell,
    );

void main() {
  test('FeishuNotifyAction posts the given message to the configured webhook',
      () async {
    final shell = _FakeShellRunner();
    final action = _action(shell);

    await action.run(_context());

    expect(action.name, 'Send Feishu Notification');
    expect(shell.lastUrl, 'https://open.feishu.cn/hook');
    expect(shell.lastJson, contains('hello world'));
    expect(shell.lastJson, contains('text'));
    expect(shell.calls, 1, reason: '成功时不该重试');
  });

  test('curl 带上超时参数，避免挑中坏节点后干等', () async {
    final shell = _FakeShellRunner();

    await _action(shell).run(_context());

    expect(shell.lastArgs, containsAll(['-sS', '-f']));
    expect(shell.lastArgs, containsAllInOrder(['--connect-timeout', '5']));
    expect(shell.lastArgs, containsAllInOrder(['--max-time', '15']));
  });

  test('不开 curl 自带重试，避免与外层重试相乘', () async {
    // 两层重试会变成 maxAttempts × (1 + --retry) 次请求，最坏耗时成倍放大，
    // 而且 curl 内部重试是静默的，日志上看不出试了几次
    final shell = _FakeShellRunner();

    await _action(shell).run(_context());

    expect(shell.lastArgs, isNot(contains('--retry')));
  });

  test('curl 失败时重试到上限，且不抛异常', () async {
    final shell = _FakeShellRunner(
      results: const [
        ShellResult(exitCode: 7, stdout: '', stderr: 'connection timed out'),
      ],
    );

    await _action(shell, maxAttempts: 3).run(_context());

    expect(shell.calls, 3);
  });

  test('前几次失败、后续成功时停止重试', () async {
    final shell = _FakeShellRunner(
      results: const [
        ShellResult(exitCode: 35, stdout: '', stderr: 'recv failure'),
        ShellResult(exitCode: 0, stdout: '{"code":0}', stderr: ''),
      ],
    );

    await _action(shell, maxAttempts: 3).run(_context());

    expect(shell.calls, 2, reason: '成功后不该继续重试');
  });

  test('HTTP 200 但业务码非零视为失败并重试', () async {
    // 飞书对 token 失效之类的错误返回 200 + 非零 code，只看退出码会误判成功
    final shell = _FakeShellRunner(
      results: const [
        ShellResult(
          exitCode: 0,
          stdout: '{"code":9499,"msg":"bad request"}',
          stderr: '',
        ),
      ],
    );

    await _action(shell, maxAttempts: 2).run(_context());

    expect(shell.calls, 2);
  });

  test('webhook 未配置时直接跳过，不发请求', () async {
    final shell = _FakeShellRunner();

    await _action(shell, url: '  ').run(_context());

    expect(shell.calls, 0);
  });
}
