import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _FakeGitManager implements GitManager {
  String branch = 'main';
  String gitUser = 'Alice';
  String gitHash = 'abc1234';
  String recentCommits = 'commit 1\ncommit 2';
  String commitBody = 'Fix login bug';

  @override
  Future<String> getBranch() async => branch;
  @override
  Future<String> getCurrentUser() async => gitUser;
  @override
  Future<String> getShortHash() async => gitHash;
  @override
  Future<String> getRecentCommits({int count = 10}) async => recentCommits;
  @override
  Future<String> getLatestCommitBody() async => commitBody;
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> resetHard() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<void> restoreWorkspace() async {}
}

void main() {
  late _FakeGitManager git;

  setUp(() {
    git = _FakeGitManager();
  });

  group('BuildMetadata.collect', () {
    test('returns metadata with correct branch', () async {
      git.branch = 'feature/login';
      final meta = await BuildMetadata.collect(git);
      expect(meta.branch, 'feature/login');
    });

    test('returns metadata with correct gitUser', () async {
      git.gitUser = 'Bob';
      final meta = await BuildMetadata.collect(git);
      expect(meta.gitUser, 'Bob');
    });

    test('returns metadata with correct gitHash', () async {
      git.gitHash = 'def5678';
      final meta = await BuildMetadata.collect(git);
      expect(meta.gitHash, 'def5678');
    });

    test('returns metadata with correct recentCommits', () async {
      git.recentCommits = 'fix: bug\nfeat: feature';
      final meta = await BuildMetadata.collect(git);
      expect(meta.recentCommits, 'fix: bug\nfeat: feature');
    });

    test('returns metadata with correct commitBody', () async {
      git.commitBody = 'Detailed description';
      final meta = await BuildMetadata.collect(git);
      expect(meta.commitBody, 'Detailed description');
    });
  });
}
