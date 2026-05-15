import 'dart:io';

import 'build_metadata.dart';
import 'config.dart';
import 'deploy_service.dart';
import 'git_manager.dart';
import 'logger.dart';
import 'shell_runner.dart' show ShellRunner;
import 'version_manager.dart';

enum AppPlatform {
  android('Android'),
  ios('iOS');

  final String label;
  const AppPlatform(this.label);
}

enum DeployTarget {
  pgyer('Pgyer'),
  googlePlay('Google Play'),
  appStore('App Store');

  final String label;
  const DeployTarget(this.label);
}

/// Executes a step with standardized logging and error handling.
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

abstract class EnvBuilder {
  EnvBuilder(this.config);

  final CIToolsConfig config;

  late int buildNumber;

  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  late final BuildMetadata metadata;

  String get envName;
  String get iosExportMethod;
  bool get shouldSwapInfoPlist => false;
  String get apiHost;

  Future<File> buildAndroid();
  Future<void> processArtifacts(File androidFile, File iosFile);

  Future<File> buildIOS() async {
    await ShellRunner.instance.run('fvm', [
      'flutter',
      'build',
      'ipa',
      '--export-method=$iosExportMethod',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      '--dart-define=ENV=$envName',
    ]);
    return findIpaFile();
  }

  Future<void> uploadAndNotify(AppPlatform platform, File file) async {
    Logger.info('Processing ${platform.label}...');
    final description = [
      ..._coreInfoLines(),
      '',
      'recent commits:',
      metadata.recentCommits,
    ].join('\n');

    final url = await DeployService.instance.uploadToPgyer(
      file.path,
      config.pgyerApiKey!,
      updateDescription: description,
    );

    await DeployService.instance.sendFeishuNotification(
      config.feishuWebhookUrl!,
      buildFeishuMessage(
        platform: platform,
        target: DeployTarget.pgyer,
        downloadUrl: url,
      ),
    );
  }

  List<String> _coreInfoLines() => [
    'versionName: $buildName',
    'versionCode: $buildNumber',
    'env:         $envName',
    'api_host:    $apiHost',
    'git_hash:    ${metadata.gitHash}',
  ];

  String buildFeishuMessage({
    required AppPlatform platform,
    required DeployTarget target,
    String? downloadUrl,
  }) {
    const sep = '──────────────────────────';
    final lines = <String>[
      '🚀 ${config.appName} 新版本 $buildNumber (${platform.label} · ${target.label})',
      'branch: ${metadata.branch}  by: ${metadata.gitUser}',
      sep,
      ..._coreInfoLines(),
    ];
    if (downloadUrl != null) {
      lines
        ..add(sep)
        ..add('🔗 下载: $downloadUrl');
    }
    lines
      ..add(sep)
      ..add('最近提交:')
      ..add(metadata.recentCommits);
    if (metadata.commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(metadata.commitBody);
    }
    return lines.join('\n');
  }

  Future<void> cleanProject() async {
    await ShellRunner.instance.run('fvm', ['flutter', 'clean']);
    await ShellRunner.instance.run('fvm', ['flutter', 'pub', 'get']);
  }

  Future<void> buildPrepare() async {
    if (shouldSwapInfoPlist) {
      Logger.info('Swapping Info.plist for product environment');
      File('ios/Runner/Info.plist').renameSync('ios/Runner/Info.plist.backup');
      File('ios/Runner/Info.plist.product').renameSync('ios/Runner/Info.plist');
    }
  }

  File findIpaFile() {
    final ipaDir = Directory('build/ios/ipa');
    if (!ipaDir.existsSync()) {
      throw 'IPA build failed: Directory not found at ${ipaDir.path}';
    }
    final ipaList = ipaDir
        .listSync()
        .where((e) => e.path.endsWith('.ipa'))
        .toList();
    if (ipaList.isEmpty) {
      throw 'IPA build failed: No .ipa file found in ${ipaDir.path}';
    }
    return ipaList.first as File;
  }

  Future<void> run() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await VersionManager.instance.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep('Collect Build Metadata', BuildMetadata.collect);
    try {
      await runStep('Check Git Status', GitManager.instance.checkClean);
      await buildPrepare();
      Logger.section('Starting Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final androidFile = await runStep('Build Android', buildAndroid);
      final iosFile = await runStep('Build iOS', buildIOS);
      await runStep(
        'Process Artifacts',
        () => processArtifacts(androidFile, iosFile),
      );
      await runStep(
        'Push Build Tag',
        () => VersionManager.instance.pushNewBuildTag(buildNumber),
      );
    } finally {
      await GitManager.instance.restoreWorkspace();
    }
  }
}
