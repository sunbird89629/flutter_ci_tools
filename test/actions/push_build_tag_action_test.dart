import 'package:flutter_ci_tools/src/actions/push_build_tag_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  final List<int> pushed = [];

  @override
  Future<int?> fetchLatestBuildNumber() async => null;

  @override
  Future<int> computeNextBuildNumber(int seed) async => seed;

  @override
  Future<void> pushNewBuildTag(int buildNumber) async {
    pushed.add(buildNumber);
  }

  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

void main() {
  test(
      'PushBuildTagAction delegates buildNumber to VersionManager.pushNewBuildTag',
      () async {
    final version = _FakeVersionManager();
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      platforms: <AppPlatform>{},
    )..buildNumber = 12042;

    final action = PushBuildTagAction(versionManager: version);
    await action.run(context);

    expect(action.name, 'Push Build Tag');
    expect(version.pushed, [12042]);
  });
}
