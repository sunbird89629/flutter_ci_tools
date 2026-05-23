// lib/src/pipeline.dart
import 'dart:io';

import 'package:flutter_ci_tools/src/default_shell_runner.dart';

import 'build_metadata.dart';
import 'builders/android_builder.dart';
import 'builders/ios_builder.dart';
import 'config.dart';
import 'git_manager.dart';
import 'logger.dart';
import 'shell_runner.dart';
import 'pipeline_context.dart';
import 'version_manager.dart';

/// The target platform for a build.
enum AppPlatform {
  /// Android platform.
  android('Android'),

  /// iOS platform.
  ios('iOS');

  /// Human-readable label for the platform.
  final String label;
  const AppPlatform(this.label);
}

/// The destination where a build artifact will be uploaded.
enum DeployTarget {
  /// [Pgyer](https://www.pgyer.com) beta distribution platform.
  pgyer('Pgyer'),

  /// Google Play Console.
  googlePlay('Google Play'),

  /// Apple App Store Connect.
  appStore('App Store');

  /// Human-readable label for the deploy target.
  final String label;
  const DeployTarget(this.label);
}

/// The Android build output format.
enum AndroidBuildType {
  /// Standard APK package.
  apk,

  /// Android App Bundle for Play Store upload.
  appbundle,
}

/// Executes [action] with standardized section logging and error handling.
///
/// Prints a section header before running [action], and logs the duration
/// on success or the error on failure. Rethrows any exception from [action].
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

/// Base class for CI build pipelines.
///
/// Subclasses define environment-specific configuration by overriding the
/// abstract getters and deploy methods. The [run], [runAndroidOnly], and
/// [runIOSOnly] methods execute the full or platform-specific build flow.
///
/// All dependencies are injected via the constructor with sensible defaults,
/// making pipelines easy to test with fakes.
abstract class BuildPipeline {
  /// Creates a pipeline with the given [config] and optional dependencies.
  BuildPipeline(
    CIToolsConfig config, {
    VersionManager? versionManager,
    GitManager? gitManager,
    ShellRunner? shellRunner,
    AndroidBuilder? androidBuilder,
    IOSBuilder? iosBuilder,
  })  : context = PipelineContext(config: config, platforms: AppPlatform.values.toSet()),
        _versionManager = versionManager ?? DefaultVersionManager(),
        _gitManager = gitManager ?? DefaultGitManager(),
        _shellRunner = shellRunner ?? DefaultShellRunner(),
        _androidBuilder = androidBuilder ?? AndroidBuilder(),
        _iosBuilder = iosBuilder ?? IOSBuilder();

  /// Shared context holding config, build state, and inter-step store.
  final PipelineContext context;

  final VersionManager _versionManager;
  final GitManager _gitManager;
  final ShellRunner _shellRunner;
  final AndroidBuilder _androidBuilder;
  final IOSBuilder _iosBuilder;

  /// The human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName => context.buildName;

  /// Unique identifier for this pipeline (e.g. `"test"`, `"prod"`).
  String get name;
  /// Short description shown in the interactive pipeline selector.
  String get description;

  /// Extended help text printed when the user passes `--help`.
  String get help;

  /// Environment identifier passed to `--dart-define=ENV=` (e.g. `"test"`, `"prod"`).
  String get envName;

  /// iOS export method used by `xcodebuild` (e.g. `"development"`, `"ad-hoc"`, `"app-store"`).
  String get iosExportMethod;

  /// Backend API host URL for this environment.
  String get apiHost;

  /// Whether to build an APK or an App Bundle for Android.
  AndroidBuildType get androidBuildType;

  /// Whether to swap `Info.plist` with the product variant before building.
  ///
  /// Defaults to `false`. Override to `true` to rename `Info.plist.product`
  /// to `Info.plist` during [buildPrepare].
  bool get shouldSwapInfoPlist => false;

  /// Hook called after git check and before the build starts.
  ///
  /// Override to run environment-specific preparation (e.g. writing build info files).
  Future<void> beforeBuild() async {}

  /// Deploys the Android build artifact ([file]) to the configured target.
  Future<void> deployAndroid(File file);

  /// Deploys the iOS build artifact ([file]) to the configured target.
  Future<void> deployIOS(File file);

  /// Runs `fvm flutter clean` followed by `fvm flutter pub get`.
  Future<void> cleanProject() async {
    await _shellRunner.run('fvm', ['flutter', 'clean']);
    await _shellRunner.run('fvm', ['flutter', 'pub', 'get']);
  }

  /// Pre-build step that handles Info.plist swapping when [shouldSwapInfoPlist] is true.
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
          buildName: context.buildName,
          buildNumber: context.buildNumber,
          envName: envName,
        );
      case AndroidBuildType.appbundle:
        return _androidBuilder.buildAppBundle(
          buildName: context.buildName,
          buildNumber: context.buildNumber,
          envName: envName,
        );
    }
  }

  Future<File> _buildIOS() async {
    return _iosBuilder.buildIpa(
      buildName: context.buildName,
      buildNumber: context.buildNumber,
      envName: envName,
      exportMethod: iosExportMethod,
    );
  }

  List<String> _coreInfoLines() => [
        'versionName: ${context.buildName}',
        'versionCode: ${context.buildNumber}',
        'env:         $envName',
        'api_host:    $apiHost',
        'git_hash:    ${context.metadata.gitHash}',
      ];

  /// Builds a formatted Feishu notification message for the given [platform] and [target].
  String buildFeishuMessage({
    required AppPlatform platform,
    required DeployTarget target,
    String? downloadUrl,
  }) {
    const sep = '──────────────────────────';
    final lines = <String>[
      '🚀 ${context.config.appName} 新版本 ${context.buildNumber} (${platform.label} · ${target.label})',
      'branch: ${context.metadata.branch}  by: ${context.metadata.gitUser}',
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
      ..add(context.metadata.recentCommits);
    if (context.metadata.commitBody.isNotEmpty) {
      lines
        ..add(sep)
        ..add('版本说明:')
        ..add(context.metadata.commitBody);
    }
    return lines.join('\n');
  }

  /// Executes the full build pipeline for both Android and iOS.
  ///
  /// Steps: resolve version → collect metadata → git check → beforeBuild →
  /// buildPrepare → clean → build Android → build iOS → deploy both → push tag.
  /// Restores the workspace in a `finally` block regardless of success or failure.
  Future<void> run() async {
    await runStep('Resolve Build Version', () async {
      context.buildNumber = await _versionManager.computeNextBuildNumber(
        context.config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}');
    });
    context.metadata = await runStep(
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
        () => _versionManager.pushNewBuildTag(context.buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }

  /// Executes the build pipeline for Android only.
  Future<void> runAndroidOnly() async {
    await runStep('Resolve Build Version', () async {
      context.buildNumber = await _versionManager.computeNextBuildNumber(
        context.config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}');
    });
    context.metadata = await runStep(
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
        () => _versionManager.pushNewBuildTag(context.buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }

  /// Executes the build pipeline for iOS only.
  Future<void> runIOSOnly() async {
    await runStep('Resolve Build Version', () async {
      context.buildNumber = await _versionManager.computeNextBuildNumber(
        context.config.seedBuildNumber,
      );
      Logger.info('Resolved buildNumber=${context.buildNumber}  buildName=${context.buildName}');
    });
    context.metadata = await runStep(
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
        () => _versionManager.pushNewBuildTag(context.buildNumber),
      );
    } finally {
      await _gitManager.restoreWorkspace();
    }
  }
}
