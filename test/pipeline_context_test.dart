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
  });
}
