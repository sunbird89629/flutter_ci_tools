import 'package:flutter_ci_tools/src/actions/feishu_build_notify_action.dart';
import 'package:flutter_ci_tools/src/context_keys.dart';
import 'package:flutter_ci_tools/src/utils/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/http_poster.dart';
import 'package:test/test.dart';

class _FakeHttpPoster implements HttpPoster {
  _FakeHttpPoster({this.statusCode = 200});

  final int statusCode;
  int calls = 0;

  /// 发出去的消息正文。
  String? lastText;

  @override
  Future<HttpResponse> postJson(
    Uri url,
    Object body, {
    Duration connectTimeout = const Duration(seconds: 5),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls++;
    final content = (body as Map)['content'] as Map;
    lastText = content['text'] as String;
    return HttpResponse(statusCode: statusCode, body: '{"code":0}');
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
    final http = _FakeHttpPoster();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )
      ..put(ContextKeys.buildNumber, 12042)
      ..put(ContextKeys.pgyerDownloadUrl, 'https://example.com/dl');

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: 'Pgyer',
      downloadUrlKeys: [ContextKeys.pgyerDownloadUrl],
      httpPoster: http,
    );
    await action.run(context);

    expect(action.name, 'Send Feishu Build Notification');
    expect(http.lastText, contains('TestApp'));
    expect(http.lastText, contains('12042'));
    expect(http.lastText, contains('Pgyer'));
    expect(http.lastText, contains('https://example.com/dl'));
    expect(http.lastText, contains('release notes'));
    expect(http.lastText, contains('main'));
    expect(http.lastText, contains('abc1234'));
    expect(http.lastText, contains('Alice'));
    expect(http.lastText, contains('commit1'));
  });

  test('formats message with multiple download URLs via keys', () async {
    final http = _FakeHttpPoster();
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
      target: 'Pgyer',
      downloadUrlKeys: ['urlA', 'urlB'],
      httpPoster: http,
    );
    await action.run(context);

    expect(http.lastText, contains('https://example.com/a'));
    expect(http.lastText, contains('https://example.com/b'));
    expect(http.lastText, contains('🔗 下载链接'));
  });

  test('omits download line when no downloadUrlKeys provided', () async {
    final http = _FakeHttpPoster();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )..put(ContextKeys.buildNumber, 12042);

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: 'Pgyer',
      httpPoster: http,
    );
    await action.run(context);

    expect(http.lastText, isNot(contains('🔗 下载')));
  });

  test('maxAttempts / retryDelay 在子类上同样生效', () async {
    // 所有流水线用的都是 FeishuBuildNotifyAction，这两个参数得能从子类构造进来
    final http = _FakeHttpPoster(statusCode: 500);
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      git: _FakeGitManager(),
    )..put(ContextKeys.buildNumber, 12042);

    final action = FeishuBuildNotifyAction(
      webhookUrl: 'https://open.feishu.cn/hook',
      target: 'Pgyer',
      maxAttempts: 2,
      retryDelay: Duration.zero,
      httpPoster: http,
    );
    await action.run(context);

    expect(http.calls, 2, reason: 'maxAttempts 没生效说明没透传');
  });
}
