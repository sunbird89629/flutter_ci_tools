import '../build_metadata.dart';
import '../utils/git_manager.dart';
import '../utils/git_manager_impl.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Collects git/build metadata via [GitManager] and writes it to
/// [PipelineContext.metadata].
class CollectMetadataAction extends PipelineAction<void> {
  CollectMetadataAction({GitManager? gitManager})
      : _gitManager = gitManager ?? GitManagerImpl();

  final GitManager _gitManager;

  @override
  String get name => 'Collect Build Metadata';

  @override
  Future<void> run(PipelineContext context) async {
    context.metadata = await BuildMetadata.collect(_gitManager);
  }
}
