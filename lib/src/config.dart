/// Application-level configuration for the CI pipeline.
///
/// Contains app identity, build numbering seed, and optional API credentials.
class CIToolsConfig {
  const CIToolsConfig({
    required this.appName,
    required this.seedBuildNumber,
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
}
