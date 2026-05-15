import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';
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
  late _FakeShellRunner shell;
  late DefaultDeployService deploy;

  setUp(() {
    shell = _FakeShellRunner();
    deploy = DefaultDeployService(shellRunner: shell);
  });

  group('uploadToPgyer', () {
    test('parses successful response and returns download URL', () async {
      shell.stub('curl', [
        '--http1.1',
        '-F', 'file=@test.apk',
        '-F', '_api_key=key123',
        'https://www.pgyer.com/apiv2/app/upload',
      ], ShellResult(exitCode: 0, stdout: '{"code":0,"data":{"buildKey":"abc123"}}', stderr: ''));

      final url = await deploy.uploadToPgyer('test.apk', 'key123');
      expect(url, 'https://www.pgyer.com/abc123');
    });

    test('throws DeployException on API error code', () async {
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '{"code":1,"message":"Invalid API key"}',
        stderr: '',
      ));

      expect(
        () => deploy.uploadToPgyer('test.apk', 'key123'),
        throwsA(isA<DeployException>()),
      );
    });

    test('throws DeployException on JSON parse failure', () async {
      shell.stubAny(ShellResult(
        exitCode: 0,
        stdout: '<html>502 Bad Gateway</html>',
        stderr: '',
      ));

      expect(
        () => deploy.uploadToPgyer('test.apk', 'key123'),
        throwsA(isA<DeployException>()),
      );
    });

    test('includes update description when provided', () async {
      shell.stub('curl', [
        '--http1.1',
        '-F', 'file=@test.apk',
        '-F', '_api_key=key123',
        '-F', 'buildUpdateDescription=release notes',
        'https://www.pgyer.com/apiv2/app/upload',
      ], ShellResult(exitCode: 0, stdout: '{"code":0,"data":{"buildKey":"xyz"}}', stderr: ''));

      final url = await deploy.uploadToPgyer('test.apk', 'key123',
          updateDescription: 'release notes');
      expect(url, 'https://www.pgyer.com/xyz');
    });
  });

  group('sendFeishuNotification', () {
    test('sends POST with correct JSON payload', () async {
      shell.stubAny(ShellResult(exitCode: 0, stdout: '', stderr: ''));

      await deploy.sendFeishuNotification(
        'https://hooks.example.com/webhook',
        'Hello from CI',
      );

      expect(
        shell.runCalls,
        contains(
          contains('https://hooks.example.com/webhook'),
        ),
      );
    });
  });

  group('uploadToGooglePlay', () {
    test('throws if json key file does not exist', () async {
      expect(
        () => deploy.uploadToGooglePlay(
          File('nonexistent.aab'),
          packageName: 'com.example',
          jsonKeyPath: '/nonexistent/path.json',
        ),
        throwsA(isA<DeployException>()),
      );
    });
  });
}
