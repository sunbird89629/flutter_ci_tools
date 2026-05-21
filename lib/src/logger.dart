import 'dart:io';

class Logger {
  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _blue = '\x1B[34m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  static void info(String msg) => stdout.writeln('$_blueℹ️  $msg$_reset');
  static void success(String msg) => stdout.writeln('$_green✅ $msg$_reset');
  static void warning(String msg) => stdout.writeln('$_yellow⚠️  $msg$_reset');

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String get timeStamp {
    final t = DateTime.now();
    return '[${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}]';
  }

  static void error(String msg, [Object? e]) {
    stderr.writeln('$_red❌ $msg$_reset');
    if (e != null) stderr.writeln('$_red   Error: $e$_reset');
  }

  static void section(String title) {
    stdout.writeln('\n$_bold$_cyan🚀 $title...$_reset');
    stdout.writeln('$_gray${'—' * 40}$_reset');
  }

  static void command(String cmd) {
    final content = '$timeStamp$_green$cmd$_reset';
    stdout.writeln(content);
  }

  static void print(String msg, {String color = _reset}) =>
      stdout.writeln('$color$msg$_reset');
}
