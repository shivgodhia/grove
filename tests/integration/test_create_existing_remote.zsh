#!/usr/bin/env zsh
# Integration tests: creating workspace tracking existing remote branches

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Tracks remote branch where it exists
ztr test '
    create_test_repo myapp
    create_remote_branch myapp "someone/fix-bug"
    gv myapp "someone/fix-bug" &>/dev/null
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/someone-fix-bug/myapp" rev-parse --abbrev-ref HEAD)
    [[ "$branch" == "someone/fix-bug" ]]
' 'tracks existing remote branch'

# Uses raw name (no prefix) when matching remote
ztr test '
    create_test_repo myapp
    create_remote_branch myapp "someone/fix-bug"
    gv myapp "someone/fix-bug" &>/dev/null
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/someone-fix-bug/myapp" rev-parse --abbrev-ref HEAD)
    [[ "$branch" != "testuser/someone/fix-bug" ]] && [[ "$branch" == "someone/fix-bug" ]]
' 'uses raw branch name not prefixed'

# Multi-project: tracks where available, creates off base elsewhere
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    create_remote_branch frontend "someone/fix-bug"
    # backend does NOT have this remote branch
    gv fullstack "someone/fix-bug" &>/dev/null
    local b_fe=$(git -C "$GROVE_WORKSPACES_DIR/fullstack/someone-fix-bug/frontend" rev-parse --abbrev-ref HEAD)
    local b_be=$(git -C "$GROVE_WORKSPACES_DIR/fullstack/someone-fix-bug/backend" rev-parse --abbrev-ref HEAD)
    [[ "$b_fe" == "someone/fix-bug" ]] && [[ "$b_be" == "someone/fix-bug" ]]
' 'multi-project: tracks where available, creates new branch elsewhere'
