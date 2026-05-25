import 'package:flutter_ci_tools/src/actions/resolve_build_version_action.dart';
import 'package:flutter_ci_tools/src/pipeline.dart' show AppPlatform;
import 'package:flutter_ci_tools/src/pipeline_context.dart';
import 'package:flutter_ci_tools/src/version_manager.dart';
import 'package:test/test.dart';

class _FakeVersionManager implements VersionManager {
  int nextBuildNumber = 12345;
  int? receivedSeed;

  @override
  Future<int?> fetchLatestBuildNumber() async => null;

  @override
  Future<int> computeNextBuildNumber(int seed) async {
    receivedSeed = seed;
    return nextBuildNumber;
  }

  @override
  Future<void> pushNewBuildTag(int buildNumber) async {}

  @override
  Future<void> interactiveBumpAndPush(int seed) async {}
}

void main() {
  test('ResolveBuildVersionAction sets context.buildNumber from VersionManager',
      () async {
    final version = _FakeVersionManager()..nextBuildNumber = 12001;
    final action = ResolveBuildVersionAction(versionManager: version);
    final context = PipelineContext(
      appName: 'TestApp',
      seedBuildNumber: 12000,
      platforms: <AppPlatform>{},
    );

    await action.run(context);

    expect(action.name, 'Resolve Build Version');
    expect(version.receivedSeed, 12000);
    expect(context.buildNumber, 12001);
  });
}
