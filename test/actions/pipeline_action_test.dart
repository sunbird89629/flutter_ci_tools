import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
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
      platforms: <AppPlatform>{},
    );

    await action.run(context);

    expect(action.ran, isTrue);
    expect(action.capturedContext, same(context));
  });

  test('PipelineAction has a name', () {
    final action = _TestAction();
    expect(action.name, 'Test Action');
  });
}
