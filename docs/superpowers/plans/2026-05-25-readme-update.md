# README Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update README.md to reflect the new Pipeline/Action architecture and move the debug section to a separate doc.

**Architecture:** Example-first structure — show a working pipeline upfront in Quick Start, then expand into Usage steps, API table, and Example link. Debug section moves to `docs/debugging-vscode.md`.

**Tech Stack:** Markdown (documentation only)

---

### Task 1: Create `docs/debugging-vscode.md`

**Files:**
- Create: `docs/debugging-vscode.md`

Move the debug section out of README first so we can rewrite README cleanly.

- [ ] **Step 1: Create the debug doc**

Create `docs/debugging-vscode.md` with the following content (extracted from current README lines 55–99):

````markdown
# Debug Your Build Script in VS Code

`build.dart` is a plain Dart CLI script, so VS Code's Flutter "Run/Debug"
buttons don't apply. Use the Dart VM Service + **Attach to Dart Process**
workflow instead:

**Step 1 — Set a breakpoint** somewhere in `build.dart` (e.g. the first line
of `main`).

![Set a breakpoint in main()](../image-3.png)

**Step 2 — Launch the script with the VM service enabled and paused at
start**, so the debugger has time to attach before any code runs:

```bash
dart run --observe --pause-isolates-on-start build.dart test_android
```

You'll see output like:

```text
The Dart VM service is listening on http://127.0.0.1:8181/7AV5Tc5ob6A=/
The Dart DevTools debugger and profiler is available at: http://127.0.0.1:8181/7AV5Tc5ob6A=/devtools/?uri=ws://127.0.0.1:8181/7AV5Tc5ob6A=/ws
vm-service: isolate(5025938485331611) 'main' has no debugger attached and is paused at start.
```

Copy the VM service URI (`http://127.0.0.1:8181/7AV5Tc5ob6A=/`).

**Step 3 — In VS Code, open the Command Palette** (`⌘⇧P` / `Ctrl+Shift+P`)
and run **`Debug: Attach to Dart Process`**.

![Command Palette: Debug: Attach to Dart Process](../image.png)

**Step 4 — Paste the VM service URI** from Step 2 and press Enter.

![Paste VM Service URI](../image-1.png)

**Step 5 — The debugger attaches and stops at your breakpoint.** Locals,
call stack, and step controls all work as usual.

![Debugger paused at breakpoint with Locals panel](../image-2.png)

> Tip: if you only need logs (no breakpoints), drop `--pause-isolates-on-start`
> and just use `dart run --observe build.dart …. The script runs immediately
> and you can attach at any time.
````

- [ ] **Step 2: Verify image paths**

The images (`image.png`, `image-1.png`, `image-2.png`, `image-3.png`) live in the repo root. The doc is at `docs/debugging-vscode.md`, so paths use `../` prefix. Confirm the images exist:

```bash
ls image.png image-1.png image-2.png image-3.png
```

Expected: all four files exist in repo root.

- [ ] **Step 3: Commit**

```bash
git add docs/debugging-vscode.md
git commit -m "docs: move VS Code debug guide to docs/debugging-vscode.md"
```

---

### Task 2: Rewrite `README.md`

**Files:**
- Modify: `README.md`

Replace the entire README with the new example-first structure.

- [ ] **Step 1: Write the new README**

Replace the full content of `README.md` with:

````markdown
# flutter_ci_tools

Reusable CI tooling for Flutter apps. Provides a pipeline/action architecture
for build orchestration, git-tag-based versioning, deploy services (Pgyer,
Feishu, Google Play, App Store), and structured terminal logging.

## Quick Start

### 1. Entry point — `ci/build.dart`

```dart
import 'package:flutter_ci_tools/flutter_ci_tools.dart';
import 'pipelines/test_pipeline.dart';
import 'pipelines/prod_pipeline.dart';

Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(TestPipeline())
    ..register(ProdPipeline());
  await registry.run(args);
}
```

### 2. Define a pipeline

```dart
class TestPipeline extends BuildPipeline {
  @override String get name => 'test';
  @override String get description => 'Build & deploy to Pgyer';
  @override String get help => '...';

  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      MyAppContext(platforms: platforms);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    await runAction(CollectMetadataAction());
    await runAction(CleanProjectAction());

    if (context.platforms.contains(AppPlatform.android)) {
      final apk = await runAction(BuildAndroidAction(
        envName: 'test', buildType: AndroidBuildType.apk,
      ));
      await runAction(PgyerUploadAction(
        artifact: apk, apiKey: context.pgyerApiKey!, description: '...',
      ));
    }

    await runAction(PushBuildTagAction());
  }

  @override
  Future<void> afterBuild() => runAction(RestoreWorkspaceAction());
}
```

## Usage

### 1. Define your PipelineContext

Subclass `PipelineContext` to bundle shared configuration (app name,
credentials, etc.) across all pipelines:

```dart
class MyAppContext extends PipelineContext {
  MyAppContext({required super.platforms})
      : super(
          appName: 'MyApp',
          seedBuildNumber: 10000,
          pgyerApiKey: Platform.environment['PGYER_API_KEY'],
          feishuWebhookUrl: Platform.environment['FEISHU_WEBHOOK_URL'],
        );
}
```

### 2. Create a BuildPipeline

Implement `body()` to compose actions. Use `runAction()` to execute each
step with automatic logging and error handling:

```dart
class MyPipeline extends BuildPipeline {
  @override String get name => 'test';
  @override String get description => '...';
  @override String get help => '...';

  @override
  PipelineContext createContext(Set<AppPlatform> platforms) =>
      MyAppContext(platforms: platforms);

  @override
  Future<void> body() async {
    await runAction(ResolveBuildVersionAction());
    // ... compose more actions
  }
}
```

### 3. Register & run

```dart
Future<void> main(List<String> args) async {
  final registry = PipelineRegistry()
    ..register(MyPipeline());
  await registry.run(args);
}
```

Run from the command line:

```bash
dart run ci/build.dart test           # both platforms
dart run ci/build.dart test android   # Android only
dart run ci/build.dart                # interactive selector
```

## API

| Symbol | Description |
|--------|-------------|
| `PipelineContext` | Shared config + runtime state passed through all actions |
| `BuildPipeline` | Abstract base: `beforeBuild → body → afterBuild` lifecycle |
| `PipelineAction<R>` | Abstract action unit; receives context, returns typed result |
| `PipelineRegistry` | Registers pipelines; handles CLI routing and interactive selection |
| `runStep` | Logs + times a pipeline step, rethrows on failure |
| `Logger` | Coloured stdout/stderr output |
| `ShellRunner` | Process runner with live streaming and capture |
| `GitManager` | Git status, branch, hash, commit history |
| `VersionManager` | `builds/*` git-tag-based build numbering |
| `BuildMetadata` | Collects branch/user/hash/commits at build time |

Built-in actions include `ResolveBuildVersionAction`, `CollectMetadataAction`,
`CheckGitStatusAction`, `CleanProjectAction`, `BuildAndroidAction`,
`BuildIOSAction`, `PgyerUploadAction`, `PgyerUploadV2Action`,
`GooglePlayUploadAction`, `AppStoreUploadAction`, `FeishuBuildNotifyAction`,
`PushBuildTagAction`, and `RestoreWorkspaceAction`.

## Example

A complete consumer demo lives in [`example/`](./example/) — three pipelines
(test, prod, android-test), all deploy targets, and a Flutter app that displays
its own build metadata at runtime.
````

- [ ] **Step 2: Verify the README renders correctly**

Open `README.md` in a Markdown previewer and confirm:
- Code blocks have syntax highlighting
- Table renders correctly
- Example link points to `./example/`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for Pipeline/Action architecture"
```
