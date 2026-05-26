import 'dart:io';

import 'build_metadata.dart';

/// State of the build version number.
sealed class BuildVersion {}

/// Build version has not yet been resolved by [ResolveBuildVersionAction].
class BuildVersionUnresolved extends BuildVersion {}

/// Build version was resolved to a concrete [value].
class BuildVersionResolved extends BuildVersion {
  final int value;
  BuildVersionResolved(this.value);
}

/// Shared, mutable context passed through all pipeline steps.
///
/// Holds both static configuration (app identity) provided at
/// construction time and runtime state (metadata, build number, build artifact)
/// populated by lifecycle actions during a single pipeline run.
///
/// Subclass this to bundle reusable configuration across multiple pipelines.
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
  });

  /// Display name of the application (used in notifications).
  final String appName;

  /// Starting build number used when no existing `builds/*` tag is found.
  final int seedBuildNumber;

  /// Git and build metadata, populated by `CollectMetadataAction`.
  late BuildMetadata metadata;

  BuildVersion _buildVersion = BuildVersionUnresolved();

  /// Resolved build number.
  ///
  /// Throws [StateError] if accessed before [resolveBuildVersion] is called
  /// (typically by `ResolveBuildVersionAction`).
  int get buildNumber {
    switch (_buildVersion) {
      case BuildVersionUnresolved():
        throw StateError(
          'buildNumber 尚未解析。请确保先执行 ResolveBuildVersionAction。',
        );
      case BuildVersionResolved(:final value):
        return value;
    }
  }

  /// Sets the build number. Called by `ResolveBuildVersionAction`.
  void resolveBuildVersion(int version) {
    _buildVersion = BuildVersionResolved(version);
  }

  /// Human-readable build name derived from [buildNumber] (e.g. `"1.2.0"`).
  String get buildName {
    final str = buildNumber.toString();
    return '${str[0]}.${str[1]}.${str[2]}';
  }

  File? _buildArtifact;

  /// The build artifact file produced by a build action.
  ///
  /// Throws [StateError] if accessed before a build action sets it
  /// (e.g. `BuildAndroidAction` or `BuildIOSAction`).
  File get buildArtifact {
    if (_buildArtifact == null) {
      throw StateError(
        'buildArtifact 尚未设置。请先执行 BuildAndroidAction 或 BuildIOSAction。',
      );
    }
    return _buildArtifact!;
  }

  /// Sets the build artifact file. Called by build actions.
  void setBuildArtifact(File file) => _buildArtifact = file;
}
