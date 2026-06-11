import '../action_status.dart';
import '../pipeline_context.dart';

/// A single deploy/notification step in a pipeline.
///
/// Actions receive a [PipelineContext] and produce a typed [R] result.
/// Use [R] = `void` when the action has no return value.
abstract class PipelineAction<R> {
  /// Human-readable name; used as the log section header by `Pipeline.runAction`.
  String get name => this.runtimeType.toString();

  /// Optional description shown alongside [name] in pipeline summaries.
  ///
  /// Defaults to the class name converted from CamelCase to a space-separated
  /// sentence (e.g. `BuildAndroidAction` → `"build android action"`).
  /// Override to provide a more human-friendly description.
  String get description {
    final className = runtimeType.toString();
    return className
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .toLowerCase()
        .trim();
  }

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
