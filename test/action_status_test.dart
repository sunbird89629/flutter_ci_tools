import 'package:flutter_ci_tools/src/action_status.dart';
import 'package:test/test.dart';

void main() {
  group('ActionStatus', () {
    test('has four values', () {
      expect(ActionStatus.values, hasLength(4));
    });

    test('contains success, failed, skipped, interrupted', () {
      expect(
          ActionStatus.values,
          containsAll([
            ActionStatus.success,
            ActionStatus.failed,
            ActionStatus.skipped,
            ActionStatus.interrupted,
          ]));
    });
  });
}
