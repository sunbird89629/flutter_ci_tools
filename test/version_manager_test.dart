import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _FakeShellRunner implements ShellRunner {
  final Map<String, ShellResult> _responses = {};
  final List<String> runCalls = [];

  void stub(String executable, List<String> args, ShellResult result) {
    _responses['$executable ${args.join(' ')}'] = result;
  }

  @override
  Future<void> run(String executable, List<String> args) async {
    runCalls.add('$executable ${args.join(' ')}');
  }

  @override
  Future<ShellResult> runAndCapture(
    String executable,
    List<String> args,
  ) async {
    final key = '$executable ${args.join(' ')}';
    runCalls.add(key);
    return _responses[key] ??
        ShellResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
        );
  }
}

void main() {
  late _FakeShellRunner shell;
  late DefaultVersionManager version;

  setUp(() {
    shell = _FakeShellRunner();
    version = DefaultVersionManager(shellRunner: shell);
  });

  group('VersionManager', () {
    test('fetchLatestBuildNumber returns null when no tags exist', () async {
      shell.stub('git', ['fetch', '--tags', '--force'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));
      shell.stub('git', ['tag', '--list', 'builds/*'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));

      expect(await version.fetchLatestBuildNumber(), isNull);
    });

    test('fetchLatestBuildNumber returns max from tag list', () async {
      shell.stub('git', ['fetch', '--tags', '--force'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));
      shell.stub(
          'git',
          ['tag', '--list', 'builds/*'],
          ShellResult(
              exitCode: 0,
              stdout: 'builds/10050\nbuilds/10099\nbuilds/10001\n',
              stderr: ''));

      expect(await version.fetchLatestBuildNumber(), 10099);
    });

    test('fetchLatestBuildNumber ignores non-builds tags', () async {
      shell.stub('git', ['fetch', '--tags', '--force'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));
      shell.stub(
          'git',
          ['tag', '--list', 'builds/*'],
          ShellResult(
              exitCode: 0,
              stdout: 'v1.0.0\nbuilds/10050\nrelease\n',
              stderr: ''));

      expect(await version.fetchLatestBuildNumber(), 10050);
    });

    test('computeNextBuildNumber returns seed when no tags', () async {
      shell.stub('git', ['fetch', '--tags', '--force'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));
      shell.stub('git', ['tag', '--list', 'builds/*'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));

      expect(await version.computeNextBuildNumber(12000), 12000);
    });

    test('computeNextBuildNumber returns max + 1', () async {
      shell.stub('git', ['fetch', '--tags', '--force'],
          ShellResult(exitCode: 0, stdout: '', stderr: ''));
      shell.stub(
          'git',
          ['tag', '--list', 'builds/*'],
          ShellResult(
              exitCode: 0, stdout: 'builds/10050\nbuilds/10099\n', stderr: ''));

      expect(await version.computeNextBuildNumber(12000), 10100);
    });

    test('pushNewBuildTag creates and force-pushes tag', () async {
      await version.pushNewBuildTag(10100);

      expect(
        shell.runCalls,
        containsAll([
          'git tag -a -f builds/10100 -m CI build 10100',
          'git push --force origin builds/10100',
        ]),
      );
    });
  });
}
