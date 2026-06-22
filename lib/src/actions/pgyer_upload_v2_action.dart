import 'dart:convert';
import 'dart:io';

import '../context_keys.dart';
import '../utils/shell_runner_impl.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../pipeline_context.dart';
import '../utils/shell_runner.dart';
import 'pipeline_action.dart';

/// Pgyer's official 3-step "fastUploadApp" upload protocol.
///
/// In contrast to [PgyerUploadAction] (the legacy single-shot endpoint),
/// this action:
/// 1. Probes a list of API domains and picks the first reachable one
///    (resilient to regional DNS / firewall issues in mainland China).
/// 2. Requests a Tencent COS upload token from Pgyer.
/// 3. Uploads the artifact directly to COS (bypassing Pgyer's own servers
///    — much faster for large files).
/// 4. Polls `buildInfo` until processing completes and stores the build's
///    public download URL in the context bag under [resultKey].
///
/// The artifact file is read from the explicit [artifact] parameter if
/// provided, otherwise from `ContextKeys.buildArtifact` in the context bag.
class PgyerUploadV2Action extends PipelineAction {
  /// Creates a Pgyer V2 upload action.
  ///
  /// [apiKey] is the Pgyer API key for authentication.
  /// [buildUpdateDescription] is an optional build description shown on Pgyer.
  /// [artifact] optionally specifies the file to upload; if null, reads
  /// `ContextKeys.buildArtifact` from the context bag.
  /// [resultKey] is the context key under which the download URL is stored.
  /// Defaults to [ContextKeys.pgyerDownloadUrl]; override when uploading
  /// multiple artifacts in parallel so each URL lands under a distinct key.
  /// [maxRetries] is the maximum number of upload attempts (default: 5).
  /// [apiDomains] overrides the default list of API hosts to probe.
  /// [probeDomain] overrides the default domain reachability check for testing.
  /// [shellRunner] overrides the default [ShellRunner] for testing.
  PgyerUploadV2Action({
    required this.apiKey,
    this.buildUpdateDescription,
    this.artifact,
    this.resultKey = ContextKeys.pgyerDownloadUrl,
    this.maxRetries = 5,
    List<String>? apiDomains,
    Future<bool> Function(String domain)? probeDomain,
    ShellRunner? shellRunner,
  })  : apiDomains = apiDomains ?? _defaultApiDomains,
        _probeDomain = probeDomain ?? _defaultProbeDomain,
        _shellRunner = shellRunner ?? ShellRunnerImpl();

  /// Pgyer API key for authentication.
  final String apiKey;

  /// Optional build update description shown on the Pgyer download page.
  final String? buildUpdateDescription;

  /// Explicit file to upload; falls back to `ContextKeys.buildArtifact`
  /// from the context bag when `null`.
  final File? artifact;

  /// Context key under which the download URL is stored. Defaults to
  /// [ContextKeys.pgyerDownloadUrl]; override when uploading multiple
  /// artifacts in parallel so each URL lands under a distinct key.
  final String resultKey;

  /// Maximum number of upload attempts before throwing.
  final int maxRetries;

  /// Ordered list of API hosts to probe. First reachable one is used.
  final List<String> apiDomains;

  final Future<bool> Function(String domain) _probeDomain;
  final ShellRunner _shellRunner;

  @override
  String get name => 'Upload to Pgyer (V2)';

  @override
  Future<void> run(PipelineContext context) async {
    _shellRunner.setLogger(context.logger);
    final log = context.logger;
    final file = artifact ?? context.get<File>(ContextKeys.buildArtifact);
    final domain = await _selectReachableDomain(log);
    final apiBaseUrl = 'http://$domain/apiv2';
    final webDomain = domain.startsWith('api.') ? domain.substring(4) : domain;

    _CosToken? token;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      if (attempt > 1) {
        log.info(
          'Retrying Pgyer upload (attempt $attempt/$maxRetries)...',
        );
        await Future.delayed(const Duration(seconds: 10));
      }
      try {
        token = await _getCOSToken(apiBaseUrl, file, log);
        await _uploadToCOS(token, file, log);
        break;
      } catch (e) {
        log.error('Pgyer upload attempt $attempt failed: $e');
        if (attempt == maxRetries) rethrow;
        token = null;
      }
    }
    if (token == null) {
      throw DeployException(
        'Pgyer upload failed after $maxRetries attempts',
      );
    }
    final shortcutUrl = await _pollBuildInfo(apiBaseUrl, token.key, log);
    final downloadUrl = 'https://$webDomain/$shortcutUrl';
    log.success('Pgyer build ready: $downloadUrl');
    context.put(resultKey, downloadUrl);
  }

  Future<String> _selectReachableDomain(Logger log) async {
    log.info('Probing Pgyer API domains...');
    for (final domain in apiDomains) {
      if (await _probeDomain(domain)) {
        log.info('Using domain $domain');
        return domain;
      }
    }
    throw DeployException(
      'All Pgyer API domains unreachable: ${apiDomains.join(", ")}',
    );
  }

  /// Default probe: HTTPS GET against `/apiv2/app/getCOSToken` with a
  /// 5-second connect timeout and 10-second overall timeout. Any HTTP
  /// response (even an error code) counts as reachable; network/timeout
  /// errors count as unreachable.
  static Future<bool> _defaultProbeDomain(String domain) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .getUrl(Uri.parse('https://$domain/apiv2/app/getCOSToken'))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<_CosToken> _getCOSToken(
      String apiBaseUrl, File artifact, Logger log) async {
    log.info('Requesting COS upload token...');
    final buildType = artifact.path.split('.').last;
    final result = await _shellRunner.runAndCapture('curl', [
      '-s',
      '--form-string',
      '_api_key=$apiKey',
      '--form-string',
      'buildType=$buildType',
      if (buildUpdateDescription != null) ...[
        '--form-string',
        'buildUpdateDescription=$buildUpdateDescription',
      ],
      '$apiBaseUrl/app/getCOSToken',
    ]);
    if (result.exitCode != 0) {
      throw DeployException('getCOSToken curl failed: ${result.stderr}');
    }
    final dynamic response;
    try {
      response = jsonDecode(result.stdout);
    } catch (_) {
      throw DeployException('getCOSToken returned non-JSON: ${result.stdout}');
    }
    if (response['code'] != 0) {
      throw DeployException(
        'getCOSToken failed: ${response['message'] ?? response}',
      );
    }
    final data = response['data'] as Map<String, dynamic>?;
    // Pgyer API 响应结构可能有两种形式：
    // 1. 直接在 data 下（旧格式）
    // 2. signature/securityToken 嵌套在 data.params 下（新格式）
    final params = data?['params'] as Map<String, dynamic>?;
    final endpoint = data?['endpoint'] as String?;
    final key = data?['key'] as String?;
    final signature =
        (params?['signature'] ?? data?['signature']) as String?;
    final securityToken =
        (params?['x-cos-security-token'] ?? data?['x-cos-security-token'])
            as String?;
    if (endpoint == null ||
        key == null ||
        signature == null ||
        securityToken == null) {
      throw DeployException(
        'getCOSToken response missing required fields: ${result.stdout}',
      );
    }
    return _CosToken(
      endpoint: endpoint,
      key: key,
      signature: signature,
      securityToken: securityToken,
    );
  }

  Future<void> _uploadToCOS(_CosToken token, File artifact, Logger log) async {
    final fileName = artifact.path.split('/').last;
    final size = artifact.lengthSync();
    log.info('Uploading $fileName ($size bytes) to COS...');
    final result = await _shellRunner.runAndCapture('curl', [
      '-o',
      '/dev/null',
      '-w',
      '%{http_code}',
      '-s',
      '--connect-timeout',
      '30',
      '--max-time',
      '1800',
      '--form-string',
      'key=${token.key}',
      '--form-string',
      'signature=${token.signature}',
      '--form-string',
      'x-cos-security-token=${token.securityToken}',
      '--form-string',
      'x-cos-meta-file-name=$fileName',
      '-F',
      'file=@${artifact.path}',
      token.endpoint,
    ]);
    if (result.exitCode != 0) {
      throw DeployException('COS upload curl failed: ${result.stderr}');
    }
    final httpCode = result.stdout.trim();
    if (httpCode != '204') {
      throw DeployException(
          'COS upload returned HTTP $httpCode (expected 204)');
    }
    log.success('Uploaded to COS.');
  }

  Future<String> _pollBuildInfo(
      String apiBaseUrl, String key, Logger log) async {
    log.info('Waiting for Pgyer to process the build...');
    const maxAttempts = 60;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = await _shellRunner.runAndCapture('curl', [
        '-s',
        '$apiBaseUrl/app/buildInfo?_api_key=$apiKey&buildKey=$key',
      ]);
      if (result.exitCode == 0) {
        try {
          final response = jsonDecode(result.stdout);
          if (response['code'] == 0) {
            final data = response['data'] as Map<String, dynamic>?;
            final shortcutUrl = data?['buildShortcutUrl'] as String?;
            if (shortcutUrl == null) {
              throw DeployException(
                'buildInfo missing buildShortcutUrl: ${result.stdout}',
              );
            }
            return shortcutUrl;
          }
        } catch (e) {
          if (e is DeployException) rethrow;
          // Treat JSON parse failures as transient and keep polling.
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    throw DeployException(
        'Pgyer build processing timed out after ${maxAttempts}s');
  }
}

const _defaultApiDomains = [
  'api.pgyer.com',
  'api.xcxwo.com',
  'api.pgyeraapp.com',
];

class _CosToken {
  _CosToken({
    required this.endpoint,
    required this.key,
    required this.signature,
    required this.securityToken,
  });

  final String endpoint;
  final String key;
  final String signature;
  final String securityToken;
}
