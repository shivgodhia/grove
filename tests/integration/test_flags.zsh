#!/usr/bin/env zsh
# Integration tests: --help, --home, and TMUX switch-client

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# --help returns 0
ztr test '
    gv --help &>/dev/null
    (( $? == 0 ))
' '--help returns exit code 0'

# --help produces output
ztr test '
    local output=$(gv --help 2>&1)
    [[ -n "$output" ]] && [[ "$output" == *"Grove"* ]]
' '--help produces output containing Grove'

# --help shows usage sections
ztr test '
    local output=$(gv --help 2>&1)
    [[ "$output" == *"QUICK START"* ]] &&
    [[ "$output" == *"CONFIGURATION"* ]]
' '--help shows usage sections'

# --home changes to projects dir
ztr test '
    local before="$PWD"
    gv --home
    [[ "$PWD" == "$GROVE_PROJECTS_DIR" ]]
    cd "$before"
' '--home changes to projects dir'

# --home returns 0
ztr test '
    local before="$PWD"
    gv --home &>/dev/null
    local rc=$?
    cd "$before"
    (( rc == 0 ))
' '--home returns exit code 0'

# No args shows usage and returns error
ztr test '
    gv &>/dev/null
    (( $? != 0 ))
' 'no args returns error'

# TMUX set causes switch-client instead of attach-session
ztr test '
    create_test_repo myapp
    typeset -g TMUX="/tmp/tmux-test/default,12345,0"
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "switch-client" &&
    ! mock_tmux_was_called_with "attach-session"
' 'TMUX set causes switch-client instead of attach'

# TMUX unset causes attach-session
ztr test '
    create_test_repo myapp
    unset TMUX
    gv myapp my-feature &>/dev/null
    mock_tmux_was_called_with "attach-session" &&
    ! mock_tmux_was_called_with "switch-client"
' 'TMUX unset causes attach-session'
