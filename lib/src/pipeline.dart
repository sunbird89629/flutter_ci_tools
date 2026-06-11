import 'action_status.dart';
import 'actions/pipeline_action.dart';
import 'pipeline_context.dart';
import 'utils/logger.dart';

/// Base class for CI build pipelines.
///
/// Subclasses implement [body] to compose [PipelineAction]s; the base class
/// provides only the execution shell ([beforeBuild] → [body] → [afterBuild])
/// with try/finally semantics guaranteeing [afterBuild] runs even on failure.
abstract class Pipeline {
  /// Converts the pipeline class name to a snake_case identifier.
  ///
  /// For example:
  /// - `AndroidTestPipeline` → `android_test`
  /// - `ProdPipeline` → `prod`
  /// - `PublishIOSAction` → `publish_i_o_s_action`
  ///
  /// The logic:
  /// 1. Removes the `Pipeline` suffix (case-insensitive)
  /// 2. Converts CamelCase to snake_case
  String get name {
    final className = this.runtimeType.toString();

    // Remove Pipeline suffix
    String withoutSuffix = className;
    if (className.toLowerCase().endsWith('pipeline')) {
      withoutSuffix = className.substring(
        0,
        className.length - 'pipeline'.length,
      );
    }

    // Convert CamelCase to snake_case
    final snakeCase = withoutSuffix
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => '_${match.group(1)}')
        .toLowerCase()
        .replaceFirst('_', ''); // Remove leading underscore

    return snakeCase;
  }

  /// Short description shown in the interactive selector.
  String get description => '当前 pipeline 的说明，应包含关键信息';

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

  /// Extended help text printed when the user passes `--help`.
  String get help;

  /// Builds the [PipelineContext] for this run, receiving the raw CLI args.
  ///
  /// Implementations typically instantiate a project-specific
  /// [PipelineContext] subclass that bundles shared configuration
  /// (app name, credentials, etc.).
  PipelineContext createContext(List<String> args);

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
  Future<void> run(List<String> args) async {
    context = createContext(args);
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

  /// Runs [action] with section logging, timing, and status recording.
  /// Returns the action's typed result.
  Future<R> runAction<R>(PipelineAction<R> action) async {
    executedActions.add(action);
    return _runTracked(action);
  }

  /// Parallel executes multiple actions, returning their results in order.
  Future<List<R>> runParallelActions<R>(List<PipelineAction<R>> actions) async {
    executedActions.addAll(actions);
    return Future.wait(actions.map(_runTracked));
  }

  Future<R> _runTracked<R>(PipelineAction<R> action) async {
    Logger.section(action.name);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action.run(context);
      stopwatch.stop();
      Logger.success('Finished: ${action.name}');
      action
        ..status = ActionStatus.success
        ..duration = stopwatch.elapsed;
      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      Logger.error('Failed: ${action.name}', e);
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
      final time =
          ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
      Logger.info('$icon ${action.name} ($time)');
    }
    Logger.info(sep);
    final failure = lastFailure;
    if (failure != null) {
      Logger.error('失败: ${failure.name}', failure.error);
    }
  }
}
