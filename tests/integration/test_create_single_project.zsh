#!/usr/bin/env zsh
# Integration tests: creating a single-project workspace

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Creates worktree directory at correct path
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]]
' 'creates worktree directory at correct path'

# Worktree is on the correct branch
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" rev-parse --abbrev-ref HEAD)
    [[ "$branch" == "testuser/my-feature" ]]
' 'worktree is on correct branch'

# tmux new-session called
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "new-session"
' 'tmux new-session called'

# tmux session name is correct
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "grove/myapp/my-feature"
' 'tmux session name is correct'

# Slash in name is sanitized to dash in directory
ztr test '
    create_test_repo myapp
    gv myapp "feature/auth" &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/feature-auth/myapp" ]]
' 'slash in name sanitized to dash in directory'

# Attaching to existing workspace does not recreate
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local call_count_after_create=${#MOCK_TMUX_CALLS}
    MOCK_TMUX_CALLS=()
    gv myapp my-feature &>/dev/null
    # Should have called has-session (found it) then attach, but NOT new-session
    ! mock_tmux_was_called_with "new-session"
' 'attaching to existing workspace does not create new session'
