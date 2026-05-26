import 'package:flutter_ci_tools/src/utils/default_shell_runner.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultShellRunner', () {
    late DefaultShellRunner shellRunner;

    setUp(() {
      shellRunner = DefaultShellRunner();
    });

    test('run completes successfully for a valid command', () async {
      await shellRunner.run('echo', ['hello']);
    });

    test('run throws StateError on non-zero exit code', () async {
      expect(
        () => shellRunner.run('false', []),
        throwsA(isA<StateError>()),
      );
    });

    test('runAndCapture captures stdout', () async {
      final result = await shellRunner.runAndCapture('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'hello');
      expect(result.stderr, isEmpty);
    });

    test('runAndCapture returns non-zero exit code without throwing', () async {
      final result = await shellRunner.runAndCapture('false', []);
      expect(result.exitCode, isNot(0));
    });
  });
}
