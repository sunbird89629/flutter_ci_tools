// lib/src/pipeline.dart
import 'dart:io';

import 'build_metadata.dart';
import 'builders/android_builder.dart';
import 'builders/ios_builder.dart';
import 'config.dart';
import 'deploy_service.dart';
import 'git_manager.dart';
import 'logger.dart';
import 'shell_runner.dart';
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

enum AndroidBuildType { apk, appbundle }

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

abstract class BuildPipeline {
  BuildPipeline(
    this.config, {
    VersionManager? versionManager,
    GitManager? gitManager,
    DeployService? deployService,
    ShellRunner? shellRunner,
    AndroidBuilder? androidBuilder,
    IOSBuilder? iosBuilder,
  })  : _versionManager = versionManager ?? DefaultVersionManager(),
        _gitManager = gitManager ?? DefaultGitManager(),
        _deployService = deployService ?? DefaultDeployService(),
        _shellRunner = shellRunner ?? DefaultShellRunner(),
        _androidBuilder = androidBuilder ?? AndroidBuilder(),
        _iosBuilder = iosBuilder ?? IOSBuilder();

  final CIToolsConfig config;
  final VersionManager _versionManager;
  final GitManager _gitManager;
  final DeployService _deployService;
  final ShellRunner _shellRunner;
  final AndroidBuilder _androidBuilder;
  final IOSBuilder _iosBuilder;

  late int buildNumber;

  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  late final BuildMetadata metadata;

  String get envName;
  String get iosExportMethod;
  String get apiHost;
  AndroidBuildType get androidBuildType;
  bool get shouldSwapInfoPlist => false;

  Future<void> beforeBuild() async {}

  Future<void> deployAndroid(File file);
  Future<void> deployIOS(File file);

  Future<void> cleanProject() async {
    await _shellRunner.run('fvm', ['flutter', 'clean']);
    await _shellRunner.run('fvm', ['flutter', 'pub', 'get']);
  }

  Future<void> buildPrepare() async {
    if (shouldSwapInfoPlist) {
      Logger.info('Swapping Info.plist for product environment');
      File('ios/Runner/Info.plist').renameSync('ios/Runner/Info.plist.backup');
      File('ios/Runner/Info.plist.product').renameSync('ios/Runner/Info.plist');
    }
  }

  Future<File> _buildAndroid() async {
    switch (androidBuildType) {
      case AndroidBuildType.apk:
        return _androidBuilder.buildApk(
          buildName: buildName,
          buildNumber: buildNumber,
          envName: envName,
        );
      case AndroidBuildType.appbundle:
        return _androidBuilder.buildAppBundle(
          buildName: buildName,
          buildNumber: buildNumber,
          envName: envName,
        );
    }
  }

  Future<File> _buildIOS() async {
    return _iosBuilder.buildIpa(
      buildName: buildName,
      buildNumber: buildNumber,
      envName: envName,
      exportMethod: iosExportMethod,
    );
  }

  Future<void> uploadToPgyerAndNotify(AppPlatform platform, File file) async {
    Logger.info('Processing ${platform.label}...');
    final description = [
      ..._coreInfoLines(),
      '',
      'recent commits:',
      metadata.recentCommits,
    ].join('\n');

    final url = await _deployService.uploadToPgyer(
      file.path,
      config.pgyerApiKey!,
      updateDescription: description,
    );

    await _deployService.sendFeishuNotification(
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

  Future<void> run() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await _versionManager.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep(
      'Collect Build Metadata',
      () => BuildMetadata.collect(_gitManager),
    );
    try {
      await runStep('Check Git Status', _gitManager.checkClean);
      await beforeBuild();
      await buildPrepare();
      Logger.section('Starting Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final androidFile = await runStep('Build Android', _buildAndroid);
      final iosFile = await runStep('Build iOS', _buildIOS);
      await runStep('Deploy Android', () => deployAndroid(androidFile));
      await runStep('Deploy iOS', () => deployIOS(iosFile));
      await runStep(
        'Push Build Tag',
        () => _versionManager.pushNewBuildTag(buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }

  Future<void> runAndroidOnly() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await _versionManager.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep(
      'Collect Build Metadata',
      () => BuildMetadata.collect(_gitManager),
    );
    try {
      await runStep('Check Git Status', _gitManager.checkClean);
      await beforeBuild();
      await buildPrepare();
      Logger.section('Starting Android-Only Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final androidFile = await runStep('Build Android', _buildAndroid);
      await runStep('Deploy Android', () => deployAndroid(androidFile));
      await runStep(
        'Push Build Tag',
        () => _versionManager.pushNewBuildTag(buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }

  Future<void> runIOSOnly() async {
    await runStep('Resolve Build Version', () async {
      buildNumber = await _versionManager.computeNextBuildNumber(
        config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=$buildNumber  buildName=$buildName');
    });
    metadata = await runStep(
      'Collect Build Metadata',
      () => BuildMetadata.collect(_gitManager),
    );
    try {
      await runStep('Check Git Status', _gitManager.checkClean);
      await beforeBuild();
      await buildPrepare();
      Logger.section('Starting iOS-Only Build and Upload Pipeline');
      await runStep('Clean Project', cleanProject);
      final iosFile = await runStep('Build iOS', _buildIOS);
      await runStep('Deploy iOS', () => deployIOS(iosFile));
      await runStep(
        'Push Build Tag',
        () => _versionManager.pushNewBuildTag(buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }
}
