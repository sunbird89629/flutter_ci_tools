/// Result of a captured shell command execution.
class ShellResult {
  /// Process exit code (0 = success).
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Interface for executing shell commands.
///
/// Implementations can be swapped for testing to avoid real process execution.
abstract class ShellRunner {
  /// Runs a command, streaming stdout/stderr to the terminal. Throws on non-zero exit.
  Future<void> run(String executable, List<String> args);

  /// Runs a command and captures its output without printing to the terminal.
  Future<ShellResult> runAndCapture(String executable, List<String> args);
}
