import 'package:flutter_ci_tools/src/action_status.dart';
import 'package:flutter_ci_tools/src/actions/pipeline_action.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

class _TestAction extends PipelineAction {
  @override
  Future<void> run(PipelineContext context) async {}
}

void main() {
  // status / duration / error 的记录由 pipeline_test.dart 端到端覆盖，
  // 这里只验基类自己那点逻辑。
  test('hasRun 跟随 status 变化', () {
    final action = _TestAction();
    expect(action.hasRun, isFalse);

    action.status = ActionStatus.success;
    expect(action.hasRun, isTrue);
  });

  test('name 默认取类名，description 由 CamelCase 拆成句子', () {
    expect(_TestAction().name, '_TestAction');
    expect(_TestAction().description, '_ test action');
  });
}
