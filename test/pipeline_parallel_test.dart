import 'package:flutter_ci_tools/src/action_status.dart';
import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _TestAction extends PipelineAction<int> {
  _TestAction(this.value, {this.delay = Duration.zero});

  final int value;
  final Duration delay;

  @override
  Future<int> run(PipelineContext context) async {
    await Future.delayed(delay);
    return value;
  }
}

class _FailingAction extends PipelineAction<int> {
  @override
  Future<int> run(PipelineContext context) async {
    throw StateError('oops');
  }
}

class _TestPipeline extends Pipeline {
  @override
  PipelineContext createContext(List<String> args) =>
      PipelineContext(appName: 'test', seedBuildNumber: 1, rawArgs: args);

  @override
  String get help => 'test';

  @override
  Future<void> body() async {}
}

void main() {
  group('Pipeline runParallel', () {
    test('runs multiple actions in parallel and returns results in order', () async {
      final pipeline = _TestPipeline();
      await pipeline.run([]);

      final results = await pipeline.runParallel([
        _TestAction(1, delay: const Duration(milliseconds: 50)),
        _TestAction(2, delay: const Duration(milliseconds: 10)),
        _TestAction(3, delay: const Duration(milliseconds: 30)),
      ]);

      expect(results, [1, 2, 3]);
      expect(pipeline.executedActions.length, 3);
      expect(pipeline.allSucceeded, isTrue);
    });

    test('tracks status and duration for parallel actions', () async {
      final pipeline = _TestPipeline();
      await pipeline.run([]);

      await pipeline.runParallel([
        _TestAction(1),
        _TestAction(2),
      ]);

      for (final action in pipeline.executedActions) {
        expect(action.status, ActionStatus.success);
        expect(action.duration, isNotNull);
      }
    });
  });

  group('Pipeline runParallel with failure', () {
    test('one action fails - others still complete and get recorded', () async {
      final pipeline = _TestPipeline();
      await pipeline.run([]);

      Object? caughtError;
      try {
        await pipeline.runParallel([
          _TestAction(1),
          _FailingAction(),
          _TestAction(3),
        ]);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<StateError>());
      expect(pipeline.executedActions.length, 3);
      expect(pipeline.executedActions[0].status, ActionStatus.success);
      expect(pipeline.executedActions[1].status, ActionStatus.failed);
      expect(pipeline.executedActions[2].status, ActionStatus.success);
      expect(pipeline.lastFailure, isNotNull);
    });
  });
}
