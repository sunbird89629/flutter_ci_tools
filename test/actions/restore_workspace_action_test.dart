import 'package:flutter_ci_tools/src/actions/restore_workspace_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _FakeGitManager implements GitManager {
  bool restored = false;

  @override Future<void> checkClean() async {}
  @override Future<void> resetHard() async {}
  @override Future<void> clean() async {}
  @override Future<void> restoreWorkspace() async { restored = true; }
  @override Future<String> getShortHash() async => '';
  @override Future<String> getRecentCommits({int count = 10}) async => '';
  @override Future<String> getBranch() async => '';
  @override Future<String> getCurrentUser() async => '';
  @override Future<String> getLatestCommitBody() async => '';
}

void main() {
  test('RestoreWorkspaceAction delegates to GitManager.restoreWorkspace', () async {
    final git = _FakeGitManager();
    final action = RestoreWorkspaceAction(gitManager: git);
    await action.run(PipelineContext(
      config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000),
    ));

    expect(action.name, 'Restore Workspace');
    expect(git.restored, isTrue);
  });
}
