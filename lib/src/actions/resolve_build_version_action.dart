import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/version_manager.dart';
import '../utils/version_manager_impl.dart';
import 'pipeline_action.dart';

/// Computes the next build number via [VersionManager] and stores it in
/// [PipelineContext] via [PipelineContext.resolveBuildVersion].
class ResolveBuildVersionAction extends PipelineAction<void> {
  ResolveBuildVersionAction({VersionManager? versionManager})
      : _versionManager = versionManager ?? VersionManagerImpl();

  final VersionManager _versionManager;

  @override
  String get name => 'Resolve Build Version';

  @override
  Future<void> run(PipelineContext context) async {
    final number = await _versionManager.computeNextBuildNumber(
      context.seedBuildNumber,
    );
    context.resolveBuildVersion(number);
    Logger.info(
      'Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}',
    );
  }
}
