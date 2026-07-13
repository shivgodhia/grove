#!/usr/bin/env zsh
# Integration tests: --no-tmux create-only mode
#
# --no-tmux creates the workspace/worktrees but does not open or attach a tmux
# session. It prints ONLY the workspace working directory on stdout (all progress
# output goes to stderr), so callers can `cd "$(gv --no-tmux <ws> <name>)"`.

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Creates worktree directory at correct path
ztr test '
    create_test_repo myapp
    gv --no-tmux myapp my-feature >/dev/null 2>&1
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]]
' '--no-tmux creates worktree directory at correct path'

# Worktree is on the correct branch
ztr test '
    create_test_repo myapp
    gv --no-tmux myapp my-feature >/dev/null 2>&1
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" rev-parse --abbrev-ref HEAD)
    [[ "$branch" == "testuser/my-feature" ]]
' '--no-tmux worktree is on correct branch'

# stdout is EXACTLY the worktree path (nothing else leaks to stdout)
ztr test '
    create_test_repo myapp
    local out=$(gv --no-tmux myapp my-feature 2>/dev/null)
    [[ "$out" == "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]]
' '--no-tmux prints only the worktree path on stdout'

# The printed path is usable in a cd subshell
ztr test '
    create_test_repo myapp
    ( cd "$(gv --no-tmux myapp my-feature 2>/dev/null)" && [[ "$PWD" == "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]] )
' '--no-tmux path works with cd command substitution'

# Does NOT open a tmux session
ztr test '
    create_test_repo myapp
    gv --no-tmux myapp my-feature >/dev/null 2>&1
    ! mock_tmux_was_called_with "new-session"
' '--no-tmux does not create a tmux session'

# Re-running on an existing workspace prints the same path and does not create tmux
ztr test '
    create_test_repo myapp
    gv --no-tmux myapp my-feature >/dev/null 2>&1
    MOCK_TMUX_CALLS=()
    local out=$(gv --no-tmux myapp my-feature 2>/dev/null)
    [[ "$out" == "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]] && ! mock_tmux_was_called_with "new-session"
' '--no-tmux on existing workspace prints path without creating tmux'

# Flag works in trailing position
ztr test '
    create_test_repo myapp
    local out=$(gv myapp my-feature --no-tmux 2>/dev/null)
    [[ "$out" == "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]]
' '--no-tmux is accepted in trailing argument position'

# Multi-project: prints the workspace root (not a nested project dir)
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[stack]="frontend backend"
    local out=$(gv --no-tmux stack my-feature 2>/dev/null)
    [[ "$out" == "$GROVE_WORKSPACES_DIR/stack/my-feature" ]] && [[ -d "$out/frontend" ]] && [[ -d "$out/backend" ]]
' '--no-tmux multi-project prints workspace root'
