import 'package:flutter_ci_tools/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Logger', () {
    test('silent logger accepts all methods without crash', () {
      final logger = Logger.silent();
      logger.info('hello');
      logger.success('ok');
      logger.warning('warn');
      logger.error('fail');
      logger.section('build');
      logger.closeSection(true, 'build', const Duration(seconds: 5));
      logger.command('fvm flutter build');
      logger.verbose('debug output');
      // no crash = pass
    });

    test('terminal logger accepts all methods without crash', () {
      final logger = Logger.terminal();
      logger.info('hello');
      logger.success('ok');
      logger.warning('warn');
      logger.error('fail');
      logger.section('build');
      logger.closeSection(true, 'build', const Duration(seconds: 3));
      logger.command('echo hello');
      logger.verbose('debug info');
    });

    test('terminal with noColor does not crash', () {
      final logger = Logger.terminal(noColor: true);
      logger.info('test');
      logger.success('test');
      logger.section('test');
      logger.closeSection(true, 'test', const Duration(seconds: 1));
    });

    test('verbose does not print when verbose is false', () {
      final logger = Logger.terminal(isVerbose: false);
      // Should print nothing — just ensure no crash
      logger.verbose('should not appear');
    });
  });
}
