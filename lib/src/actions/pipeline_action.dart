import '../action_status.dart';
import '../pipeline_context.dart';

/// A single deploy/notification step in a pipeline.
///
/// Actions receive a [PipelineContext] and produce a typed [R] result.
/// Use [R] = `void` when the action has no return value.
abstract class PipelineAction<R> {
  /// Human-readable name; used as the log section header by `BuildPipeline.runAction`.
  String get name;

  /// The execution status of this action, or `null` before it has run.
  ActionStatus? status;

  /// How long the action took to execute.
  Duration? duration;

  /// The error that caused the action to fail, if any.
  Object? error;

  /// The stack trace captured when the action failed, if any.
  StackTrace? stackTrace;

  /// Whether this action has been executed (i.e. [status] is non-null).
  bool get hasRun => status != null;

  /// Executes this action against [context] and returns its result.
  Future<R> run(PipelineContext context);
}
