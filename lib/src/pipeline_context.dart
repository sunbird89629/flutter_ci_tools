import 'build_metadata.dart';
import 'pipeline.dart' show AppPlatform;

/// Shared, mutable context passed through all pipeline steps.
///
/// Holds both static configuration (app identity, credentials) provided at
/// construction time and runtime state (metadata, build number) populated by
/// lifecycle actions during a single pipeline run.
///
/// Subclass this to bundle reusable configuration across multiple pipelines.
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    required this.platforms,
    this.pgyerApiKey,
    this.feishuWebhookUrl,
  });

  /// Display name of the application (used in notifications).
  final String appName;

  /// Starting build number used when no existing `builds/*` tag is found.
  final int seedBuildNumber;

  /// Pgyer API key for uploading builds. Required for Pgyer deploy target.
  final String? pgyerApiKey;

  /// Feishu (Lark) webhook URL for sending build notifications.
  final String? feishuWebhookUrl;

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
