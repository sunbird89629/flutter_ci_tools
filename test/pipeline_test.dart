import 'package:flutter_ci_tools/src/action_status.dart';
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
  PipelineContext createContext(List<String> args) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
        rawArgs: args,
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

class _SimpleAction extends PipelineAction<String> {
  _SimpleAction(this.label, {this.result = 'ok', this.willThrow = false});
  final String label;
  final String result;
  final bool willThrow;
  @override
  String get name => label;
  @override
  Future<String> run(PipelineContext context) async {
    if (willThrow) throw StateError('fail from $label');
    return result;
  }
}

class _ValuePipeline extends BuildPipeline {
  String? returnValue;
  @override
  String get name => 'value-test';
  @override
  String get description => 'test';
  @override
  String get help => 'help';
  @override
  PipelineContext createContext(List<String> args) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
      );
  @override
  Future<void> body() async {
    returnValue = await runAction(_SimpleAction('s1', result: 'hello'));
  }
}

class _FailActionPipeline extends BuildPipeline {
  @override
  String get name => 'fail-test';
  @override
  String get description => 'test';
  @override
  String get help => 'help';
  @override
  PipelineContext createContext(List<String> args) => PipelineContext(
        appName: 'A',
        seedBuildNumber: 10000,
      );
  @override
  Future<void> body() async {
    await runAction(_SimpleAction('ok-action'));
    await runAction(_SimpleAction('will-fail', willThrow: true));
  }
}

void main() {
  group('BuildPipeline lifecycle', () {
    test('runs beforeBuild → body → afterBuild in order', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log);
      await pipeline.run([]);
      expect(log, ['before', 'body-start', 'action-a', 'after']);
    });

    test('runs afterBuild even when body throws, and rethrows the body error',
        () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log, bodyThrows: true);
      await expectLater(
        pipeline.run([]),
        throwsA(isA<StateError>()),
      );
      expect(log, ['before', 'body-start', 'after']);
    });

    test(
        'afterBuild errors are swallowed (logged) so they do not mask body errors',
        () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log, afterThrows: true);
      await pipeline.run([]); // should NOT throw
      expect(log, containsAll(['before', 'body-start', 'action-a', 'after']));
    });
  });

  group('action status tracking', () {
    test('records success status and duration on action', () async {
      final pipeline = _TestPipeline(log: []);
      await pipeline.run([]);
      final actionA = pipeline.executedActions
          .firstWhere((a) => a.name == 'action-a');
      expect(actionA.status, ActionStatus.success);
      expect(actionA.duration, isNotNull);
      expect(actionA.duration!.inMilliseconds, greaterThanOrEqualTo(0));
      expect(actionA.error, isNull);
      expect(actionA.stackTrace, isNull);
    });

    test('records failed status with error on action', () async {
      final pipeline = _FailActionPipeline();
      await expectLater(
        pipeline.run([]),
        throwsA(isA<StateError>()),
      );
      expect(pipeline.executedActions.first.name, 'ok-action');
      expect(pipeline.executedActions.first.status, ActionStatus.success);
      expect(pipeline.executedActions.last.name, 'will-fail');
      expect(pipeline.executedActions.last.status, ActionStatus.failed);
      expect(pipeline.executedActions.last.error, isA<StateError>());
    });

    test('executedActions preserves execution order', () async {
      final log = <String>[];
      final pipeline = _TestPipeline(log: log);
      await pipeline.run([]);
      expect(pipeline.executedActions.map((a) => a.name),
          ['action-a', 'after']);
    });

    test('allSucceeded returns true when all actions succeed', () async {
      final pipeline = _TestPipeline(log: []);
      await pipeline.run([]);
      expect(pipeline.allSucceeded, isTrue);
      expect(pipeline.lastFailure, isNull);
    });

    test('allSucceeded returns false and lastFailure returns failed action',
        () async {
      final pipeline = _FailActionPipeline();
      await expectLater(
        pipeline.run([]),
        throwsA(isA<StateError>()),
      );
      expect(pipeline.allSucceeded, isFalse);
      expect(pipeline.lastFailure, isNotNull);
      expect(pipeline.lastFailure!.name, 'will-fail');
      expect(pipeline.lastFailure!.error, isA<StateError>());
      expect(pipeline.executedActions.first.name, 'ok-action');
      expect(pipeline.executedActions.first.status, ActionStatus.success);
    });

    test('runAction returns the action result', () async {
      final pipeline = _ValuePipeline();
      await pipeline.run([]);
      expect(pipeline.returnValue, 'hello');
      expect(pipeline.executedActions.first.status, ActionStatus.success);
    });
  });
}
