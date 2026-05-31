import 'dart:io';

import 'utils/args_parser.dart';
import 'utils/git_manager.dart';

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
/// construction time and runtime state (build number, build artifact)
/// populated by lifecycle actions during a single pipeline run.
///
/// Subclass this to bundle reusable configuration across multiple pipelines.
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    this.rawArgs = const [],
    GitManager? git,
  }) : git = git ?? GitManager.instance;

  /// Git accessor shared across all pipeline actions.
  final GitManager git;

  /// Display name of the application (used in notifications).
  final String appName;

  /// Starting build number used when no existing `builds/*` tag is found.
  final int seedBuildNumber;

  /// Raw CLI arguments passed through from the registry.
  final List<String> rawArgs;

  /// Convenience argument parser built from [rawArgs].
  late final ArgsParser args = ArgsParser(rawArgs);

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

  /// Flutter 项目根目录。
  ///
  /// 从 [Directory.current] 起逐级向上查找含 `pubspec.yaml` 的目录。
  /// 到文件系统根仍未找到则抛 [StateError]。
  late final Directory projectRoot = _findProjectRoot();

  /// `pubspec.yaml` 的 `name` 字段。
  late final String pubspecName = _readPubspecField('name');

  /// `pubspec.yaml` 的 `version` 字段（原始字符串，如 `"0.1.0"`）。
  late final String pubspecVersion = _readPubspecField('version');

  late final String _pubspecContent =
      File('${projectRoot.path}/pubspec.yaml').readAsStringSync();

  String _readPubspecField(String key) {
    final match = RegExp('^$key:\\s*(.+)\$', multiLine: true)
        .firstMatch(_pubspecContent);
    if (match == null) {
      throw StateError('pubspec.yaml 中未找到字段：$key。');
    }
    var value = match.group(1)!;
    // 去掉行尾注释
    final hash = value.indexOf('#');
    if (hash != -1) value = value.substring(0, hash);
    value = value.trim();
    // 去掉首尾引号
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }

  Directory _findProjectRoot() {
    var dir = Directory.current.absolute;
    while (true) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw StateError(
          '未找到 pubspec.yaml：从 ${Directory.current.path} 向上查找至文件系统根均无结果。',
        );
      }
      dir = parent;
    }
  }
}
