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
    return _responses[key] ?? ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  late _FakeShellRunner shell;
  late GitManagerImpl git;

  setUp(() {
    shell = _FakeShellRunner();
    git = GitManagerImpl(shellRunner: shell);
  });

  group('GitManager', () {
    test('getShortHash returns trimmed stdout', () async {
      shell.stub(
        'git',
        ['rev-parse', '--short', 'HEAD'],
        ShellResult(exitCode: 0, stdout: 'abc1234\n', stderr: ''),
      );
      expect(await git.getShortHash(), 'abc1234');
    });

    test('getBranch returns trimmed stdout', () async {
      shell.stub(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        ShellResult(exitCode: 0, stdout: 'main\n', stderr: ''),
      );
      expect(await git.getBranch(), 'main');
    });

    test('getRecentCommits returns trimmed stdout', () async {
      shell.stub(
        'git',
        ['log', '--oneline', '--no-merges', '-n', '10'],
        ShellResult(
            exitCode: 0, stdout: 'abc commit 1\ndef commit 2\n', stderr: ''),
      );
      expect(await git.getRecentCommits(), 'abc commit 1\ndef commit 2');
    });

    test('getCurrentUser returns git config user name', () async {
      shell.stub(
        'git',
        ['config', '--get', 'user.name'],
        ShellResult(exitCode: 0, stdout: 'Alice\n', stderr: ''),
      );
      expect(await git.getCurrentUser(), 'Alice');
    });

    test('getCurrentUser falls back when git name empty', () async {
      shell.stub(
        'git',
        ['config', '--get', 'user.name'],
        ShellResult(exitCode: 0, stdout: '', stderr: ''),
      );
      final result = await git.getCurrentUser();
      expect(result, isNotEmpty);
    });

    test('getLatestCommitBody returns trimmed commit body', () async {
      shell.stub(
        'git',
        ['log', '-1', '--pretty=%b'],
        ShellResult(exitCode: 0, stdout: 'Fix login bug\n', stderr: ''),
      );
      expect(await git.getLatestCommitBody(), 'Fix login bug');
    });

    test('throws GitException on non-zero exit', () async {
      shell.stub(
        'git',
        ['rev-parse', '--short', 'HEAD'],
        ShellResult(exitCode: 128, stdout: '', stderr: 'fatal: not a git repo'),
      );
      expect(
        () => git.getShortHash(),
        throwsA(isA<GitException>()),
      );
    });

    test('restoreWorkspace resets and cleans', () async {
      await git.restoreWorkspace();
      expect(shell.runCalls, contains('git reset HEAD --hard'));
      expect(shell.runCalls, contains('git clean -fd'));
    });
  });
}
