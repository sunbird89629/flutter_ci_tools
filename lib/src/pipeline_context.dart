import 'build_metadata.dart';
import 'config.dart';
import 'pipeline.dart' show AppPlatform;

/// Shared, read-only context passed through all pipeline steps.
///
/// Holds the config and the platform filter (set at pipeline launch), plus
/// build-time fields populated by lifecycle actions.
class PipelineContext {
  PipelineContext({required this.config, required this.platforms});

  /// Application-level configuration (name, API keys, seed build number).
  final CIToolsConfig config;

  /// Platforms this pipeline run targets.
  final Set<AppPlatform> platforms;

  /// Git and build metadata, populated by `CollectMetadataAction`.
  late BuildMetadata metadata;

  /// Resolved build number, populated by `ResolveBuildVersionAction`.
  late int buildNumber;

  /// Human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }
}
