import '../utils/git_manager.dart';
import '../utils/git_manager_impl.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Aborts the pipeline if the working tree has uncommitted changes.
class CheckGitStatusAction extends PipelineAction<void> {
  CheckGitStatusAction({GitManager? gitManager})
      : _gitManager = gitManager;

  final GitManager? _gitManager;

  @override
  String get name => 'Check Git Status';

  @override
  Future<void> run(PipelineContext context) {
    final gm = _gitManager ?? GitManagerImpl(logger: context.logger);
    return gm.checkClean();
  }
}
