import 'package:flutter_ci_tools/src/utils/args_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ArgsParser', () {
    test('has() 精确匹配参数', () {
      final parser = ArgsParser(['android', '--debug']);
      expect(parser.has('android'), isTrue);
      expect(parser.has('--debug'), isTrue);
      expect(parser.has('ios'), isFalse);
      expect(ArgsParser([]).has('anything'), isFalse);
    });

    test('getOption() 解析 --key=value', () {
      final parser = ArgsParser(['--env=test', '--flavor=prod', '--empty=']);
      expect(parser.getOption('env'), 'test');
      expect(parser.getOption('flavor'), 'prod');
      // --key= 是空串而不是 null，调用方才能区分「没传」和「传了空值」
      expect(parser.getOption('empty'), '');
      expect(parser.getOption('missing'), isNull);
      expect(ArgsParser([]).getOption('env'), isNull);
    });

    test('positional 取第一个非 -- 参数，与顺序无关', () {
      expect(ArgsParser(['android', '--debug']).positional, 'android');
      expect(ArgsParser(['--debug', 'android']).positional, 'android');
      expect(ArgsParser(['--debug', '--verbose']).positional, isNull);
      expect(ArgsParser([]).positional, isNull);
    });

    test('positionalArgs 取全部非 -- 参数', () {
      expect(ArgsParser(['android', 'ios', '--debug']).positionalArgs,
          ['android', 'ios']);
      expect(ArgsParser(['--debug', '--verbose']).positionalArgs, isEmpty);
      expect(ArgsParser([]).positionalArgs, isEmpty);
    });
  });
}
