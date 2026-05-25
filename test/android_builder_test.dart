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

  setUp(() {
    shell = _FakeShellRunner();
  });

  group('AndroidBuilder', () {
    test('buildApk runs correct flutter build apk command', () async {
      final builder = AndroidBuilder(shellRunner: shell);
      final file = await builder.buildApk(
        buildName: '1.2.0',
        buildNumber: 12001,
        envName: 'test',
      );

      expect(
        shell.runCalls,
        contains(
            'fvm flutter build apk --build-name=1.2.0 --build-number=12001 --dart-define=ENV=test'),
      );
      expect(file.path, 'build/app/outputs/flutter-apk/app-release.apk');
    });

    test('buildAppBundle runs correct flutter build appbundle command',
        () async {
      final builder = AndroidBuilder(shellRunner: shell);
      final file = await builder.buildAppBundle(
        buildName: '1.0.0',
        buildNumber: 10000,
        envName: 'prod',
      );

      expect(
        shell.runCalls,
        contains(
            'fvm flutter build appbundle --build-name=1.0.0 --build-number=10000 --dart-define=ENV=prod'),
      );
      expect(file.path, 'build/app/outputs/bundle/release/app-release.aab');
    });

    test('default constructor does not throw', () {
      final builder = AndroidBuilder();
      expect(builder, isA<AndroidBuilder>());
    });
  });
}
