import 'dart:io';

/// Colored terminal logger with emoji indicators and timestamps.
///
/// All methods write directly to stdout/stderr. Used throughout the library
/// for consistent build output formatting.
class Logger {
  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _blue = '\x1B[34m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  /// Prints an informational message in blue.
  static void info(String msg) => stdout.writeln('$_blueℹ️  $msg$_reset');

  /// Prints a success message in green.
  static void success(String msg) => stdout.writeln('$_green✅ $msg$_reset');

  /// Prints a warning message in yellow.
  static void warning(String msg) => stdout.writeln('$_yellow⚠️  $msg$_reset');

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Returns the current time formatted as `[HH:MM:SS]`.
  static String get timeStamp {
    final t = DateTime.now();
    return '[${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}]';
  }

  /// Prints an error message in red to stderr, optionally including the error object.
  static void error(String msg, [Object? e]) {
    stderr.writeln('$_red❌ $msg$_reset');
    if (e != null) stderr.writeln('$_red   Error: $e$_reset');
  }

  /// Prints a bold section header with a separator line.
  static void section(String title) {
    stdout.writeln('\n$_bold$_cyan🚀 $title...$_reset');
    stdout.writeln('$_gray${'—' * 40}$_reset');
  }

  /// Prints a shell command with a timestamp in green.
  static void command(String cmd) {
    final content = '$timeStamp$_green$cmd$_reset';
    stdout.writeln(content);
  }

  /// Prints a message with an optional ANSI [color] code.
  static void print(String msg, {String color = _reset}) =>
      stdout.writeln('$color$msg$_reset');
}
