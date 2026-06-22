import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  @override
  void setLogger(Logger logger) {}
  final List<String> runCalls = [];

  @override
  Future<void> run(String exe, List<String> args) async {
    runCalls.add('$exe ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  late _FakeShellRunner shell;
  late PipelineContext context;

  setUp(() {
    shell = _FakeShellRunner();
    context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
    )..put(ContextKeys.buildNumber, 12001);
  });

  test(
      'BuildIOSAction runs flutter build ipa with export method, env, and version',
      () async {
    final action = BuildIOSAction(
      envName: 'prod',
      exportMethod: 'app-store',
      shellRunner: shell,
    );

    // _findIpa will throw StateError because build/ios/ipa won't exist,
    // but the flutter build command should have been run first.
    try {
      await action.run(context);
    } on StateError {
      // Expected — _findIpa fails because the directory doesn't exist
    }

    expect(action.name, 'Build iOS');
    expect(
      shell.runCalls,
      contains(
        'fvm flutter build ipa --export-method=app-store --build-name=1.2.0 --build-number=12001 --dart-define=ENV=prod',
      ),
    );
  });

  test('BuildIOSAction throws StateError if IPA directory not found', () async {
    final action = BuildIOSAction(
      envName: 'test',
      exportMethod: 'ad-hoc',
      shellRunner: shell,
    );

    await expectLater(action.run(context), throwsStateError);
  });

  test('BuildIOSAction default constructor does not throw', () {
    final action = BuildIOSAction(envName: 'prod', exportMethod: 'app-store');
    expect(action, isA<BuildIOSAction>());
  });
}
