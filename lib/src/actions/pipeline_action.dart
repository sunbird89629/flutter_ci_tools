import '../pipeline_context.dart';

/// A single deploy/notification step in a pipeline.
///
/// Actions receive a [PipelineContext] and store results in its
/// key-value store for downstream actions to consume.
abstract class PipelineAction {
  /// Human-readable name for logging (e.g. "Upload to Pgyer").
  String get name;

  /// Executes this action using data from [context].
  ///
  /// Results should be stored via [PipelineContext.set] for downstream actions.
  Future<void> run(PipelineContext context);
}
