import 'package:flutter_ci_tools/src/actions/clean_project_action.dart';
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  @override
  void setLogger(Logger logger) {}
  final List<String> calls = [];
  @override
  Future<void> run(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  test('CleanProjectAction runs flutter clean then pub get', () async {
    final shell = _FakeShellRunner();
    final action = CleanProjectAction(shellRunner: shell);

    await action.run(PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
    ));

    expect(action.name, 'Clean Project');
    expect(shell.calls, [
      'fvm flutter clean',
      'fvm flutter pub get',
    ]);
  });
}
