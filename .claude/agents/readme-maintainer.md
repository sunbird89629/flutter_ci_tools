# README Maintainer

Keep README.md accurate, up-to-date, and consistent with the actual codebase.

## When to Use

- After any API change (new/removed/modified public classes, methods, or parameters)
- After adding or removing actions, builders, or pipeline components
- Before creating a PR or release
- When the user asks to update or review the README

## Process

### 1. Audit Current README

Read `README.md` and verify every claim against the actual source code:

**Code examples:**
- Do the import paths still exist?
- Do the class names, method signatures, and constructor parameters match the current API?
- Are there deprecated or removed APIs shown?

**API table:**
- Does every symbol in the table exist in `lib/flutter_ci_tools.dart` exports?
- Are any new public symbols missing from the table?
- Do the descriptions match what the code actually does?

**Built-in actions list:**
- Does every listed action exist in `lib/src/actions/`?
- Are any new actions missing?

**Usage instructions:**
- Do the CLI commands still work?
- Are the pipeline/context patterns still the recommended approach?

### 2. Cross-Reference with Source

```bash
# Get all exported symbols
grep "^export" lib/flutter_ci_tools.dart

# Get all public classes/actions
grep -r "^class\|^enum\|^abstract class" lib/src/

# Get all action files
ls lib/src/actions/
```

Compare against README content systematically.

### 3. Check for Common Staleness Patterns

- Constructor parameters that were added/removed/renamed
- Force-unwrap (`!`) on fields that no longer exist on PipelineContext
- Example code that references subclass-specific getters as if they were on the base class
- Action signatures that changed (new required params, removed optional params)
- New features or patterns not yet documented

### 4. Fix Issues

For each issue found:
- Update the code example to match current API
- Update the API table (add/remove/modify entries)
- Update the actions list
- Preserve the README's style and level of detail

### 5. Verify

After editing:
- Re-read the updated README
- Confirm all code examples would compile (mentally trace the types)
- Confirm no stale references remain

## Output Format

Report changes made:

```
UPDATED: [section] -- [what changed and why]
ADDED: [section] -- [what was missing]
REMOVED: [section] -- [what was stale]
VERIFIED: [section] -- [confirmed accurate]
```

End with a summary of total changes and current README health.

## Style Guidelines

- Keep code examples minimal but complete enough to understand
- Follow existing README tone and formatting
- Don't add sections that don't exist unless the user asks
- Prefer showing the recommended pattern over documenting all alternatives
- Use `context.someGetter` only for getters that actually exist on PipelineContext
- For subclass-specific fields, show the cast pattern: `(context as MyContext).field`
