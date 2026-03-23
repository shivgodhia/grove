# Development Guide

Grove is a single-file Zsh script (`grove.zsh`, ~1100 lines). There is no build step.

## Project Structure

```
grove.zsh                 # The entire tool — sourced into user's shell
grove.local.zsh           # User config (gitignored)
grove.local.example.zsh   # Config template
tests/
  run_tests.zsh           # Test runner entry point
  helpers.zsh             # Tmux mock, temp git repo builders, setup/teardown
  lib/ztr/                # zsh-test-runner (git submodule — run `git submodule update --init`)
  unit/                   # Unit tests for internal _grove_* functions
  integration/            # Integration tests for full gv workflows
skills/grove/             # Claude Code skill definition
```

## Running Tests

```bash
# First time: init the submodule
git submodule update --init

# Run all tests
zsh tests/run_tests.zsh

# Run only unit or integration tests
zsh tests/run_tests.zsh unit
zsh tests/run_tests.zsh integration
```

All tests run offline. Git tests use local bare repos as fake remotes. Tmux is fully mocked — no real sessions are created.

## Testing Framework

Tests use [zsh-test-runner](https://github.com/olets/zsh-test-runner) (ztr). Key patterns:

- Each test file defines `ZTR_SETUP_FN()` and `ZTR_TEARDOWN_FN()` as **function definitions** (not variable assignments — ztr looks up the function by name).
- Tests are single expressions passed to `ztr test '<expr>' 'name'`. Multi-statement tests use newlines inside single-quoted strings.
- Setup creates a fresh temp dir (`$TEST_TMPDIR`) with isolated `$GROVE_PROJECTS_DIR` and `$GROVE_WORKSPACES_DIR`.
- Teardown removes the temp dir.
- `create_test_repo <name>` creates a git repo with a local bare remote as origin.
- `create_remote_branch <repo> <branch>` pushes a branch to the bare remote (deletes the local copy so it only exists on remote).
- `mock_tmux_was_called_with <pattern>` checks if any mock tmux call contained the pattern.

## Tmux Mock

The mock intercepts all `tmux` calls (grove uses bare `tmux`, not `command tmux`). It tracks sessions in `MOCK_TMUX_SESSIONS` and logs all calls to `MOCK_TMUX_CALLS`. No real tmux sessions are ever created during tests.

## Test Architecture Notes

- All test files are `source`d into a single shell process. `grove_test_setup` resets known globals between tests, but if grove.zsh introduces new globals, they could leak between tests.
- The tmux mock logs calls as `"$*"` (space-joined), so argument boundaries are lost. Use `mock_tmux_was_called_with` for substring matching; precise argument assertions are not possible.
- Tab completion code (~350 lines, ZLE widgets) is not tested — it requires an interactive terminal.

## Known Quirks

- `git ls-remote --heads origin "name"` uses suffix matching, so it matches `refs/heads/prefix/name`. This means grove's date-prefix fallback in `_grove_resolve_branch_name` is unreachable through normal `gv` usage when `prefix/name` exists on remote.
- Grove sources `grove.local.zsh` at load time. Tests copy `grove.zsh` to an isolated temp dir (without `grove.local.zsh`) to avoid loading real user config.
- Interactive-only builtins (`compdef`, `zle`, `bindkey`) are stubbed in the test harness since tests run non-interactively.
