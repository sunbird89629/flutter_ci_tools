import 'version_manager_impl.dart';

/// Interface for managing git-tag-based build versioning.
///
/// Uses `builds/<number>` tags to track and increment build numbers.
abstract class VersionManager {
  /// Default singleton instance.
  static VersionManager instance = VersionManagerImpl();

  /// Fetches the highest existing `builds/*` tag from the remote, or `null` if none exist.
  Future<int?> fetchLatestBuildNumber();

  /// Returns the next build number: latest tag + 1, or [seedBuildNumber] if no tags exist.
  Future<int> computeNextBuildNumber(int seedBuildNumber);

  /// Creates and force-pushes a `builds/<number>` tag to origin.
  Future<void> pushNewBuildTag(int buildNumber);

  /// Prompts the user interactively to choose a new base build number and pushes the tag.
  Future<void> interactiveBumpAndPush(int seedBuildNumber);
}
