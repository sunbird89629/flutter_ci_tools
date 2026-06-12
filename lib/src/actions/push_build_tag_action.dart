import '../context_keys.dart';
import '../pipeline_context.dart';
import '../utils/version_manager.dart';
import '../utils/version_manager_impl.dart';
import 'pipeline_action.dart';

/// Creates and force-pushes a `builds/<buildNumber>` tag for this build.
///
/// Reads `ContextKeys.buildNumber` from the context bag — requires
/// `ResolveBuildVersionAction` earlier in the pipeline body.
class PushBuildTagAction extends PipelineAction<void> {
  PushBuildTagAction({VersionManager? versionManager})
      : _versionManager = versionManager;

  final VersionManager? _versionManager;

  @override
  String get name => 'Push Build Tag';

  @override
  Future<void> run(PipelineContext context) {
    final vm = _versionManager ?? VersionManagerImpl(logger: context.logger);
    return vm.pushNewBuildTag(context.get<int>(ContextKeys.buildNumber));
  }
}
