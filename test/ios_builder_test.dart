import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:flutter_ci_tools/src/builders/ios_builder.dart';
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

  group('IOSBuilder', () {
    test('buildIpa runs correct flutter build ipa command', () async {
      final builder = IOSBuilder(shellRunner: shell);
      // buildIpa will throw StateError because build/ios/ipa won't exist,
      // but the flutter build command should have been run first
      try {
        await builder.buildIpa(
          buildName: '1.2.0',
          buildNumber: 12001,
          envName: 'test',
          exportMethod: 'development',
        );
      } on StateError {
        // Expected — _findIpa fails because the directory doesn't exist
      }

      expect(
        shell.runCalls,
        contains('fvm flutter build ipa --export-method=development --build-name=1.2.0 --build-number=12001 --dart-define=ENV=test'),
      );
    });

    test('buildIpa throws StateError if IPA directory not found', () async {
      final builder = IOSBuilder(shellRunner: shell);
      await expectLater(
        () => builder.buildIpa(
          buildName: '1.0.0',
          buildNumber: 10000,
          envName: 'test',
          exportMethod: 'ad-hoc',
        ),
        throwsStateError,
      );
    });

    test('default constructor does not throw', () {
      final builder = IOSBuilder();
      expect(builder, isA<IOSBuilder>());
    });
  });
}
