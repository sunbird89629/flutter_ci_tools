import '../utils/shell_runner_impl.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Runs `fvm flutter clean` followed by `fvm flutter pub get`.
class CleanProjectAction extends PipelineAction {
  CleanProjectAction({ShellRunner? shellRunner})
      : _shellRunner = shellRunner ?? ShellRunnerImpl();

  final ShellRunner _shellRunner;

  @override
  String get name => 'Clean Project';

  @override
  Future<void> run(PipelineContext context) async {
    _shellRunner.setLogger(context.logger);
    await _shellRunner.run('fvm', ['flutter', 'clean']);
    await _shellRunner.run('fvm', ['flutter', 'pub', 'get']);
  }
}
