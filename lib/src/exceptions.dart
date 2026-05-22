/// Exceptions thrown by flutter_ci_tools.
/// Thrown when a Git command fails or the working tree is not clean.
class GitException implements Exception {
  /// Human-readable error description.
  final String message;

  /// The exit code of the failed Git command.
  final int exitCode;
  const GitException(this.message, this.exitCode);

  @override
  String toString() => 'GitException: $message (exit code $exitCode)';
}

/// Thrown when a deploy operation (upload, notification) fails.
class DeployException implements Exception {
  /// Human-readable error description.
  final String message;
  const DeployException(this.message);

  @override
  String toString() => 'DeployException: $message';
}
