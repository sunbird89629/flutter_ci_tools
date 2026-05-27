/// Simple CLI argument parser.
///
/// Provides helpers for common arg patterns without imposing a full
/// arg-parsing framework. Pipelines interpret args however they like.
class ArgsParser {
  ArgsParser(this.args);

  /// Raw argument list.
  final List<String> args;

  /// Whether [arg] is present (exact match).
  bool has(String arg) => args.contains(arg);

  /// Returns the value from `--key=value`, or `null` if not found.
  String? getOption(String key) {
    final prefix = '--$key=';
    for (final arg in args) {
      if (arg.startsWith(prefix)) return arg.substring(prefix.length);
    }
    return null;
  }

  /// First positional (non `--`) argument, or `null`.
  String? get positional {
    for (final arg in args) {
      if (!arg.startsWith('--')) return arg;
    }
    return null;
  }

  /// All positional (non `--`) arguments.
  List<String> get positionalArgs =>
      args.where((a) => !a.startsWith('--')).toList();
}
