#!/usr/bin/env zsh
# Integration tests: gv --rm

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Removes worktree directory
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv --rm myapp my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/my-feature" ]]
' 'removes worktree directory'

# Deletes local branch
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv --rm myapp my-feature &>/dev/null
    local branches=$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/my-feature")
    [[ -z "$branches" ]]
' 'deletes local branch'

# Kills tmux session
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    MOCK_TMUX_CALLS=()
    gv --rm myapp my-feature &>/dev/null
    mock_tmux_was_called_with "kill-session"
' 'kills tmux session'

# Cleans up empty parent dir
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv --rm myapp my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp" ]]
' 'cleans up empty parent dir'

# Non-existent workspace returns error
ztr test '
    gv --rm nonexistent blah &>/dev/null
    (( $? != 0 ))
' 'removing non-existent workspace returns error'

# Parent dir preserved when other instances exist
ztr test '
    create_test_repo myapp
    gv myapp feature1 &>/dev/null
    gv myapp feature2 &>/dev/null
    gv --rm myapp feature1 &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/myapp" ]] &&
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/feature2" ]] &&
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/feature1" ]]
' 'parent dir preserved when other instances exist'

# Multi-project removal cleans all worktrees
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    gv --rm fullstack my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature" ]]
' 'multi-project removal cleans all worktrees'
