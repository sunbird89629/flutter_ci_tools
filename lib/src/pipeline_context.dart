import 'build_metadata.dart';
import 'config.dart';

/// Shared context passed through all pipeline steps.
///
/// Holds immutable configuration, mutable build state, and a generic
/// key-value store for inter-step data passing.
class PipelineContext {
  /// Creates a context with the given [config].
  PipelineContext({required this.config});

  /// Application-level configuration (name, API keys, seed build number).
  final CIToolsConfig config;

  /// Git and build metadata collected at the start of the pipeline run.
  late BuildMetadata metadata;

  /// The resolved build number, set during pipeline execution.
  late int buildNumber;

  /// The human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  final Map<String, dynamic> _store = {};

  /// Stores [value] under [key]. Overwrites if key already exists.
  void set<T>(String key, T value) => _store[key] = value;

  /// Retrieves value by [key], cast to [T].
  ///
  /// Throws if the key does not exist or the value is not of type [T].
  T get<T>(String key) => _store[key] as T;

  /// Retrieves value by [key], cast to [T]. Returns null if missing.
  T? tryGet<T>(String key) => _store[key] as T?;

  /// Whether [key] exists in the store.
  bool has(String key) => _store.containsKey(key);

  /// Removes [key] from the store. Returns the removed value, or null.
  T? remove<T>(String key) => _store.remove(key) as T?;
}
