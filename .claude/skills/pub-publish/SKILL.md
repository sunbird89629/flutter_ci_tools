---
name: pub-publish
description: Publish a new version of flutter_ci_tools to pub.dev
disable-model-invocation: true
---

# Pub Publish

Publish flutter_ci_tools to pub.dev with pre-flight checks.

## Usage

```
/pub-publish
```

## Process

1. **Verify working directory is clean**:
   ```bash
   git status --porcelain
   ```

2. **Run pre-flight checks**:
   ```bash
   dart format --output=none --set-exit-if-changed lib test
   dart analyze --fatal-infos lib test
   dart test
   ```

3. **Dry-run publish**:
   ```bash
   dart pub publish --dry-run
   ```

4. **Confirm with user** — show the current version from `pubspec.yaml` and ask to proceed.

5. **Publish**:
   ```bash
   dart pub publish
   ```

6. **Push tags** (if not already pushed):
   ```bash
   git push origin --tags
   ```

## Notes

- Always run pre-flight checks before publishing — pub.dev does not allow overwriting versions
- If any check fails, fix it before proceeding
- The version in `pubspec.yaml` must be updated beforehand (use the `ship-release` skill for this)
- Tags should already exist from the `ship-release` workflow; this step only ensures they're pushed
