import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
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
      platforms: <AppPlatform>{},
    )..resolveBuildVersion(12001);
  });

  test('BuildAndroidAction(apk) stores apk in context', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.apk,
      shellRunner: shell,
    );

    await action.run(context);

    expect(action.name, 'Build Android');
    expect(
        context.buildArtifact.path, 'build/app/outputs/flutter-apk/app-release.apk');
    expect(
      shell.runCalls,
      contains(
        'fvm flutter build apk --build-name=1.2.0 --build-number=12001 --dart-define=ENV=prod',
      ),
    );
  });

  test('BuildAndroidAction(appbundle) stores aab in context', () async {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.appbundle,
      shellRunner: shell,
    );

    await action.run(context);

    expect(context.buildArtifact.path,
        'build/app/outputs/bundle/release/app-release.aab');
    expect(
      shell.runCalls,
      contains(
        'fvm flutter build appbundle --build-name=1.2.0 --build-number=12001 --dart-define=ENV=prod',
      ),
    );
  });

  test('BuildAndroidAction default constructor does not throw', () {
    final action = BuildAndroidAction(
      envName: 'prod',
      buildType: AndroidBuildType.apk,
    );
    expect(action, isA<BuildAndroidAction>());
  });
}
