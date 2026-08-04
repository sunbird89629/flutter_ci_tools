---
name: ship-release
description: Cut a release for this pub.dev package — promote the CHANGELOG's Unreleased section into a version, bump pubspec, commit, tag, push
disable-model-invocation: true
---

# Ship Release (pub.dev package)

Cuts a release for this package: `## Unreleased` → `## X.Y.Z`, bump `pubspec.yaml`,
commit, annotated tag, push.

```
/ship-release 0.2.0        # 'v0.2.0' works too — both normalize the same way
```

Not to be confused with `hao:ship`, which releases Claude plugins (`plugin.json`).

**CHANGELOG headers are bare (`## 0.2.0`); git tags carry the `v` (`v0.2.0`).**
Don't add a date or SHA to the header — versions ≤ 0.1.0 have a trailing SHA,
that convention was dropped, don't reintroduce it.

## The CHANGELOG is written by hand, not generated

Entries land **with the change that caused them**, under `## Unreleased`. By
release time the notes already exist. So this skill *promotes* them — it does
not regenerate prose from `git log --oneline`.

Git history is only a **gap check**: find changes that shipped without an entry.

## Process

### 1. Preflight — refuse to release if any of these fail

```bash
git status --porcelain          # must be empty; stop if the tree is dirty
git rev-parse --abbrev-ref HEAD # expect main
dart analyze lib test           # must be clean
dart test                       # must be green
dart pub publish --dry-run      # catches missing files / bad pubspec before the tag
```

Also confirm the version moves **forward** from `pubspec.yaml`'s current value,
and that `git tag -l v<version>` is empty.

### 2. Gap check

```bash
git log $(git describe --tags --abbrev=0)..HEAD --no-merges --format='%h %s'
```

Cross-reference against `## Unreleased`. For any commit with no entry, decide:
write one in house style, or skip it as not user-visible (internal test/chore
churn usually is). Ask the user when a commit's user impact is unclear.

### 3. Compose the entry

Rename `## Unreleased` → `## <version>`, merging in anything from step 2. Leave
no empty `## Unreleased` behind — the next change recreates it.

Sections, in this order, omitting empty ones:

| Section | Commit prefix |
|---|---|
| `### ⚠️ Breaking Changes` | `!` suffix or `BREAKING CHANGE:` footer |
| `### ✨ Features` | `feat:` |
| `### 🐛 Bug Fixes` | `fix:` |
| `### ♻️ Refactoring` | `refactor:` |
| `### ⚡ Performance` | `perf:` |
| `### 📚 Documentation` | `docs:` |
| `### ✅ Tests` | `test:` |
| `### 🔧 Chores` | `chore:` |

Breaking changes go first and **must state the migration** (`X` → `Y`), because
this package is published to pub.dev and the entry is what consumers read.

### 4. Apply, commit, tag — in this order

```bash
# a. edit pubspec.yaml version: and CHANGELOG.md, then:
git add CHANGELOG.md pubspec.yaml
git commit -m "chore: bump to <version>"

# b. tag AFTER the commit exists, so the tag contains the bump
git tag -a v<version> -m "v<version>: <一句中文简述>"

# c. push
git push origin main
git push origin v<version>
```

Tagging before committing points the tag at the previous commit — a released
`v0.2.0` whose `pubspec.yaml` still says `0.1.9`. Always commit first.

Show the composed entry and stop for confirmation before step 4. Pushing and
tagging are the irreversible parts.

## House style for entries

Match the existing entries — read `## 0.1.1`–`## 0.1.3` before writing.

- **Chinese**, wrapped at ~80 columns.
- **Say why, not just what.** A reader who hits the bug should recognize it.
  Commit subjects are a starting point, not the entry — rewrite them.
- Backtick every identifier: `` `FeishuNotifyAction` ``, `` `maxAttempts` ``.
- Concrete numbers over adjectives: "3×3=9 次请求、最坏约 2.5 分钟" beats
  "重试太多".

Good — explains the trap, not just the diff:

```markdown
- `FeishuBuildNotifyAction` 补上 `maxAttempts` / `retryDelay` 并透传给
  `FeishuNotifyAction`。此前这两个参数只存在于 `FeishuNotifyAction` 上，而所有
  流水线用的都是 `FeishuBuildNotifyAction`，等于**够不着**，只能吃默认值
```

Too thin — restates the subject line:

```markdown
- 修复 FeishuBuildNotifyAction 的重试参数
```

## Notes

- **Never edit released entries.** Fix a wrong past entry by noting the
  correction in the new version, not by rewriting history.
- `dart pub publish` itself is a separate, manual step — this skill stops at
  pushing the tag.
- If history shows the bump riding along inside a feature commit (v0.1.1–v0.1.3
  did this), that's the older one-change-per-release cadence. With an
  accumulated `## Unreleased`, use the separate `chore: bump` commit above.
