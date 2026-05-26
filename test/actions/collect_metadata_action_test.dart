import 'package:flutter_ci_tools/src/actions/collect_metadata_action.dart';
import 'package:flutter_ci_tools/src/utils/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

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
  Future<String> getRecentCommits({int count = 10}) async => 'log';
  @override
  Future<String> getBranch() async => 'main';
  @override
  Future<String> getCurrentUser() async => 'Alice';
  @override
  Future<String> getLatestCommitBody() async => 'body';
}

void main() {
  test('CollectMetadataAction populates context.metadata via GitManager',
      () async {
    final action = CollectMetadataAction(gitManager: _FakeGitManager());
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
    );

    await action.run(context);

    expect(action.name, 'Collect Build Metadata');
    expect(context.metadata.branch, 'main');
    expect(context.metadata.gitUser, 'Alice');
    expect(context.metadata.gitHash, 'abc1234');
    expect(context.metadata.commitBody, 'body');
  });
}
