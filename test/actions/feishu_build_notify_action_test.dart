import 'package:flutter_ci_tools/src/actions/feishu_build_notify_action.dart';
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  String? lastJson;
  @override
  Future<void> run(String exe, List<String> args) async {}
  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final dIdx = args.indexOf('-d');
    if (dIdx >= 0 && dIdx + 1 < args.length) lastJson = args[dIdx + 1];
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('FeishuBuildNotifyAction sends formatted build message via webhook',
      () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
    )
      ..resolveBuildVersion(12042)
      ..metadata = BuildMetadata(
        branch: 'main',
        gitUser: 'Alice',
        gitHash: 'abc1234',
        recentCommits: 'commit1\ncommit2',
        commitBody: 'release notes',
      );

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: DeployTarget.pgyer,
      downloadUrl: 'https://example.com/dl',
      shellRunner: shell,
    );
    await action.run(context);

    expect(action.name, 'Send Feishu Build Notification');
    expect(shell.lastJson, contains('TestApp'));
    expect(shell.lastJson, contains('12042'));
    expect(shell.lastJson, contains('Pgyer'));
    expect(shell.lastJson, contains('https://example.com/dl'));
    expect(shell.lastJson, contains('release notes'));
  });
}
