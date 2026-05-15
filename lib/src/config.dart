class CIToolsConfig {
  const CIToolsConfig({
    required this.appName,
    required this.seedBuildNumber,
    this.pgyerApiKey,
    this.feishuWebhookUrl,
  });

  final String appName;
  final int seedBuildNumber;
  final String? pgyerApiKey;
  final String? feishuWebhookUrl;
}
