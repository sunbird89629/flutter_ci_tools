import 'dart:io';

import 'package:flutter_ci_tools/src/actions/pgyer_upload_action.dart';
import 'package:flutter_ci_tools/src/utils/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final Map<String, ShellResult> _responses = {};
  ShellResult? _fallback;
  final List<String> runCalls = [];

  void stub(String exe, List<String> args, ShellResult r) =>
      _responses['$exe ${args.join(' ')}'] = r;
  void stubAny(ShellResult r) => _fallback = r;

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final key = '$exe ${args.join(' ')}';
    runCalls.add(key);
    return _responses[key] ??
        _fallback ??
        ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  PipelineContext ctx() => PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 1000,
        platforms: {AppPlatform.android},
      );

  test('returns download URL on success', () async {
    final shell = _FakeShellRunner()
      ..stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":0,"data":{"buildKey":"abc123"}}',
        stderr: '',
      ));
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'test_api_key',
      shellRunner: shell,
    );

    final url = await action.run(ctx());
    expect(url, 'https://www.pgyer.com/abc123');
  });

  test('includes description when provided', () async {
    final shell = _FakeShellRunner()
      ..stub(
        'curl',
        [
          '--http1.1',
          '-F',
          'file=@test.apk',
          '-F',
          '_api_key=k',
          '-F',
          'buildUpdateDescription=notes',
          'https://api.xcxwo.com/apiv2/app/upload',
        ],
        ShellResult(
          exitCode: 0,
          stdout: '{"code":0,"data":{"buildKey":"xyz"}}',
          stderr: '',
        ),
      );
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'k',
      description: 'notes',
      shellRunner: shell,
    );
    final url = await action.run(ctx());
    expect(url, 'https://www.pgyer.com/xyz');
  });

  test('throws DeployException on API error', () async {
    final shell = _FakeShellRunner()
      ..stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":1,"message":"bad key"}',
        stderr: '',
      ));
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'k',
      shellRunner: shell,
    );
    expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
  });

  test('throws DeployException on JSON parse failure', () async {
    final shell = _FakeShellRunner()
      ..stubAny(ShellResult(
        exitCode: 0,
        stdout: '<html>502 Bad Gateway</html>',
        stderr: '',
      ));
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'k',
      shellRunner: shell,
    );
    expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
  });

  test('name is correct', () {
    final action = PgyerUploadAction(
      artifact: File('test.apk'),
      apiKey: 'k',
    );
    expect(action.name, 'Upload to Pgyer');
  });
}
