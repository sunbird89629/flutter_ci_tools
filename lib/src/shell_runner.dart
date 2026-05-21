class ShellResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

abstract class ShellRunner {
  Future<void> run(String executable, List<String> args);
  Future<ShellResult> runAndCapture(String executable, List<String> args);
}
