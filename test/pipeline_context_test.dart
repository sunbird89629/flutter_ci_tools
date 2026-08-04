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
  group('construction', () {
    test('暴露配置字段，rawArgs 默认为空', () {
      final ctx = PipelineContext(appName: 'TestApp', seedBuildNumber: 12000);
      expect(ctx.appName, 'TestApp');
      expect(ctx.seedBuildNumber, 12000);
      expect(ctx.rawArgs, isEmpty);
    });

    test('args getter 包装 rawArgs', () {
      final ctx = PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 10000,
        rawArgs: ['android', '--env=test'],
      );
      expect(ctx.rawArgs, ['android', '--env=test']);
      expect(ctx.args.has('android'), isTrue);
      expect(ctx.args.getOption('env'), 'test');
    });

    test('暴露注入的 GitManager', () async {
      final git = _FakeGitManager();
      final ctx = PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 12000,
        git: git,
      );
      expect(identical(ctx.git, git), isTrue);
      expect(await ctx.git.getBranch(), 'main');
    });
  });

  group('KV bag', () {
    late PipelineContext ctx;
    setUp(() {
      ctx = PipelineContext(appName: 'TestApp', seedBuildNumber: 12000);
    });

    test('put / get 按类型取回值', () {
      final file = File('test.apk');
      ctx
        ..put('k', 42)
        ..put(ContextKeys.buildArtifact, file);
      expect(ctx.get<int>('k'), 42);
      expect(ctx.get<File>(ContextKeys.buildArtifact), file);
    });

    test('get 缺 key 时抛 StateError，且带上 key 名', () {
      expect(
        () => ctx.get<int>('missing'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('missing'))),
      );
    });

    test('tryGet 缺 key 时返回 null', () {
      ctx.put('url', 'https://x');
      expect(ctx.tryGet<String>('url'), 'https://x');
      expect(ctx.tryGet<String>('missing'), isNull);
    });
  });

  test('buildName 由 buildNumber 拆成 x.y.z', () {
    final ctx = PipelineContext(appName: 'TestApp', seedBuildNumber: 12000);
    for (final (number, name) in [
      (10000, '1.0.0'),
      (12001, '1.2.0'),
      (12345, '1.2.3'),
    ]) {
      ctx.put(ContextKeys.buildNumber, number);
      expect(ctx.buildName, name, reason: '$number 应格式化为 $name');
    }
  });

  group('pubspec 字段', () {
    test('读取本包 name 与 version', () {
      final ctx = _ctx();
      expect(ctx.pubspecName, equals('flutter_ci_tools'));
      // 不写死版本号：这里验的是「能从 pubspec 读出版本」，
      // 写死会让每次 bump 都误报失败（0.0.4 → 0.1.0 时就断过一次）
      expect(ctx.pubspecVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
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

  group('projectRoot', () {
    test('从嵌套子目录向上找到含 pubspec.yaml 的包根', () {
      expect(
        File('${_ctx().projectRoot.path}/pubspec.yaml').existsSync(),
        isTrue,
      );

      final original = Directory.current;
      final tmp = Directory.systemTemp.createTempSync('pctx_');
      try {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: tmp_pkg\n');
        Directory('${tmp.path}/a/b/c').createSync(recursive: true);
        Directory.current = '${tmp.path}/a/b/c';
        // resolveSymbolicLinks 消除 macOS /private/var 与 /var 符号链接差异
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
