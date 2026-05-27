import 'package:flutter_ci_tools/src/action_status.dart';
import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _TestAction extends PipelineAction<void> {
  bool ran = false;
  PipelineContext? capturedContext;

  @override
  String get name => 'Test Action';

  @override
  Future<void> run(PipelineContext context) async {
    ran = true;
    capturedContext = context;
  }
}

void main() {
  test('PipelineAction run receives context', () async {
    final action = _TestAction();
    final context = PipelineContext(
      appName: 'Test',
      seedBuildNumber: 1000,
    );

    await action.run(context);

    expect(action.ran, isTrue);
    expect(action.capturedContext, same(context));
  });

  test('PipelineAction has a name', () {
    final action = _TestAction();
    expect(action.name, 'Test Action');
  });

  test('status is null before run', () {
    final action = _TestAction();
    expect(action.status, isNull);
    expect(action.hasRun, isFalse);
  });

  test('status can be set to success', () {
    final action = _TestAction();
    action.status = ActionStatus.success;
    action.duration = Duration(seconds: 5);
    expect(action.status, ActionStatus.success);
    expect(action.duration, Duration(seconds: 5));
    expect(action.hasRun, isTrue);
  });

  test('status can be set to failed with error', () {
    final action = _TestAction();
    final error = StateError('oops');
    action.status = ActionStatus.failed;
    action.duration = Duration(seconds: 2);
    action.error = error;
    action.stackTrace = StackTrace.current;
    expect(action.status, ActionStatus.failed);
    expect(action.error, same(error));
    expect(action.stackTrace, isNotNull);
  });
}
