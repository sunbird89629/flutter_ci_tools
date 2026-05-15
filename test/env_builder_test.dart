import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  int? latestTag;
  int nextBuildNumber = 12001;
  List<int> pushedTags = [];

  @override
  Future<int?> fetchLatestBuildNumber() async => latestTag;

  @override
  Future<int> computeNextBuildNumber(int seed) async => nextBuildNumber;

  @override
  Future<void> pushNewBuildTag(int buildNumber) async {
    pushedTags.add(buildNumber);
  }

  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

class _FakeGitManager implements GitManager {
  bool isClean = true;
  bool didRestore = false;

  @override
  Future<void> checkClean() async {
    if (!isClean) throw GitException('dirty', 1);
  }

  @override
  Future<void> restoreWorkspace() async {
    didRestore = true;
  }

  @override
  Future<void> resetHard() async {}

  @override
  Future<void> clean() async {}

  @override
  Future<String> getShortHash() async => 'abc1234';

  @override
  Future<String> getRecentCommits({int count = 10}) async => 'commits';

  @override
  Future<String> getBranch() async => 'main';

  @override
  Future<String> getCurrentUser() async => 'Alice';

  @override
  Future<String> getLatestCommitBody() async => '';
}

class _FakeDeployService implements DeployService {
  @override
  Future<String> uploadToPgyer(String fp, String key,
      {String? updateDescription}) async => 'https://pgyer.com/test';

  @override
  Future<void> sendFeishuNotification(String url, String text) async {}

  @override
  Future<void> uploadToGooglePlay(File aab,
      {required String packageName,
      required String jsonKeyPath}) async {}

  @override
  Future<void> uploadToAppStore(File ipa,
      {required String issuerId,
      required String apiKeyId,
      required String apiKeyPath}) async {}
}

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

class _TestEnvBuilder extends EnvBuilder {
  _TestEnvBuilder(
    super.config, {
    super.versionManager,
    super.gitManager,
    super.deployService,
    super.shellRunner,
  });

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'ad-hoc';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  Future<File> buildAndroid() async => File('test.apk');

  @override
  Future<File> buildIOS() async => File('test.ipa');

  @override
  Future<void> processArtifacts(File androidFile, File iosFile) async {}
}

void main() {
  late _FakeVersionManager version;
  late _FakeGitManager git;
  late _FakeDeployService deploy;
  late _FakeShellRunner shell;
  late CIToolsConfig config;

  _TestEnvBuilder createBuilder() => _TestEnvBuilder(
        config,
        versionManager: version,
        gitManager: git,
        deployService: deploy,
        shellRunner: shell,
      );

  setUp(() {
    version = _FakeVersionManager();
    git = _FakeGitManager();
    deploy = _FakeDeployService();
    shell = _FakeShellRunner();
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000);
  });

  group('EnvBuilder', () {
    test('buildName formats buildNumber correctly', () {
      final builder = createBuilder();
      builder.buildNumber = 12001;
      expect(builder.buildName, '1.2.0');
    });

    test('buildName handles zeros', () {
      final builder = createBuilder();
      builder.buildNumber = 10000;
      expect(builder.buildName, '1.0.0');
    });

    test('run orchestrates steps and pushes tag', () async {
      final builder = createBuilder();
      await builder.run();

      expect(builder.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('run restores workspace on failure', () async {
      git.isClean = false;
      final builder = createBuilder();

      try {
        await builder.run();
      } catch (_) {
        // Expected -- checkClean throws
      }

      expect(git.didRestore, isTrue);
    });
  });
}
