import '../context_keys.dart';
import '../pipeline_context.dart';
import '../utils/version_manager.dart';
import '../utils/version_manager_impl.dart';
import 'pipeline_action.dart';

/// Computes the next build number via [VersionManager] and stores it in
/// [PipelineContext] under [ContextKeys.buildNumber].
class ResolveBuildVersionAction extends PipelineAction {
  ResolveBuildVersionAction({VersionManager? versionManager})
      : _versionManager = versionManager;

  final VersionManager? _versionManager;

  @override
  String get name => 'Resolve Build Version';

  @override
  Future<void> run(PipelineContext context) async {
    final vm = _versionManager ?? VersionManagerImpl(logger: context.logger);
    final number = await vm.computeNextBuildNumber(
      context.seedBuildNumber,
    );
    context.put(ContextKeys.buildNumber, number);
    context.logger.info(
      'Resolved buildNumber=$number  buildName=${context.buildName}',
    );
  }
}
