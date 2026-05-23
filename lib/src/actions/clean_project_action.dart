import '../default_shell_runner.dart';
import '../pipeline_context.dart';
import '../shell_runner.dart';
import 'pipeline_action.dart';

/// Runs `fvm flutter clean` followed by `fvm flutter pub get`.
class CleanProjectAction extends PipelineAction<void> {
  CleanProjectAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? DefaultShellRunner();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Clean Project';

  @override
  Future<void> run(PipelineContext context) async {
    await _shellRunner.run('fvm', ['flutter', 'clean']);
    await _shellRunner.run('fvm', ['flutter', 'pub', 'get']);
  }
}
