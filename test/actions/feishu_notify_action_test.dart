import 'package:flutter_ci_tools/src/actions/feishu_notify_action.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final List<String> runCalls = [];
  final List<List<String>> capturedArgs = [];

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
    capturedArgs.add(args);
  }

  @override
  Future<ShellResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    runCalls.add('$executable ${args.join(' ')}');
    capturedArgs.add(args);
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('FeishuNotifyAction', () {
    late _FakeShellRunner shell;
    late FeishuNotifyAction action;

    setUp(() {
      shell = _FakeShellRunner();
      action = FeishuNotifyAction(shellRunner: shell);
    });

    test('name is correct', () {
      expect(action.name, 'Send Feishu Notification');
    });

    test('sends POST with correct JSON payload', () async {
      final context = PipelineContext(
        config: const CIToolsConfig(
          appName: 'TestApp',
          seedBuildNumber: 1000,
          feishuWebhookUrl: 'https://hooks.example.com/webhook',
        ),
        platforms: <AppPlatform>{},
      );
      context.set<String>('notification_message', 'Hello from CI');

      await action.run(context);

      expect(shell.runCalls, contains(contains('https://hooks.example.com/webhook')));
      expect(shell.capturedArgs.first.join(' '), contains('Hello from CI'));
    });
  });
}
