import 'dart:io';
import 'package:flutter_ci_tools/src/builders/android_builder.dart';
import 'package:flutter_ci_tools/src/builders/ios_builder.dart';
import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/git_manager.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_registry.dart';
import 'package:flutter_ci_tools/src/shell_runner.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  @override
  Future<int?> fetchLatestBuildNumber() async => null;
  @override
  Future<int> computeNextBuildNumber(int seed) async => 10001;
  @override
  Future<void> pushNewBuildTag(int buildNumber) async {}
  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

class _FakeGitManager implements GitManager {
  @override
  Future<void> checkClean() async {}
  @override
  Future<void> restoreWorkspace() async {}
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
  @override
  Future<void> run(String exe, List<String> args) async {}
  @override
  Future<ShellResult> runAndCapture(String exe, List<String> args) async =>
      ShellResult(exitCode: 0, stdout: '', stderr: '');
}

class _FakeAndroidBuilder extends AndroidBuilder {
  _FakeAndroidBuilder() : super(shellRunner: _FakeShellRunner());
}

class _FakeIOSBuilder extends IOSBuilder {
  _FakeIOSBuilder() : super(shellRunner: _FakeShellRunner());
}

class _StubPipeline extends BuildPipeline {
  final String _name;
  final String _description;
  final String _help;
  bool didRun = false;
  bool didRunAndroid = false;
  bool didRunIOS = false;

  _StubPipeline(
    this._name,
    this._description,
    this._help,
    CIToolsConfig config, {
    super.versionManager,
    super.gitManager,
    super.shellRunner,
    super.androidBuilder,
    super.iosBuilder,
  }) : super(config);

  @override
  String get name => _name;
  @override
  String get description => _description;
  @override
  String get help => _help;
  @override
  String get envName => _name;
  @override
  String get iosExportMethod => 'development';
  @override
  String get apiHost => 'https://api.test.com';
  @override
  AndroidBuildType get androidBuildType => AndroidBuildType.apk;
  @override
  Future<void> deployAndroid(File file) async {}
  @override
  Future<void> deployIOS(File file) async {}

  @override
  Future<void> run() async {
    didRun = true;
  }

  @override
  Future<void> runAndroidOnly() async {
    didRunAndroid = true;
  }

  @override
  Future<void> runIOSOnly() async {
    didRunIOS = true;
  }
}

void main() {
  late CIToolsConfig config;
  late _FakeVersionManager version;
  late _FakeGitManager git;
  late _FakeShellRunner shell;

  _StubPipeline createPipeline(String name,
      {String? description, String? help}) {
    return _StubPipeline(
      name,
      description ?? '$name description',
      help ?? '$name help',
      config,
      versionManager: version,
      gitManager: git,
      shellRunner: shell,
      androidBuilder: _FakeAndroidBuilder(),
      iosBuilder: _FakeIOSBuilder(),
    );
  }

  setUp(() {
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 10000);
    version = _FakeVersionManager();
    git = _FakeGitManager();
    shell = _FakeShellRunner();
  });

  group('PipelineRegistry', () {
    test('register adds a pipeline', () {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);
      expect(registry.pipelines, contains(pipeline));
    });

    test('register throws on duplicate name', () {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));
      expect(
        () => registry.register(createPipeline('test')),
        throwsArgumentError,
      );
    });

    test('run dispatches to pipeline.run() for known name', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test']);
      expect(pipeline.didRun, isTrue);
    });

    test('run dispatches to pipeline.runAndroidOnly() for android arg',
        () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'android']);
      expect(pipeline.didRunAndroid, isTrue);
    });

    test('run dispatches to pipeline.runIOSOnly() for ios arg', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'ios']);
      expect(pipeline.didRunIOS, isTrue);
    });

    test('pipelines getter returns registered pipelines in order', () {
      final registry = PipelineRegistry();
      final p1 = createPipeline('a');
      final p2 = createPipeline('b');
      registry
        ..register(p1)
        ..register(p2);

      expect(registry.pipelines, [p1, p2]);
    });

    test('run shows interactive prompt and selects pipeline by number',
        () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run([], readLine: () => '1');
      expect(pipeline.didRun, isTrue);
    });

    test('run interactive exits on 0', () async {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));

      var exitCode = -1;
      await registry.run([], readLine: () => '0',
          onExit: (code) => exitCode = code);
      expect(exitCode, 0);
    });

    test('run interactive re-prompts on invalid input', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      var callCount = 0;
      await registry.run([], readLine: () {
        callCount++;
        if (callCount == 1) return 'invalid';
        return '1';
      });
      expect(pipeline.didRun, isTrue);
      expect(callCount, 2);
    });

    test('run interactive re-prompts on out-of-range number', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      var callCount = 0;
      await registry.run([], readLine: () {
        callCount++;
        if (callCount == 1) return '99';
        return '1';
      });
      expect(pipeline.didRun, isTrue);
      expect(callCount, 2);
    });
  });
}
