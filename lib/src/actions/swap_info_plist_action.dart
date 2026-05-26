import 'dart:io';

import '../utils/logger.dart';
import '../pipeline_context.dart';
import 'pipeline_action.dart';

/// Swaps `ios/Runner/Info.plist` with `ios/Runner/Info.plist.product`,
/// backing up the original to `Info.plist.backup`.
///
/// Used by pipelines that build a "product" variant of the iOS app.
/// Pair with `RestoreWorkspaceAction` in `afterBuild` to undo the swap.
class SwapInfoPlistAction extends PipelineAction<void> {
  @override
  String get name => 'Swap Info.plist for Product Variant';

  @override
  Future<void> run(PipelineContext context) async {
    Logger.info('Swapping Info.plist for product environment');
    File('ios/Runner/Info.plist').renameSync('ios/Runner/Info.plist.backup');
    File('ios/Runner/Info.plist.product').renameSync('ios/Runner/Info.plist');
  }
}
