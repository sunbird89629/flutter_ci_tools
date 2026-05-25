import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _RecordingAction extends PipelineAction<void> {
  _RecordingAction(this.label, this.log, {this.willThrow = false});
  final String label;
  final List<String> log;
  final bool willThrow;
  @override
  String get name => label;
  @override
  Future<void> run(PipelineContext context) async {
    log.add(label);
    if (willThrow) throw StateError('boom from $label');
  }
}

class _TestPipeline extends BuildPipeline {
  _TestPipeline(
      {required this.log, this.bodyThrows = false, this.afterThrows = false});

  final List<String> log;
  final bool bodyThrows;
  final bool afterThrows;

  @override
  String get name => 'test';
  @override
  String get description => 'test pipeline';
  @override
  String get help => 'help';

  @override
  PipelineContext createContext(Set<AppPlatform> platforms) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
        platforms: platforms,
      );

  @override
  Future<void> beforeBuild() async => log.add('before');

  @override
  Future<void> body() async {
    log.add('body-start');
    if (bodyThrows) throw StateError('body-failed');
    await runAction(_RecordingAction('action-a', log));
  }

  @override
  Future<void> afterBuild() => runAction(
        _RecordingAction('after', log, willThrow: afterThrows),
      );
}

void main() {
  group('BuildPipeline lifecycle', () {
    test('runs beforeBuild → body → afterBuild in order', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log);
      await pipeline.run({AppPlatform.android});
      expect(log, ['before', 'body-start', 'action-a', 'after']);
      expect(pipeline.context.platforms, {AppPlatform.android});
    });

    test('runs afterBuild even when body throws, and rethrows the body error',
        () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log, bodyThrows: true);
      await expectLater(
        pipeline.run({AppPlatform.android, AppPlatform.ios}),
        throwsA(isA<StateError>()),
      );
      expect(log, ['before', 'body-start', 'after']);
    });

    test(
        'afterBuild errors are swallowed (logged) so they do not mask body errors',
        () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log, afterThrows: true);
      await pipeline.run({AppPlatform.android}); // should NOT throw
      expect(log, containsAll(['before', 'body-start', 'action-a', 'after']));
    });
  });
}
