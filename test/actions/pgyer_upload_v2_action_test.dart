import 'dart:io';

import 'package:flutter_ci_tools/src/actions/pgyer_upload_v2_action.dart';
import 'package:flutter_ci_tools/src/context_keys.dart';
import 'package:flutter_ci_tools/src/utils/exceptions.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/shell_runner.dart';
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

/// Returns a probe function that records every domain it's asked about and
/// reports reachability based on [reachable].
({Future<bool> Function(String) probe, List<String> probed}) probeStub(
  bool Function(String domain) reachable,
) {
  final probed = <String>[];
  Future<bool> probe(String domain) async {
    probed.add(domain);
    return reachable(domain);
  }

  return (probe: probe, probed: probed);
}

void main() {
  PipelineContext ctx() => PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 1000,
      );

  group('PgyerUploadV2Action', () {
    test('name is correct', () {
      final action = PgyerUploadV2Action(
        apiKey: 'k',
      );
      expect(action.name, 'Upload to Pgyer (V2)');
    });

    test('happy path: probe → token → upload → poll → write URL to bag', () async {
      final shell = _ScriptedShellRunner()
        ..on(
            '--form-string _api_key=k',
            () => ShellResult(
                  exitCode: 0,
                  stdout: '{"code":0,"data":{'
                      '"endpoint":"https://bucket.cos.region.myqcloud.com",'
                      '"key":"BUILD_KEY",'
                      '"signature":"SIG",'
                      '"x-cos-security-token":"TOK"}}',
                  stderr: '',
                ))
        ..on('bucket.cos.region.myqcloud.com',
            () => ShellResult(exitCode: 0, stdout: '204', stderr: ''))
        ..on(
            'app/buildInfo?_api_key=k&buildKey=BUILD_KEY',
            () => ShellResult(
                  exitCode: 0,
                  stdout: '{"code":0,"data":{"buildShortcutUrl":"abcd"}}',
                  stderr: '',
                ));

      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final context = ctx()..put(ContextKeys.buildArtifact, apk);
        final action = PgyerUploadV2Action(
          apiKey: 'k',
          probeDomain: (d) async => d == 'api.pgyer.com',
          shellRunner: shell,
        );
        await action.run(context);
        expect(context.get<String>(ContextKeys.pgyerDownloadUrl),
            'https://pgyer.com/abcd');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('throws when all probe domains fail', () async {
      final context = ctx()..put(ContextKeys.buildArtifact, File('test.apk'));
      final action = PgyerUploadV2Action(
        apiKey: 'k',
        probeDomain: (_) async => false,
        shellRunner: _ScriptedShellRunner(),
      );
      await expectLater(action.run(context), throwsA(isA<DeployException>()));
    });

    test('throws when getCOSToken returns non-zero code', () async {
      final shell = _ScriptedShellRunner()
        ..on(
            '--form-string _api_key=k',
            () => ShellResult(
                  exitCode: 0,
                  stdout: '{"code":1,"message":"bad key"}',
                  stderr: '',
                ));

      final context = ctx()..put(ContextKeys.buildArtifact, File('test.apk'));
      final action = PgyerUploadV2Action(
        apiKey: 'k',
        probeDomain: (_) async => true,
        shellRunner: shell,
      );
      await expectLater(action.run(context), throwsA(isA<DeployException>()));
    });

    test('throws when COS upload returns non-204', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final shell = _ScriptedShellRunner()
          ..on(
              '--form-string _api_key=k',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{'
                        '"endpoint":"https://bucket.cos.x.com",'
                        '"key":"K","signature":"S","x-cos-security-token":"T"}}',
                    stderr: '',
                  ))
          ..on('bucket.cos.x.com',
              () => ShellResult(exitCode: 0, stdout: '500', stderr: ''));

        final context = ctx()..put(ContextKeys.buildArtifact, apk);
        final action = PgyerUploadV2Action(
          apiKey: 'k',
          probeDomain: (_) async => true,
          shellRunner: shell,
        );
        await expectLater(action.run(context), throwsA(isA<DeployException>()));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('falls back to second domain when first probe fails', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final stub = probeStub((d) => d == 'api.xcxwo.com');
        final shell = _ScriptedShellRunner()
          ..on(
              '--form-string _api_key=k',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{'
                        '"endpoint":"https://bucket.cos.x.com",'
                        '"key":"BK","signature":"S","x-cos-security-token":"T"}}',
                    stderr: '',
                  ))
          ..on('bucket.cos.x.com',
              () => ShellResult(exitCode: 0, stdout: '204', stderr: ''))
          ..on(
              'buildInfo?_api_key=k&buildKey=BK',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{"buildShortcutUrl":"x"}}',
                    stderr: '',
                  ));

        final context = ctx()..put(ContextKeys.buildArtifact, apk);
        final action = PgyerUploadV2Action(
          apiKey: 'k',
          probeDomain: stub.probe,
          shellRunner: shell,
        );
        await action.run(context);
        expect(context.get<String>(ContextKeys.pgyerDownloadUrl),
            'https://xcxwo.com/x');
        // First domain probed and rejected, second probed and accepted.
        expect(stub.probed, ['api.pgyer.com', 'api.xcxwo.com']);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('uses explicit artifact when provided', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final explicitFile = File('${tmp.path}/explicit.aab')
        ..writeAsStringSync('explicit');
      try {
        final shell = _ScriptedShellRunner()
          ..on(
              '--form-string _api_key=k',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{'
                        '"endpoint":"https://bucket.cos.x.com",'
                        '"key":"EXPLICIT","signature":"S","x-cos-security-token":"T"}}',
                    stderr: '',
                  ))
          ..on('bucket.cos.x.com',
              () => ShellResult(exitCode: 0, stdout: '204', stderr: ''))
          ..on(
              'buildInfo?_api_key=k&buildKey=EXPLICIT',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{"buildShortcutUrl":"explicit"}}',
                    stderr: '',
                  ));

        // Don't set ContextKeys.buildArtifact — explicit artifact should be used
        final context = ctx();
        final action = PgyerUploadV2Action(
          apiKey: 'k',
          artifact: explicitFile,
          probeDomain: (_) async => true,
          shellRunner: shell,
        );
        await action.run(context);
        expect(context.get<String>(ContextKeys.pgyerDownloadUrl),
            'https://pgyer.com/explicit');
        expect(
          shell.calls.any((c) => c.contains('file=@${explicitFile.path}')),
          isTrue,
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('handles nested params in getCOSToken response (new API format)', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/test.apk')..writeAsStringSync('fake');
      try {
        final shell = _ScriptedShellRunner()
          ..on(
              '--form-string _api_key=k',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{'
                        '"endpoint":"https://bucket.cos.region.myqcloud.com",'
                        '"key":"BUILD_KEY",'
                        '"params":{'
                        '"signature":"SIG_NESTED",'
                        '"x-cos-security-token":"TOK_NESTED"}}}',
                    stderr: '',
                  ))
          ..on('bucket.cos.region.myqcloud.com',
              () => ShellResult(exitCode: 0, stdout: '204', stderr: ''))
          ..on(
              'app/buildInfo?_api_key=k&buildKey=BUILD_KEY',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{"buildShortcutUrl":"nested"}}',
                    stderr: '',
                  ));

        final context = ctx()..put(ContextKeys.buildArtifact, apk);
        final action = PgyerUploadV2Action(
          apiKey: 'k',
          probeDomain: (d) async => d == 'api.pgyer.com',
          shellRunner: shell,
        );
        await action.run(context);
        expect(context.get<String>(ContextKeys.pgyerDownloadUrl),
            'https://pgyer.com/nested');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('falls back to ContextKeys.buildArtifact when artifact is null', () async {
      final tmp = Directory.systemTemp.createTempSync();
      final apk = File('${tmp.path}/fallback.apk')..writeAsStringSync('fake');
      try {
        final shell = _ScriptedShellRunner()
          ..on(
              '--form-string _api_key=k',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{'
                        '"endpoint":"https://bucket.cos.x.com",'
                        '"key":"FALLBACK","signature":"S","x-cos-security-token":"T"}}',
                    stderr: '',
                  ))
          ..on('bucket.cos.x.com',
              () => ShellResult(exitCode: 0, stdout: '204', stderr: ''))
          ..on(
              'buildInfo?_api_key=k&buildKey=FALLBACK',
              () => ShellResult(
                    exitCode: 0,
                    stdout: '{"code":0,"data":{"buildShortcutUrl":"fb"}}',
                    stderr: '',
                  ));

        final context = ctx()..put(ContextKeys.buildArtifact, apk);
        final action = PgyerUploadV2Action(
          apiKey: 'k',
          probeDomain: (_) async => true,
          shellRunner: shell,
        );
        await action.run(context);
        expect(context.get<String>(ContextKeys.pgyerDownloadUrl),
            'https://pgyer.com/fb');
        expect(
          shell.calls.any((c) => c.contains('file=@${apk.path}')),
          isTrue,
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
