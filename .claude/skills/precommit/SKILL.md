---
name: precommit
description: Use when code changes are ready to validate before committing, or when the user says "precommit", "check everything", or "run checks"
---

# Precommit

Run the full precommit suite and fix any issues.

## Steps

1. Run `mix precommit` (compiles with `--warnings-as-errors`, checks unused deps, formats code, runs tests)
2. If **compilation warnings** fail the build: fix each warning (unused variables, missing specs, deprecated calls), then re-run
3. If **format** fails: run `mix format`, then re-run
4. If **tests** fail: investigate and fix failures, then re-run
5. Report a summary of what passed and what was fixed

## Common Failures

| Failure | Fix |
|---------|-----|
| Unused variable warning | Prefix with `_` or remove |
| Unused dep | Remove from `mix.exs`, run `mix deps.unlock --unused` |
| Format diff | `mix format` |
| Test failure | Read test, read implementation, fix root cause |
