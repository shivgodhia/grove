#!/usr/bin/env zsh
# Integration tests: gv <workspace> <name> <command>

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Command runs in correct working directory (single-project)
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local output=$(gv myapp my-feature pwd)
    [[ "$output" == "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" ]]
' 'command runs in single-project worktree dir'

# Command runs in workspace root for multi-project
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    local output=$(gv fullstack my-feature pwd)
    [[ "$output" == "$GROVE_WORKSPACES_DIR/fullstack/my-feature" ]]
' 'command runs in workspace root for multi-project'

# Exit code is propagated
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv myapp my-feature "false"
    (( $? != 0 ))
' 'exit code is propagated from command'

# PWD is restored after command
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local before="$PWD"
    gv myapp my-feature "true" &>/dev/null
    [[ "$PWD" == "$before" ]]
' 'PWD is restored after command passthrough'

# No tmux session created for command passthrough
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    MOCK_TMUX_CALLS=()
    gv myapp my-feature "echo hello" &>/dev/null
    ! mock_tmux_was_called_with "new-session" &&
    ! mock_tmux_was_called_with "attach-session"
' 'no tmux interaction for command passthrough'
