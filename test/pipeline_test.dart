// test/pipeline_test.dart
import 'dart:io';
import 'package:flutter_ci_tools/src/build_metadata.dart';
import 'package:flutter_ci_tools/src/builders/android_builder.dart';
import 'package:flutter_ci_tools/src/builders/ios_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/exceptions.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
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

class _FakeAndroidBuilder extends AndroidBuilder {
  _FakeAndroidBuilder() : super(shellRunner: _FakeShellRunner());
}

class _FakeIOSBuilder extends IOSBuilder {
  _FakeIOSBuilder() : super(shellRunner: _FakeShellRunner());

  @override
  Future<File> buildIpa({
    required String buildName,
    required int buildNumber,
    required String envName,
    required String exportMethod,
  }) async {
    await Future.value();
    return File('build/ios/ipa/app.ipa');
  }
}

class _TestPipeline extends BuildPipeline {
  _TestPipeline(
    super.config, {
    super.versionManager,
    super.gitManager,
    super.shellRunner,
    super.androidBuilder,
    super.iosBuilder,
  });

  @override
  String get name => 'test';

  @override
  String get description => 'Test pipeline';

  @override
  String get help => 'Test pipeline help';

  @override
  String get envName => 'test';

  @override
  String get iosExportMethod => 'ad-hoc';

  @override
  String get apiHost => 'https://api.test.example.com';

  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.apk;

  @override
  Future<void> deployAndroid(File file) async {}

  @override
  Future<void> deployIOS(File file) async {}
}

void main() {
  late _FakeVersionManager version;
  late _FakeGitManager git;
  late _FakeShellRunner shell;
  late CIToolsConfig config;

  _TestPipeline createPipeline() => _TestPipeline(
        config,
        versionManager: version,
        gitManager: git,
        shellRunner: shell,
        androidBuilder: _FakeAndroidBuilder(),
        iosBuilder: _FakeIOSBuilder(),
      );

  setUp(() {
    version = _FakeVersionManager();
    git = _FakeGitManager();
    shell = _FakeShellRunner();
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 12000);
  });

  group('BuildPipeline', () {
    test('buildName formats buildNumber correctly', () {
      final pipeline = createPipeline();
      pipeline.context.buildNumber = 12001;
      expect(pipeline.buildName, '1.2.0');
    });

    test('buildName handles zeros', () {
      final pipeline = createPipeline();
      pipeline.context.buildNumber = 10000;
      expect(pipeline.buildName, '1.0.0');
    });

    test('run orchestrates steps and pushes tag', () async {
      final pipeline = createPipeline();
      await pipeline.run();

      expect(pipeline.context.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('run restores workspace on failure', () async {
      git.isClean = false;
      final pipeline = createPipeline();

      try {
        await pipeline.run();
      } catch (_) {
        // Expected -- checkClean throws
      }

      expect(git.didRestore, isTrue);
    });

    test('buildFeishuMessage includes core info', () {
      final pipeline = createPipeline();
      pipeline.context.buildNumber = 12001;
      pipeline.context.metadata = BuildMetadata(
        branch: 'main',
        gitUser: 'Alice',
        gitHash: 'abc1234',
        recentCommits: 'commits',
        commitBody: '',
      );

      final msg = pipeline.buildFeishuMessage(
        platform: AppPlatform.android,
        target: DeployTarget.pgyer,
        downloadUrl: 'https://example.com',
      );

      expect(msg, contains('TestApp'));
      expect(msg, contains('12001'));
      expect(msg, contains('Android'));
      expect(msg, contains('abc1234'));
      expect(msg, contains('https://example.com'));
    });

    test('runAndroidOnly builds only Android', () async {
      final pipeline = createPipeline();
      await pipeline.runAndroidOnly();

      expect(pipeline.context.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('runIOSOnly builds only iOS', () async {
      final pipeline = createPipeline();
      await pipeline.runIOSOnly();

      expect(pipeline.context.buildNumber, 12001);
      expect(version.pushedTags, contains(12001));
    });

    test('runStep wraps with logging', () async {
      var called = false;
      await runStep('Test Step', () async {
        called = true;
        return 42;
      });
      expect(called, isTrue);
    });
  });
}
