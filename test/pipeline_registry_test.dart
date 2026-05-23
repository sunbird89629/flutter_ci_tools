import 'package:flutter_ci_tools/src/config.dart';
import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_registry.dart';
import 'package:test/test.dart';

class _StubPipeline extends BuildPipeline {
  _StubPipeline(this._name, this._description, this._help, CIToolsConfig config)
      : super(config);

  final String _name;
  final String _description;
  final String _help;
  Set<AppPlatform>? receivedPlatforms;

  @override String get name => _name;
  @override String get description => _description;
  @override String get help => _help;

  @override
  Future<void> body() async {
    receivedPlatforms = context.platforms;
  }
}

void main() {
  late CIToolsConfig config;

  _StubPipeline createPipeline(String name,
      {String? description, String? help}) {
    return _StubPipeline(
      name,
      description ?? '$name description',
      help ?? '$name help',
      config,
    );
  }

  setUp(() {
    config = const CIToolsConfig(appName: 'TestApp', seedBuildNumber: 10000);
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

    test('run dispatches with all platforms when no platform arg', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test']);
      expect(pipeline.receivedPlatforms, AppPlatform.values.toSet());
    });

    test('run dispatches with android-only set for "android" arg', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'android']);
      expect(pipeline.receivedPlatforms, {AppPlatform.android});
    });

    test('run dispatches with ios-only set for "ios" arg', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test', 'ios']);
      expect(pipeline.receivedPlatforms, {AppPlatform.ios});
    });

    test('run exits 64 and prints "Unknown platform" for invalid platform arg',
        () async {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));

      var exitCode = -1;
      await registry.run(['test', 'web'], onExit: (code) => exitCode = code);
      expect(exitCode, 64);
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

    test('run interactive selects pipeline by number with all platforms',
        () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run([], readLine: () => '1');
      expect(pipeline.receivedPlatforms, AppPlatform.values.toSet());
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
      expect(pipeline.receivedPlatforms, isNotNull);
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
      expect(pipeline.receivedPlatforms, isNotNull);
      expect(callCount, 2);
    });
  });
}
