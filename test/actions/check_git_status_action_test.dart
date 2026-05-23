import 'package:flutter_ci_tools/src/actions/check_git_status_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeGitManager implements GitManager {
  bool isClean = true;
  bool checkCalled = false;

  @override
  Future<void> checkClean() async {
    checkCalled = true;
    if (!isClean) throw GitException('dirty', 1);
  }

  @override Future<void> resetHard() async {}
  @override Future<void> clean() async {}
  @override Future<void> restoreWorkspace() async {}
  @override Future<String> getShortHash() async => '';
  @override Future<String> getRecentCommits({int count = 10}) async => '';
  @override Future<String> getBranch() async => '';
  @override Future<String> getCurrentUser() async => '';
  @override Future<String> getLatestCommitBody() async => '';
}

void main() {
  late _FakeGitManager git;
  late PipelineContext context;

  setUp(() {
    git = _FakeGitManager();
    context = PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    );
  });

  test('CheckGitStatusAction delegates to GitManager.checkClean', () async {
    final action = CheckGitStatusAction(gitManager: git);
    await action.run(context);
    expect(action.name, 'Check Git Status');
    expect(git.checkCalled, isTrue);
  });

  test('CheckGitStatusAction rethrows GitException on dirty tree', () async {
    git.isClean = false;
    final action = CheckGitStatusAction(gitManager: git);
    expect(() => action.run(context), throwsA(isA<GitException>()));
  });
}
