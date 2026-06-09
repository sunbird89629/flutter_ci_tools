import 'package:flutter_ci_tools/src/pipeline.dart';
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/pipeline_registry.dart';
import 'package:test/test.dart';

class _StubPipeline extends Pipeline {
  _StubPipeline(this._name, this._description, this._help);

  final String _name;
  final String _description;
  final String _help;
  bool wasRun = false;

  @override
  String get name => _name;
  @override
  String get description => _description;
  @override
  String get help => _help;

  List<String>? receivedArgs;

  @override
  PipelineContext createContext(List<String> args) {
    receivedArgs = args;
    return PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 10000,
      rawArgs: args,
    );
  }

  @override
  Future<void> body() async {
    wasRun = true;
  }
}

void main() {
  _StubPipeline createPipeline(String name,
      {String? description, String? help}) {
    return _StubPipeline(
      name,
      description ?? '$name description',
      help ?? '$name help',
    );
  }

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

    test('run dispatches to pipeline', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run(['test']);
      expect(pipeline.wasRun, isTrue);
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

    test('run interactive selects pipeline by number', () async {
      final registry = PipelineRegistry();
      final pipeline = createPipeline('test');
      registry.register(pipeline);

      await registry.run([], readLine: () => '1');
      expect(pipeline.wasRun, isTrue);
    });

    test('run interactive exits on 0', () async {
      final registry = PipelineRegistry();
      registry.register(createPipeline('test'));

      var exitCode = -1;
      await registry
          .run([], readLine: () => '0', onExit: (code) => exitCode = code);
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
      expect(pipeline.wasRun, isTrue);
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
      expect(pipeline.wasRun, isTrue);
      expect(callCount, 2);
    });
  });
}
