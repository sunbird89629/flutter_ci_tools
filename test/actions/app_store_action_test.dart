import 'package:flutter_ci_tools/src/actions/app_store_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
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
  group('AppStoreUploadAction', () {
    late _FakeShellRunner shell;
    late AppStoreUploadAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = AppStoreUploadAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Upload to App Store');
    });

    test('throws if api key file does not exist', () {
      final context = PipelineContext(
        config: const CIToolsConfig(appName: 'Test', seedBuildNumber: 1000),
        platforms: <AppPlatform>{},
      );
      context.set<String>('artifact_path', 'nonexistent.ipa');
      context.set<String>('app_store_issuer_id', 'issuer123');
      context.set<String>('app_store_api_key_id', 'key123');
      context.set<String>('app_store_api_key_path', '/nonexistent/key.p8');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });
  });
}
