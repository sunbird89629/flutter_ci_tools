import 'dart:io';

import 'package:flutter_ci_tools/flutter_ci_tools.dart';

const _placeholder = 'YOUR_VALUE_HERE';

String _env(String key) => Platform.environment[key] ?? _placeholder;

/// Project-wide [PipelineContext] subclass: bundles the configuration shared
/// by every pipeline in this example app (name, seed build number, API keys).
class ExampleAppContext extends PipelineContext {
  ExampleAppContext({required super.platforms})
      : super(
          appName: 'FlutterCIToolsExample',
          seedBuildNumber: 10000,
          pgyerApiKey: _env('PGYER_API_KEY'),
          feishuWebhookUrl: _env('FEISHU_WEBHOOK_URL'),
        );
}

class ProdCredentials {
  static String get googlePlayPackageName => _env('GOOGLE_PLAY_PACKAGE_NAME');
  static String get googlePlayJsonKeyPath => _env('GOOGLE_PLAY_JSON_KEY_PATH');
  static String get appStoreIssuerId => _env('APP_STORE_ISSUER_ID');
  static String get appStoreApiKeyId => _env('APP_STORE_API_KEY_ID');
  static String get appStoreApiKeyPath => _env('APP_STORE_API_KEY_PATH');
}
