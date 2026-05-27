import 'action_status.dart';
import 'utils/logger.dart';
import 'pipeline_context.dart';
import 'actions/pipeline_action.dart';

/// Executes [action] with standardized section logging and error handling.
Future<T> runStep<T>(String name, Future<T> Function() action) async {
  Logger.section(name);
  try {
    final result = await action();
    Logger.success('Finished: $name');
    return result;
  } catch (e) {
    Logger.error('Failed: $name', e);
    rethrow;
  }
}

/// Base class for CI build pipelines.
///
/// Subclasses implement [body] to compose [PipelineAction]s; the base class
/// provides only the execution shell ([beforeBuild] → [body] → [afterBuild])
/// with try/finally semantics guaranteeing [afterBuild] runs even on failure.
abstract class BuildPipeline {
  /// Populated by [run]; do not access before then.
  late final PipelineContext context;

  /// Actions executed during this run, in execution order.
  final List<PipelineAction> executedActions = [];

  /// Whether all executed actions succeeded.
  bool get allSucceeded =>
      executedActions.every((a) => a.status == ActionStatus.success);

  /// The last failed action, or null if none failed.
  PipelineAction? get lastFailure {
    for (var i = executedActions.length - 1; i >= 0; i--) {
      if (executedActions[i].status == ActionStatus.failed) {
        return executedActions[i];
      }
    }
    return null;
  }

  /// Unique identifier (e.g. `"prod"`).
  String get name;

  /// Short description shown in the interactive selector.
  String get description;

  /// Extended help text printed when the user passes `--help`.
  String get help;

  /// Builds the [PipelineContext] for this run. Implementations typically
  /// instantiate a project-specific [PipelineContext] subclass that bundles
  /// shared configuration (app name, credentials, etc.).
  PipelineContext createContext();

  /// Optional preparation hook. Default no-op.
  Future<void> beforeBuild() async {}

  /// Main pipeline body. Subclasses compose actions here via [runAction].
  Future<void> body();

  /// Optional cleanup hook; always runs even if [body] throws.
  ///
  /// Errors from this hook are logged but not rethrown, so they cannot
  /// mask the original [body] failure.
  Future<void> afterBuild() async {}

  /// Entry point. Builds the [PipelineContext] via [createContext], then runs
  /// `beforeBuild → body → afterBuild`.
  Future<void> run() async {
    context = createContext();
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e) {
        Logger.error('afterBuild failed', e);
      }
      _printSummary();
    }
  }

  /// Runs [action] wrapped in [runStep], records status and timing.
  /// Returns the action's typed result.
  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await runStep(action.name, () => action.run(context));
      stopwatch.stop();
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      action
        ..status = ActionStatus.failed
        ..duration = stopwatch.elapsed
        ..error = e
        ..stackTrace = stackTrace;
      rethrow;
    }
  }

  void _printSummary() {
    if (executedActions.isEmpty) return;
    const sep = '────────────────────────────────────';
    Logger.info(sep);
    Logger.info('执行摘要');
    Logger.info(sep);
    for (final action in executedActions) {
      final status = action.status;
      final duration = action.duration;
      if (status == null || duration == null) continue;
      final icon = switch (status) {
        ActionStatus.success => '✅',
        ActionStatus.failed => '❌',
        ActionStatus.skipped => '⏭️',
        ActionStatus.interrupted => '🛑',
      };
      final ms = duration.inMilliseconds;
      final time = ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
      Logger.info('$icon ${action.name} ($time)');
    }
    Logger.info(sep);
    final failure = lastFailure;
    if (failure != null) {
      Logger.error('失败: ${failure.name}', failure.error);
    }
  }
}
