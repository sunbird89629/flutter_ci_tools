import 'package:flutter_ci_tools/src/actions/feishu_build_notify_action.dart';
import 'package:flutter_ci_tools/src/context_keys.dart';
import 'package:flutter_ci_tools/src/utils/git_manager.dart';
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

class _FakeGitManager implements GitManager {
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> resetHard() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<void> restoreWorkspace() async {}
  @override
  Future<String> getShortHash() async => 'abc1234';
  @override
  Future<String> getRecentCommits({int count = 10}) async => 'commit1\ncommit2';
  @override
  Future<String> getBranch() async => 'main';
  @override
  Future<String> getCurrentUser() async => 'Alice';
  @override
  Future<String> getLatestCommitBody() async => 'release notes';
}

void main() {
  test('FeishuBuildNotifyAction sends formatted build message via webhook',
      () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )
      ..put(ContextKeys.buildNumber, 12042)
      ..put(ContextKeys.pgyerDownloadUrl, 'https://example.com/dl');

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: DeployTarget.pgyer,
      downloadUrlKeys: [ContextKeys.pgyerDownloadUrl],
      shellRunner: shell,
    );
    await action.run(context);

    expect(action.name, 'Send Feishu Build Notification');
    expect(shell.lastJson, contains('TestApp'));
    expect(shell.lastJson, contains('12042'));
    expect(shell.lastJson, contains('Pgyer'));
    expect(shell.lastJson, contains('https://example.com/dl'));
    expect(shell.lastJson, contains('release notes'));
    expect(shell.lastJson, contains('main'));
    expect(shell.lastJson, contains('abc1234'));
    expect(shell.lastJson, contains('Alice'));
    expect(shell.lastJson, contains('commit1'));
  });

  test('formats message with multiple download URLs via keys', () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )
      ..put(ContextKeys.buildNumber, 12042)
      ..put('urlA', 'https://example.com/a')
      ..put('urlB', 'https://example.com/b');

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: DeployTarget.pgyer,
      downloadUrlKeys: ['urlA', 'urlB'],
      shellRunner: shell,
    );
    await action.run(context);

    expect(shell.lastJson, contains('https://example.com/a'));
    expect(shell.lastJson, contains('https://example.com/b'));
    expect(shell.lastJson, contains('🔗 下载链接'));
  });

  test('omits download line when no downloadUrlKeys provided', () async {
    final shell = _FakeShellRunner();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )..put(ContextKeys.buildNumber, 12042);

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: DeployTarget.pgyer,
      shellRunner: shell,
    );
    await action.run(context);

    expect(shell.lastJson, isNot(contains('🔗 下载')));
  });
}
