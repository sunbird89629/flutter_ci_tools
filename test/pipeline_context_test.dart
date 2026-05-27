import 'dart:io';

import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

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

    group('buildNumber (sealed)', () {
      test('throws StateError when accessed before resolution', () {
        expect(
          () => ctx.buildNumber,
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('buildNumber'),
          )),
        );
      });

      test('returns value after resolveBuildVersion', () {
        ctx.resolveBuildVersion(12001);
        expect(ctx.buildNumber, 12001);
      });

      test('buildName formats buildNumber correctly', () {
        ctx.resolveBuildVersion(12001);
        expect(ctx.buildName, '1.2.0');
      });

      test('buildName handles zeros', () {
        ctx.resolveBuildVersion(10000);
        expect(ctx.buildName, '1.0.0');
      });

      test('buildName handles triple digits', () {
        ctx.resolveBuildVersion(12345);
        expect(ctx.buildName, '1.2.3');
      });
    });

    group('buildArtifact', () {
      test('throws StateError when accessed before being set', () {
        expect(
          () => ctx.buildArtifact,
          throwsA(isA<StateError>()),
        );
      });

      test('returns file after setBuildArtifact', () {
        final file = File('test.apk');
        ctx.setBuildArtifact(file);
        expect(ctx.buildArtifact, file);
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
