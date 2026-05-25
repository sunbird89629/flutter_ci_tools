import 'package:flutter_ci_tools/src/actions/feishu_notify_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  String? lastJson;
  String? lastUrl;
  @override
  Future<void> run(String exe, List<String> args) async {}

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final dIdx = args.indexOf('-d');
    if (dIdx >= 0 && dIdx + 1 < args.length) lastJson = args[dIdx + 1];
    lastUrl = args.last;
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('FeishuNotifyAction posts the given message to the configured webhook',
      () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 1000,
      platforms: {AppPlatform.android},
    );

    final action = FeishuNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      message: 'hello world',
      shellRunner: shell,
    );
    await action.run(context);

    expect(action.name, 'Send Feishu Notification');
    expect(shell.lastUrl, 'https://open.feishu.cn/hook');
    expect(shell.lastJson, contains('hello world'));
    expect(shell.lastJson, contains('text'));
  });
}
