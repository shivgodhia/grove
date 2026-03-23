#!/usr/bin/env zsh
# Integration tests: post-create and post-startup hooks

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Post-create hook sends command via tmux send-keys
ztr test '
    create_test_repo myapp
    grove_post_create_commands[myapp]="npm install"
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "send-keys" &&
    mock_tmux_was_called_with "npm install"
' 'post-create hook sent via tmux send-keys'

# Post-startup hook sent after creation
ztr test '
    create_test_repo myapp
    grove_post_startup_commands[myapp]="claude"
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "send-keys" &&
    mock_tmux_was_called_with "claude"
' 'post-startup hook sent via tmux send-keys'

# Default post-startup command used when no workspace-specific one
ztr test '
    create_test_repo myapp
    typeset -g GROVE_DEFAULT_POST_STARTUP_COMMAND="default-cmd"
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "default-cmd"
' 'default post-startup command used as fallback'

# Workspace-specific post-startup overrides default
ztr test '
    create_test_repo myapp
    typeset -g GROVE_DEFAULT_POST_STARTUP_COMMAND="default-cmd"
    grove_post_startup_commands[myapp]="override-cmd"
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "override-cmd" &&
    ! mock_tmux_was_called_with "default-cmd"
' 'workspace-specific post-startup overrides default'

# Post-create and post-startup are chained with &&
ztr test '
    create_test_repo myapp
    grove_post_create_commands[myapp]="yarn install"
    grove_post_startup_commands[myapp]="claude"
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "yarn install" &&
    mock_tmux_was_called_with "claude" &&
    mock_tmux_was_called_with "&&"
' 'post-create and post-startup chained with &&'

# No hooks means no send-keys call
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    ! mock_tmux_was_called_with "send-keys"
' 'no hooks means no send-keys call'

# Hooks only fire on new creation, not re-attach
ztr test '
    create_test_repo myapp
    grove_post_startup_commands[myapp]="startup-cmd"
    gv myapp my-feature &>/dev/null
    MOCK_TMUX_CALLS=()
    gv myapp my-feature &>/dev/null
    ! mock_tmux_was_called_with "send-keys"
' 'hooks do not fire on re-attach to existing session'
