import 'dart:io';

import 'package:flutter_ci_tools/src/actions/pgyer_upload_v2_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

/// Fake that lets each test register handlers keyed by a substring match
/// against the assembled `exe + args` string.
class _ScriptedShellRunner implements ShellRunner {
  final List<_Handler> handlers = [];
  final List<String> calls = [];

  void on(String contains, ShellResult Function() respond) {
    handlers.add(_Handler(contains, respond));
  }

  @override
  Future<void> run(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async {
    final invocation = '$exe ${args.join(' ')}';
    calls.add(invocation);
    for (final h in handlers) {
      if (invocation.contains(h.contains)) return h.respond();
    }
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _Handler {
  _Handler(this.contains, this.respond);
  final String contains;
  final ShellResult Function() respond;
}

void main() {
  PipelineContext ctx() => PipelineContext(
        config: const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 1000),
        platforms: {AppPlatform.android},
      );

  group('PgyerUploadV2Action', () {
    test('name is correct', () {
      final action = PgyerUploadV2Action(
        artifact: File('test.apk'),
        apiKey: 'k',
      );
      expect(action.name, 'Upload to Pgyer (V2)');
    });

    test('happy path: probe → token → upload → poll → return URL', () async {
      final shell = _ScriptedShellRunner()
        // Domain probe: api.pgyer.com responds 200 (probe uses https://)
        ..on('https://api.pgyer.com/apiv2/app/getCOSToken', () =>
            ShellResult(exitCode: 0, stdout: '200', stderr: ''))
        // getCOSToken POST (POST uses http:// base URL, matched by _api_key)
        ..on('--form-string _api_key=k', () => ShellResult(
              exitCode: 0,
              stdout: '{"code":0,"data":{'
                  '"endpoint":"https://bucket.cos.region.myqcloud.com",'
                  '"key":"BUILD_KEY",'
                  '"signature":"SIG",'
                  '"x-cos-security-token":"TOK"}}',
              stderr: '',
            ))
        // COS upload → 204
        ..on('bucket.cos.region.myqcloud.com', () =>
            ShellResult(exitCode: 0, stdout: '204', stderr: ''))
        // buildInfo poll → success
        ..on('app/buildInfo?_api_key=k&buildKey=BUILD_KEY', () => ShellResult(
              exitCode: 0,
              stdout: '{"code":0,"data":{"buildShortcutUrl":"abcd"}}',
              stderr: '',
            ));

      // Create a real temp file so artifact.lengthSync() works
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final action = PgyerUploadV2Action(
          artifact: apk,
          apiKey: 'k',
          shellRunner: shell,
        );
        final url = await action.run(ctx());
        expect(url, 'https://pgyer.com/abcd');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('throws when all probe domains fail', () async {
      final shell = _ScriptedShellRunner()
        ..on('https://', () =>
            ShellResult(exitCode: 0, stdout: '000', stderr: ''));

      final action = PgyerUploadV2Action(
        artifact: File('test.apk'),
        apiKey: 'k',
        shellRunner: shell,
      );
      expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
    });

    test('throws when getCOSToken returns non-zero code', () async {
      final shell = _ScriptedShellRunner()
        // Probe ok
        ..on('https://api.pgyer.com/apiv2/app/getCOSToken', () =>
            ShellResult(exitCode: 0, stdout: '200', stderr: ''))
        // Token request fails
        ..on('--form-string _api_key=k', () => ShellResult(
              exitCode: 0,
              stdout: '{"code":1,"message":"bad key"}',
              stderr: '',
            ));

      final action = PgyerUploadV2Action(
        artifact: File('test.apk'),
        apiKey: 'k',
        shellRunner: shell,
      );
      expect(() => action.run(ctx()), throwsA(isA<DeployException>()));
    });

    test('throws when COS upload returns non-204', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final shell = _ScriptedShellRunner()
          ..on('https://api.pgyer.com/apiv2/app/getCOSToken', () =>
              ShellResult(exitCode: 0, stdout: '200', stderr: ''))
          ..on('--form-string _api_key=k', () => ShellResult(
                exitCode: 0,
                stdout: '{"code":0,"data":{'
                    '"endpoint":"https://bucket.cos.x.com",'
                    '"key":"K","signature":"S","x-cos-security-token":"T"}}',
                stderr: '',
              ))
          ..on('bucket.cos.x.com', () =>
              ShellResult(exitCode: 0, stdout: '500', stderr: ''));

        final action = PgyerUploadV2Action(
          artifact: apk,
          apiKey: 'k',
          shellRunner: shell,
        );
        await expectLater(action.run(ctx()), throwsA(isA<DeployException>()));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('falls back to second domain when first probe fails', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final shell = _ScriptedShellRunner()
          // First domain probe fails
          ..on('https://api.pgyer.com/apiv2/app/getCOSToken', () =>
              ShellResult(exitCode: 0, stdout: '000', stderr: ''))
          // Second domain probe succeeds
          ..on('https://api.xcxwo.com/apiv2/app/getCOSToken', () =>
              ShellResult(exitCode: 0, stdout: '200', stderr: ''))
          // The actual getCOSToken POST uses http:// + api.xcxwo.com — matches '_api_key=k'
          ..on('--form-string _api_key=k', () => ShellResult(
                exitCode: 0,
                stdout: '{"code":0,"data":{'
                    '"endpoint":"https://bucket.cos.x.com",'
                    '"key":"BK","signature":"S","x-cos-security-token":"T"}}',
                stderr: '',
              ))
          ..on('bucket.cos.x.com', () =>
              ShellResult(exitCode: 0, stdout: '204', stderr: ''))
          ..on('buildInfo?_api_key=k&buildKey=BK', () => ShellResult(
                exitCode: 0,
                stdout: '{"code":0,"data":{"buildShortcutUrl":"x"}}',
                stderr: '',
              ));

        final action = PgyerUploadV2Action(
          artifact: apk,
          apiKey: 'k',
          shellRunner: shell,
        );
        final url = await action.run(ctx());
        expect(url, 'https://xcxwo.com/x');
        // Confirm both probes were called
        expect(
          shell.calls.where((c) => c.contains('getCOSToken')).length,
          greaterThanOrEqualTo(2),
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
