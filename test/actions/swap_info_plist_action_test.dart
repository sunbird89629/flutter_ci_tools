import 'dart:io';

import 'package:flutter_ci_tools/src/actions/swap_info_plist_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('swap_info_plist_test_');
    final ios = Directory('${tmp.path}/ios/Runner')
      ..createSync(recursive: true);
    File('${ios.path}/Info.plist').writeAsStringSync('original');
    File('${ios.path}/Info.plist.product').writeAsStringSync('product');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('SwapInfoPlistAction renames Info.plist ↔ Info.plist.product', () async {
    final cwd = Directory.current;
    Directory.current = tmp;
    try {
      final action = SwapInfoPlistAction();
      await action.run(PipelineContext(
        appName: 'TestApp',
        seedBuildNumber: 12000,
        platforms: <AppPlatform>{},
      ));

      expect(action.name, 'Swap Info.plist for Product Variant');
      expect(File('ios/Runner/Info.plist').readAsStringSync(), 'product');
      expect(
          File('ios/Runner/Info.plist.backup').readAsStringSync(), 'original');
    } finally {
      Directory.current = cwd;
    }
  });
}
