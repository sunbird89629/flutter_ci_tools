// test/pipeline_context_test.dart
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

void main() {
  group('PipelineContext', () {
    late PipelineContext ctx;
    late CIToolsConfig config;

    setUp(() {
      config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000);
      ctx = PipelineContext(config: config, platforms: <AppPlatform>{});
    });

    group('construction', () {
      test('config is accessible', () {
        expect(ctx.config, same(config));
        expect(ctx.config.appName, 'TestApp');
      });

      test('exposes platforms passed to constructor', () {
        final context = PipelineContext(
          config: const CIToolsConfig(appName: 'A', seedBuildNumber: 10000),
          platforms: {AppPlatform.android},
        );
        expect(context.platforms, {AppPlatform.android});
      });
    });

    group('buildNumber and buildName', () {
      test('buildName formats buildNumber correctly', () {
        ctx.buildNumber = 12001;
        expect(ctx.buildName, '1.2.0');
      });

      test('buildName handles zeros', () {
        ctx.buildNumber = 10000;
        expect(ctx.buildName, '1.0.0');
      });

      test('buildName handles triple digits', () {
        ctx.buildNumber = 12345;
        expect(ctx.buildName, '1.2.3');
      });
    });

    group('metadata', () {
      test('metadata can be set and read', () {
        final meta = BuildMetadata(
          branch: 'main',
          gitUser: 'Alice',
          gitHash: 'abc1234',
          recentCommits: 'commits',
          commitBody: 'body',
        );
        ctx.metadata = meta;
        expect(ctx.metadata.branch, 'main');
        expect(ctx.metadata.gitHash, 'abc1234');
      });
    });

    group('store', () {
      test('set and get with correct type', () {
        ctx.set<String>('key', 'value');
        expect(ctx.get<String>('key'), 'value');
      });

      test('set and get with different types', () {
        ctx.set<int>('count', 42);
        ctx.set<bool>('flag', true);
        expect(ctx.get<int>('count'), 42);
        expect(ctx.get<bool>('flag'), true);
      });

      test('get throws on missing key', () {
        expect(() => ctx.get<String>('missing'), throwsA(isA<TypeError>()));
      });

      test('tryGet returns value when key exists', () {
        ctx.set<String>('key', 'value');
        expect(ctx.tryGet<String>('key'), 'value');
      });

      test('tryGet returns null when key missing', () {
        expect(ctx.tryGet<String>('missing'), isNull);
      });

      test('has returns true when key exists', () {
        ctx.set<String>('key', 'value');
        expect(ctx.has('key'), isTrue);
      });

      test('has returns false when key missing', () {
        expect(ctx.has('key'), isFalse);
      });

      test('set overwrites existing key', () {
        ctx.set<String>('key', 'first');
        ctx.set<String>('key', 'second');
        expect(ctx.get<String>('key'), 'second');
      });

      test('remove returns value and deletes key', () {
        ctx.set<String>('key', 'value');
        final removed = ctx.remove<String>('key');
        expect(removed, 'value');
        expect(ctx.has('key'), isFalse);
      });

      test('remove returns null for missing key', () {
        expect(ctx.remove<String>('missing'), isNull);
      });
    });
  });
}
