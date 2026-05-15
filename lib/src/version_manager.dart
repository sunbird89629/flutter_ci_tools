import 'dart:io';

import 'logger.dart';
import 'shell_runner.dart' show ShellRunner;

class VersionManager {
  VersionManager._();

  static const _tagPrefix = 'builds/';
  static const _bumpGranularity = 100;

  static Future<int?> fetchLatestBuildNumber() async {
    await ShellRunner.instance.runAndCapture('git', ['fetch', '--tags', '--force']);
    final res = await ShellRunner.instance.runAndCapture('git', [
      'tag', '--list', '$_tagPrefix*',
    ]);
    final nums = res.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith(_tagPrefix))
        .map((l) => int.tryParse(l.substring(_tagPrefix.length)))
        .whereType<int>()
        .toList();
    return nums.isEmpty ? null : nums.reduce((a, b) => a > b ? a : b);
  }

  static Future<int> computeNextBuildNumber(int seedBuildNumber) async {
    final latest = await fetchLatestBuildNumber();
    if (latest == null) {
      Logger.warning(
        'No "$_tagPrefix*" tag found. Seeding from $seedBuildNumber.',
      );
      return seedBuildNumber;
    }
    return latest + 1;
  }

  static Future<void> pushNewBuildTag(int buildNumber) async {
    final tag = '$_tagPrefix$buildNumber';
    Logger.info('Tagging $tag ...');
    await ShellRunner.instance.run('git', [
      'tag', '-a', '-f', tag, '-m', 'CI build $buildNumber',
    ]);
    await ShellRunner.instance.run('git', ['push', '--force', 'origin', tag]);
    Logger.success('Pushed tag $tag');
  }

  static Future<void> interactiveBumpAndPush(int seedBuildNumber) async {
    final latest = await fetchLatestBuildNumber();
    final floor = latest ?? (seedBuildNumber - 1);
    final base = latest ?? seedBuildNumber;
    final suggested = (base ~/ _bumpGranularity + 1) * _bumpGranularity;
    Logger.info('Current latest builds tag: ${latest ?? '(none)'}');

    while (true) {
      stdout.write('Enter new base buildNumber (default $suggested): ');
      final input = stdin.readLineSync()?.trim() ?? '';
      final next = input.isEmpty ? suggested : int.tryParse(input);
      if (next == null || next <= floor) {
        Logger.error('Invalid buildNumber (must be > $floor): $input');
        continue;
      }
      stdout.write('Push $_tagPrefix$next ? (y/N): ');
      if ((stdin.readLineSync() ?? '').trim().toLowerCase() != 'y') return;
      await pushNewBuildTag(next);
      return;
    }
  }
}
