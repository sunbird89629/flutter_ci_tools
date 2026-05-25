import '../pipeline_context.dart';

/// A single deploy/notification step in a pipeline.
///
/// Actions receive a [PipelineContext] and produce a typed [R] result.
/// Use [R] = `void` when the action has no return value.
abstract class PipelineAction<R> {
  /// Human-readable name; used as the log section header by `BuildPipeline.runAction`.
  String get name;

  /// Executes this action against [context] and returns its result.
  Future<R> run(PipelineContext context);
}
