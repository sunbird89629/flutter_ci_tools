import 'dart:io';

import 'package:flutter_ci_tools/src/context_keys.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/utils/git_manager.dart';
import 'package:test/test.dart';

PipelineContext _ctx() =>
    PipelineContext(appName: 'demo', seedBuildNumber: 100000);

class _FakeGitManager implements GitManager {
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> resetHard() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<void> restoreWorkspace() async {}
  @override
  Future<String> getShortHash() async => 'abc1234';
  @override
  Future<String> getRecentCommits({int count = 10}) async => 'log';
  @override
  Future<String> getBranch() async => 'main';
  @override
  Future<String> getCurrentUser() async => 'Alice';
  @override
  Future<String> getLatestCommitBody() async => 'body';
}

void main() {
  group('PipelineContext', () {
    late PipelineContext ctx;

    setUp(() {
      ctx = PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 12000,
      );
    });

    group('construction', () {
      test('exposes config fields', () {
        expect(ctx.appName, 'TestApp');
        expect(ctx.seedBuildNumber, 12000);
      });

      test('exposes rawArgs', () {
        final ctx = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 10000,
          rawArgs: ['android', '--debug'],
        );
        expect(ctx.rawArgs, ['android', '--debug']);
      });

      test('args getter returns ArgsParser wrapping rawArgs', () {
        final ctx = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 10000,
          rawArgs: ['android', '--env=test'],
        );
        expect(ctx.args.has('android'), isTrue);
        expect(ctx.args.getOption('env'), 'test');
      });

      test('rawArgs defaults to empty list', () {
        final ctx = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 10000,
        );
        expect(ctx.rawArgs, isEmpty);
      });
    });

    group('buildNumber via bag', () {
      test('get throws StateError when buildNumber absent', () {
        expect(
          () => ctx.get<int>(ContextKeys.buildNumber),
          throwsA(isA<StateError>()),
        );
      });

      test('returns value after put', () {
        ctx.put(ContextKeys.buildNumber, 12001);
        expect(ctx.get<int>(ContextKeys.buildNumber), 12001);
      });

      test('buildName formats buildNumber correctly', () {
        ctx.put(ContextKeys.buildNumber, 12001);
        expect(ctx.buildName, '1.2.0');
      });

      test('buildName handles zeros', () {
        ctx.put(ContextKeys.buildNumber, 10000);
        expect(ctx.buildName, '1.0.0');
      });

      test('buildName handles triple digits', () {
        ctx.put(ContextKeys.buildNumber, 12345);
        expect(ctx.buildName, '1.2.3');
      });
    });

    group('buildArtifact via bag', () {
      test('get throws StateError when artifact absent', () {
        expect(
          () => ctx.get<File>(ContextKeys.buildArtifact),
          throwsA(isA<StateError>()),
        );
      });

      test('returns file after put', () {
        final file = File('test.apk');
        ctx.put(ContextKeys.buildArtifact, file);
        expect(ctx.get<File>(ContextKeys.buildArtifact), file);
      });
    });

    group('git', () {
      test('exposes the injected GitManager', () async {
        final git = _FakeGitManager();
        final c = PipelineContext(
          appName: 'TestApp',
          seedBuildNumber: 12000,
          git: git,
        );
        expect(identical(c.git, git), isTrue);
        expect(await c.git.getBranch(), 'main');
      });
    });
  });

  group('pubspec 字段', () {
    test('读取本包 name 与 version', () {
      final ctx = _ctx();
      expect(ctx.pubspecName, equals('flutter_ci_tools'));
      expect(ctx.pubspecVersion, equals('0.0.4'));
    });

    test('字段缺失时抛 StateError', () {
      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_noname_');
      try {
        // 只写 version，不写 name
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('version: 9.9.9\n');
        Directory.current = tmp;
        expect(() => _ctx().pubspecName, throwsStateError);
      } finally {
        Directory.current = original;
        tmp.deleteSync(recursive: true);
      }
    });
  });

  group('KV bag', () {
    late PipelineContext ctx;
    setUp(() {
      ctx = PipelineContext(appName: 'TestApp', seedBuildNumber: 12000);
    });

    test('get returns the value put under a key', () {
      ctx.put('k', 42);
      expect(ctx.get<int>('k'), 42);
    });

    test('get throws StateError with key name when key absent', () {
      expect(
        () => ctx.get<int>('missing'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('missing'))),
      );
    });

    test('tryGet returns null when key absent', () {
      expect(ctx.tryGet<String>('missing'), isNull);
    });

    test('tryGet returns the value when present', () {
      ctx.put('url', 'https://x');
      expect(ctx.tryGet<String>('url'), 'https://x');
    });
  });

  group('projectRoot', () {
    test('定位到含 pubspec.yaml 的包根目录', () {
      final root = _ctx().projectRoot;
      expect(File('${root.path}/pubspec.yaml').existsSync(), isTrue);
    });

    test('从嵌套子目录向上查找', () {
      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_');
      try {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: tmp_pkg\n');
        final nested = Directory('${tmp.path}/a/b/c')
          ..createSync(recursive: true);
        Directory.current = nested;
        // canonicalize 消除 macOS /private/var 与 /var 符号链接差异
        expect(
          _ctx().projectRoot.resolveSymbolicLinksSync(),
          equals(tmp.resolveSymbolicLinksSync()),
        );
      } finally {
        Directory.current = original;
        tmp.deleteSync(recursive: true);
      }
    });

    test('找不到 pubspec.yaml 时抛 StateError', () {
      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_empty_');
      try {
        Directory.current = tmp;
        expect(() => _ctx().projectRoot, throwsStateError);
      } finally {
        Directory.current = original;
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
