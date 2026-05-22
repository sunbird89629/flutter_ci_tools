import 'package:flutter_ci_tools/src/actions/pgyer_upload_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final Map<String, ShellResult> _responses = {};
  ShellResult? _fallback;
  final List<String> runCalls = [];

  void stub(String executable, List<String> args, ShellResult result) {
    _responses['$executable ${args.join(' ')}'] = result;
  }

  void stubAny(ShellResult result) {
    _fallback = result;
  }

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    final key = '$executable ${args.join(' ')}';
    runCalls.add(key);
    return _responses[key] ??
        _fallback ??
        ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('PgyerUploadAction', () {
    late _FakeShellRunner shell;
    late PgyerUploadAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = PgyerUploadAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Upload to Pgyer');
    });

    test('uploads file and stores pgyer_url in context', () async {
      shell.stub(
        'curl',
        [
          '--http1.1',
          '-F',
          'file=@test.apk',
          '-F',
          '_api_key=test_api_key',
          'https://www.pgyer.com/apiv2/app/upload',
        ],
        ShellResult(
          exitCode: 0,
          stdout: '{"code":0,"data":{"buildKey":"abc123"}}',
          stderr: '',
        ),
      );

      final context = PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          pgyerApiKey: 'test_api_key',
        ),
      );
      context.set<String>('artifact_path', 'test.apk');

      await action.run(context);

      expect(context.get<String>('pgyer_url'), 'https://www.pgyer.com/abc123');
    });

    test('includes description when pgyer_description is set', () async {
      shell.stub(
        'curl',
        [
          '--http1.1',
          '-F',
          'file=@test.apk',
          '-F',
          '_api_key=test_api_key',
          '-F',
          'buildUpdateDescription=release notes',
          'https://www.pgyer.com/apiv2/app/upload',
        ],
        ShellResult(
          exitCode: 0,
          stdout: '{"code":0,"data":{"buildKey":"xyz"}}',
          stderr: '',
        ),
      );

      final context = PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          pgyerApiKey: 'test_api_key',
        ),
      );
      context.set<String>('artifact_path', 'test.apk');
      context.set<String>('pgyer_description', 'release notes');

      await action.run(context);

      expect(context.get<String>('pgyer_url'), 'https://www.pgyer.com/xyz');
    });

    test('throws DeployException on API error', () async {
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":1,"message":"Invalid API key"}',
        stderr: '',
      ));

      final context = PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          pgyerApiKey: 'test_api_key',
        ),
      );
      context.set<String>('artifact_path', 'test.apk');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });

    test('throws DeployException on JSON parse failure', () async {
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '<html>502 Bad Gateway</html>',
        stderr: '',
      ));

      final context = PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          pgyerApiKey: 'test_api_key',
        ),
      );
      context.set<String>('artifact_path', 'test.apk');

      expect(() => action.run(context), throwsA(isA<DeployException>()));
    });
  });
}
