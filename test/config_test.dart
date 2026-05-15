import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'package:test/test.dart';

void main() {
  group('CIToolsConfig', () {
    test('required fields are stored', () {
      const config = CIToolsConfig(appName: 'MyApp', seedBuildNumber: 12000);
      expect(config.appName, 'MyApp');
      expect(config.seedBuildNumber, 12000);
    });

    test('optional fields default to null', () {
      const config = CIToolsConfig(appName: 'X', seedBuildNumber: 1);
      expect(config.pgyerApiKey, isNull);
      expect(config.feishuWebhookUrl, isNull);
    });

    test('optional fields can be set', () {
      const config = CIToolsConfig(
        appName: 'X',
        seedBuildNumber: 1,
        pgyerApiKey: 'abc',
        feishuWebhookUrl: 'https://example.com',
      );
      expect(config.pgyerApiKey, 'abc');
      expect(config.feishuWebhookUrl, 'https://example.com');
    });
  });
}
