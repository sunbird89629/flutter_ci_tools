import 'logger.dart';
import 'pipeline_context.dart';
import 'actions/pipeline_action.dart';

/// Target platform for a build run.
enum AppPlatform {
  android('Android'),
  ios('iOS');

  final String label;
  const AppPlatform(this.label);
}

/// Executes [action] with standardized section logging and error handling.
Future<T> runStep<T>(String name, Future<T> Function() action) async {
  final startTime = DateTime.now();
  Logger.section(name);
  try {
    final result = await action();
    final duration = DateTime.now().difference(startTime);
    Logger.success('Finished: $name (${duration.inSeconds}s)');
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

  /// Unique identifier (e.g. `"prod"`).
  String get name;

  /// Short description shown in the interactive selector.
  String get description;

  /// Extended help text printed when the user passes `--help`.
  String get help;

  /// Builds the [PipelineContext] for this run. Implementations typically
  /// instantiate a project-specific [PipelineContext] subclass that bundles
  /// shared configuration (app name, credentials, etc.).
  PipelineContext createContext(Set<AppPlatform> platforms);

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
  Future<void> run(Set<AppPlatform> platforms) async {
    context = createContext(platforms);
    try {
      await beforeBuild();
      await body();
    } finally {
      try {
        await afterBuild();
      } catch (e) {
        Logger.error('afterBuild failed', e);
      }
    }
  }

  /// Runs [action] wrapped in [runStep] using [PipelineAction.name] as the
  /// log section header. Returns the action's typed result.
  Future<R> runAction<R>(PipelineAction<R> action) =>
      runStep(action.name, () => action.run(context));
}
