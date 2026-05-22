import 'package:flutter_ci_tools/src/actions/google_play_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    runCalls.add('$executable ${args.join(' ')}');
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('GooglePlayUploadAction', () {
    late _FakeShellRunner shell;
    late GooglePlayUploadAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = GooglePlayUploadAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Upload to Google Play');
    });

    test('throws if json key file does not exist', () {
      final context = PipelineContext(
        config: const CIToolsConfig(appName: 'Test', seedBuildNumber: 1000),
      );
      context.set<String>('artifact_path', 'nonexistent.aab');
      context.set<String>('google_play_package_name', 'com.example');
      context.set<String>(
        'google_play_json_key_path',
        '/nonexistent/path.json',
      );

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });
  });
}
