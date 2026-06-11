import '../pipeline_context.dart';
import '../utils/version_manager.dart';
import '../utils/version_manager_impl.dart';
import 'pipeline_action.dart';

/// Computes the next build number via [VersionManager] and stores it in
/// [PipelineContext] via [PipelineContext.resolveBuildVersion].
class ResolveBuildVersionAction extends PipelineAction<void> {
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
    context.resolveBuildVersion(number);
    context.logger.info(
      'Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}',
    );
  }
}
