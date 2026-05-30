# Remove `BuildMetadata` — Design

Date: 2026-05-31
Status: Approved (ready for implementation plan)

## Goal

Delete the `BuildMetadata` value object and its `CollectMetadataAction`. Expose
a `GitManager` directly on `PipelineContext` so consumers query git data
on-demand at the point of use.

## Why

`BuildMetadata` is an anemic data bag: it does nothing but relay the results of
five `GitManager` methods (`getBranch`, `getCurrentUser`, `getShortHash`,
`getRecentCommits`, `getLatestCommitBody`) into fields. It has no behavior of
its own and adds a layer of indirection plus an implicit lifecycle ordering
("you must run `CollectMetadataAction` before reading `context.metadata`").

Pure git reads do not warrant a dedicated pipeline action. (Contrast
`ResolveBuildVersionAction`, which has real logic — computing the next build
number — and stays.)

## Design

### 1. `GitManager` on `PipelineContext`

`PipelineContext` gains an injectable `git` dependency, replacing the
`late BuildMetadata metadata` field.

```dart
class PipelineContext {
  PipelineContext({
    required this.appName,
    required this.seedBuildNumber,
    this.rawArgs = const [],
    GitManager? git,                 // injectable; tests pass a fake
  }) : git = git ?? GitManager.instance;

  final GitManager git;
  // removed: late BuildMetadata metadata;
}
```

Rationale for putting `git` on the context (vs. each action injecting its own
`GitManager`): single source, less repetition across actions, and git is
genuinely pipeline-global infrastructure. Consistent with the project's
"maintainability first" priority.

### 2. Deletions

- `lib/src/build_metadata.dart` (the `BuildMetadata` class)
- `lib/src/actions/collect_metadata_action.dart`
- `test/build_metadata_test.dart`
- `test/actions/collect_metadata_action_test.dart`
- Barrel export of `build_metadata.dart` in `lib/flutter_ci_tools.dart`
- `runAction(CollectMetadataAction())` lines in every example pipeline
  (`test_pipeline.dart`, `prod_pipeline.dart`, `android_test_pipeline.dart`)

### 3. Consumer changes

**`FeishuBuildNotifyAction._formatMessage`** becomes async and reads from
`context.git` instead of `context.metadata`:

```dart
Future<String> _formatMessage(PipelineContext context) async {
  final git = context.git;
  final branch = await git.getBranch();
  final gitUser = await git.getCurrentUser();
  final gitHash = await git.getShortHash();
  final recentCommits = await git.getRecentCommits(count: 15);
  final commitBody = await git.getLatestCommitBody();
  // ...message assembly unchanged
}
```

`run()` is already async, so the caller just awaits `_formatMessage`.

The example `_pgyerDescription()` in `test_pipeline.dart` changes the same way
(becomes async, reads `context.git`).

### 4. `getRecentCommits` count

`BuildMetadata.collect` hard-coded `count: 15`, but `GitManager.getRecentCommits`
defaults to `10`. To preserve current behavior, call sites pass `count: 15`
explicitly. `GitManager`'s default is left unchanged.

## Known constraint

The old design froze a git snapshot once at the start of the pipeline; the new
design reads on-demand. This is safe **only as long as no action between the
build and the consumption point produces a new commit**.

In the current pipelines the order is `Build → PushBuildTag → notify`, and
`PushBuildTagAction` only creates a tag (it does not move `HEAD`), so
`getShortHash` / `getBranch` / `getRecentCommits` are identical at build time and
notify time. The risk is therefore non-existent today, but is recorded here:
anyone inserting a commit-producing action after the build must re-evaluate
this assumption.

## Out of scope

- The example app's `build_info.json` (runtime display) is a separate pipeline
  that reads a bundled asset at runtime; no library action writes it, so it is
  unaffected.
- `ResolveBuildVersionAction` keeps its git access — it has real logic, not a
  relay.

## Testing

- Remove the two deleted-class tests.
- `pipeline_context_test.dart`: drop assertions on `context.metadata.*`; add a
  test that an injected fake `GitManager` is exposed via `context.git`.
- `feishu_build_notify_action_test.dart`: construct the context with a fake
  `GitManager` (instead of assigning `..metadata = BuildMetadata(...)`) and
  assert the formatted message still contains branch / user / hash / recent
  commits / commit body.
