# Pub Ready Checker

Validate that flutter_ci_tools is ready for pub.dev publication.

## When to Use

- Before creating a release tag
- Before running `dart pub publish`
- When updating version or CHANGELOG

## Checklist

### 1. pubspec.yaml

Required fields:

| Field | Status | Rule |
|-------|--------|------|
| `name` | Required | Lowercase, underscores only |
| `version` | Required | Semver format (x.y.z) |
| `description` | Required | 60-180 chars, starts with capital, no "A package that..." |
| `repository` | Required | Valid GitHub URL |
| `environment.sdk` | Required | Compatible constraint |

Optional but recommended: `homepage`, `issue_tracker`, `documentation`, `topics`

Check that `publish_to` is set to `https://pub.dev` (not a private registry).

### 2. CHANGELOG.md

- Must exist at project root
- Latest version must match pubspec.yaml version
- Each version section should describe what changed
- Format: `## x.y.z` followed by bullet points

### 3. LICENSE

- Must exist at project root
- Should match the license declared in pubspec.yaml (if any)
- Current: MIT, Copyright 2026 HitFinds

### 4. README.md

- Must exist at project root
- Should include: package description, installation, usage example, API overview
- No broken links or TODO placeholders

### 5. Dartdoc Coverage

All public API members should have `///` doc comments:

| Element | Check |
|---------|-------|
| Classes | `/// Description` above class declaration |
| Public methods | `/// Description` with `/// ` parameter docs |
| Enum values | Brief inline docs |
| Top-level functions | `/// Description` |
| Getters/setters | `/// Description` |

Scan `lib/flutter_ci_tools.dart` barrel exports and trace each exported file for undocumented public members.

### 6. Library Exports

- `lib/flutter_ci_tools.dart` must export all public source files
- No internal implementation files should be exported (files in `src/` that are only used internally)
- No duplicate exports

### 7. Example

- `example/` directory should exist
- Should contain a runnable example (typically `example/main.dart` or `example/lib/main.dart`)
- Example should demonstrate the primary use case

### 8. Analysis

Run `dart analyze --no-fatal-infos` and report:
- Errors (must fix)
- Warnings (should fix)
- Info (nice to fix)

### 9. Test Coverage

- Run `dart test` and verify all tests pass
- Check that test files exist for all major library components
- Current coverage ratio: ~1.1:1 (test lines : library lines) -- maintain or improve

### 10. Version Consistency

Check that version numbers match across:
- `pubspec.yaml` version field
- `CHANGELOG.md` latest entry
- Any git tags (if present)

## Output Format

Report each check as:

```
PASS: [check name]
FAIL: [check name] -- [specific issue]
WARN: [check name] -- [suggestion]
SKIP: [check name] -- [reason]
```

End with a verdict:
- **READY** -- all critical checks pass, publish-safe
- **NOT READY** -- list blocking issues
- **ALMOST** -- only warnings, publishable but could improve
