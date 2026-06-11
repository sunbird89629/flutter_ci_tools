import 'dart:io';

/// Colored terminal logger with emoji indicators, timestamps, and indentation.
///
/// Use [Logger.terminal] for real CLI output (writes to stdout/stderr).
/// Use [Logger.silent] for tests (discards all output).
class Logger {
  final bool noColor;
  final bool isVerbose;
  int _indentLevel = 0;
  final void Function(String) _write;
  final void Function(String) _writeErr;

  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _blue = '\x1B[34m';
  static const _cyan = '\x1B[36m';
  static const _gray = '\x1B[90m';

  /// Real terminal logger writing to [stdout] and [stderr].
  Logger.terminal({
    this.noColor = false,
    this.isVerbose = false,
  })  : _write = ((String s) => stdout.writeln(s)),
        _writeErr = ((String s) => stderr.writeln(s));

  /// Silent logger that discards all output (for tests and fallback defaults).
  Logger.silent()
      : noColor = true,
        isVerbose = false,
        _write = _noop,
        _writeErr = _noop;

  static void _noop(String _) {}

  String get _prefix => '  ' * _indentLevel;

  String _ts() {
    final t = DateTime.now();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '[$h:$m:$s]';
  }

  static String _fmt(int seconds) =>
      seconds >= 60
          ? '${seconds ~/ 60}m${seconds % 60}s'
          : '${seconds}s';

  void indent() => _indentLevel++;
  void outdent() {
    if (_indentLevel > 0) _indentLevel--;
  }

  void info(String msg) => _write(
        '${_ts()} $_prefix${_color(_blue)}ℹ️  $msg$_resetC',
      );

  void success(String msg) => _write(
        '$_prefix${_color(_green)}✅ $msg$_resetC',
      );

  void warning(String msg) => _write(
        '$_prefix${_color(_yellow)}⚠️  $msg$_resetC',
      );

  void error(String msg) => _writeErr(
        '$_prefix${_color(_red)}❌ $msg$_resetC',
      );

  /// Section header — prints title with 🚀 and auto-indents.
  void section(String title) {
    _write('\n${_ts()} $_prefix${_color(_cyan)}${_bold}🚀 $title...$_resetC');
    _write('$_prefix$_gray${'─' * 40}$_resetC');
    indent();
  }

  /// Finishes a section: prints result, outdents.
  void closeSection(bool ok, String name, Duration duration) {
    outdent();
    final time = _fmt(duration.inSeconds);
    if (ok) {
      success('Finished: $name ($time)');
    } else {
      error('Failed: $name ($time)');
    }
  }

  /// Prints a shell command with timestamp at current indent level.
  void command(String cmd) => _write(
        '${_ts()} $_prefix${_color(_green)}\$ $cmd$_resetC',
      );

  /// Shell output line; only printed when [isVerbose] is true.
  void verbose(String line) {
    if (isVerbose) _write(line);
  }

  String _color(String ansi) => noColor ? '' : ansi;
  String get _resetC => noColor ? '' : _reset;
}
