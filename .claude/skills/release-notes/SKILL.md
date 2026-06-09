---
name: release-notes
description: Generate CHANGELOG entries from git history
disable-model-invocation: true
---

# Release Notes Generator

Generate CHANGELOG entries for a new release based on git commit history.

## Usage

```
/release-notes v0.2.0
```

## Process

1. **Get the version tag**: Use the provided version argument (e.g., `v0.2.0`)

2. **Find the previous release**:
   ```bash
   git describe --tags --abbrev=0 HEAD~1 2>/dev/null || git log --reverse --format="%H" | head -1
   ```

3. **Get commits since last release**:
   ```bash
   git log <prev-tag>..HEAD --oneline --no-merges
   ```

4. **Categorize commits** by conventional commit prefix:
   - `feat:` → ✨ Features
   - `fix:` → 🐛 Bug Fixes
   - `refactor:` → ♻️ Refactoring
   - `docs:` → 📚 Documentation
   - `test:` → ✅ Tests
   - `chore:` → 🔧 Chores
   - `style:` → 💅 Style
   - `perf:` → ⚡ Performance

5. **Generate the CHANGELOG entry**:

```markdown
## v0.2.0 (2026-06-09)

### ✨ Features
- PgyerUploadAction supports explicit artifact parameter
- FeishuBuildNotifyAction supports multiple downloadUrls

### ♻️ Refactoring
- BuildAndroidAction returns File (backward compatible)
- extract _runTracked and add runParallel

### 🐛 Bug Fixes
- handle nested params in Pgyer COS token response

### 📚 Documentation
- add explicit artifact upload implementation plan

### ✅ Tests
- add tests for explicit artifact and parallel execution
```

6. **Update CHANGELOG.md**:
   - Read the existing `CHANGELOG.md`
   - Prepend the new entry after the title
   - Write the updated file

## Output

- Print the generated release notes to the user
- Ask if they want to update `CHANGELOG.md`
- If yes, update the file and commit:
  ```bash
  git add CHANGELOG.md
  git commit -m "docs: update CHANGELOG for <version>"
  ```

## Example

User: `/release-notes v0.2.0`

Claude:
1. Gets commits since v0.1.0
2. Categorizes them
3. Generates formatted release notes
4. Shows the preview
5. Asks to update CHANGELOG.md
6. Updates and commits

## Notes

- Only include meaningful commits (skip `chore:` commits like "apply dart format" unless they're significant)
- Group related commits together
- Use the commit message as-is (don't rewrite)
- If a commit has a body, use the body as the description
