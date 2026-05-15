/// Exceptions thrown by flutter_ci_tools.
class GitException implements Exception {
  final String message;
  final int exitCode;
  const GitException(this.message, this.exitCode);

  @override
  String toString() => 'GitException: $message (exit code $exitCode)';
}

class DeployException implements Exception {
  final String message;
  const DeployException(this.message);

  @override
  String toString() => 'DeployException: $message';
}
