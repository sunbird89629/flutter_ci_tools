import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  // Logger 没有可断言的返回值，这里只做冒烟：每个变体都把全部方法走一遍，
  // 保证格式化代码（颜色、耗时、section 缩进）不会抛。
  test('各 Logger 变体的所有方法都不抛', () {
    final loggers = [
      Logger.silent(),
      Logger.terminal(),
      Logger.terminal(noColor: true),
      Logger.terminal(isVerbose: false),
    ];

    for (final logger in loggers) {
      logger.info('hello');
      logger.success('ok');
      logger.warning('warn');
      logger.error('fail');
      logger.section('build');
      logger.closeSection(true, 'build', const Duration(seconds: 5));
      logger.command('fvm flutter build');
      logger.verbose('debug output');
    }
  });
}
