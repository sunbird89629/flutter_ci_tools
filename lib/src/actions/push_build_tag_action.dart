import '../pipeline_context.dart';
import '../version_manager.dart';
import 'pipeline_action.dart';

/// Creates and force-pushes a `builds/<buildNumber>` tag for this build.
class PushBuildTagAction extends PipelineAction<void> {
  PushBuildTagAction({VersionManager? versionManager})
      : _versionManager = versionManager ?? DefaultVersionManager();

  final VersionManager _versionManager;

  @override
  String get name => 'Push Build Tag';

  @override
  Future<void> run(PipelineContext context) =>
      _versionManager.pushNewBuildTag(context.buildNumber);
}
