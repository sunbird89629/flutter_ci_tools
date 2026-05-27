import 'package:flutter_ci_tools/src/utils/args_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ArgsParser', () {
    group('has()', () {
      test('returns true when arg is present', () {
        final parser = ArgsParser(['android', '--debug']);
        expect(parser.has('android'), isTrue);
        expect(parser.has('--debug'), isTrue);
      });

      test('returns false when arg is absent', () {
        final parser = ArgsParser(['android']);
        expect(parser.has('ios'), isFalse);
      });

      test('returns false for empty args', () {
        expect(ArgsParser([]).has('anything'), isFalse);
      });
    });

    group('getOption()', () {
      test('returns value for --key=value', () {
        final parser = ArgsParser(['--env=test', '--flavor=prod']);
        expect(parser.getOption('env'), 'test');
        expect(parser.getOption('flavor'), 'prod');
      });

      test('returns null when key not found', () {
        final parser = ArgsParser(['--env=test']);
        expect(parser.getOption('flavor'), isNull);
      });

      test('returns empty string for --key=', () {
        final parser = ArgsParser(['--env=']);
        expect(parser.getOption('env'), '');
      });

      test('returns null for empty args', () {
        expect(ArgsParser([]).getOption('env'), isNull);
      });
    });

    group('positional', () {
      test('returns first non -- arg', () {
        final parser = ArgsParser(['android', '--debug']);
        expect(parser.positional, 'android');
      });

      test('skips -- args to find positional', () {
        final parser = ArgsParser(['--debug', 'android']);
        expect(parser.positional, 'android');
      });

      test('returns null when all args start with --', () {
        final parser = ArgsParser(['--debug', '--verbose']);
        expect(parser.positional, isNull);
      });

      test('returns null for empty args', () {
        expect(ArgsParser([]).positional, isNull);
      });
    });

    group('positionalArgs', () {
      test('returns all non -- args', () {
        final parser = ArgsParser(['android', 'ios', '--debug']);
        expect(parser.positionalArgs, ['android', 'ios']);
      });

      test('returns empty list when all args start with --', () {
        final parser = ArgsParser(['--debug', '--verbose']);
        expect(parser.positionalArgs, isEmpty);
      });

      test('returns empty list for empty args', () {
        expect(ArgsParser([]).positionalArgs, isEmpty);
      });
    });
  });
}
