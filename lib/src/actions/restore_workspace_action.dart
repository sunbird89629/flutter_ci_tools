import '../utils/git_manager.dart';
import '../utils/git_manager_impl.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Runs `git reset --hard HEAD` + `git clean -fd` to restore a clean tree.
///
/// Typically returned from `BuildPipeline.afterBuild()` so it runs regardless
/// of whether the main body succeeded.
class RestoreWorkspaceAction extends PipelineAction<void> {
  RestoreWorkspaceAction({GitManager? gitManager})
      : _gitManager = gitManager ?? GitManagerImpl();

  final GitManager _gitManager;

  @override
  String get name => 'Restore Workspace';

  @override
  Future<void> run(PipelineContext context) => _gitManager.restoreWorkspace();
}
