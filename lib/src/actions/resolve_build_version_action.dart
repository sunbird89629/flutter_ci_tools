import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/version_manager.dart';
import 'pipeline_action.dart';

/// Computes the next build number via [VersionManager] and writes it to
/// [PipelineContext.buildNumber].
class ResolveBuildVersionAction extends PipelineAction<void> {
  ResolveBuildVersionAction({VersionManager? versionManager})
      : _versionManager = versionManager ?? DefaultVersionManager();

  final VersionManager _versionManager;

  @override
  String get name => 'Resolve Build Version';

  @override
  Future<void> run(PipelineContext context) async {
    final number = await _versionManager.computeNextBuildNumber(
      context.seedBuildNumber,
    );
    context.buildNumber = number;
    Logger.info(
      'Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}',
    );
  }
}
