#!/usr/bin/env zsh
# Integration tests: gv --list

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Shows single-repo section
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local output=$(gv --list 2>&1)
    [[ "$output" == *"Single-Repo Workspaces"* ]]
' 'shows single-repo workspaces section'

# Shows instance name and branch
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local output=$(gv --list 2>&1)
    [[ "$output" == *"my-feature"* ]] && [[ "$output" == *"testuser/my-feature"* ]]
' 'shows instance name and branch'

# Shows tmux status when session exists
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    # Session was created by gv, mock tracks it
    local output=$(gv --list 2>&1)
    [[ "$output" == *"[tmux:"* ]]
' 'shows tmux status when session exists'

# Multi-repo section shown for multi-project workspaces
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    local output=$(gv --list 2>&1)
    [[ "$output" == *"Multi-Repo Workspaces"* ]]
' 'shows multi-repo workspaces section'

# Shows project list for multi-project workspace
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    local output=$(gv --list 2>&1)
    [[ "$output" == *frontend* ]] && [[ "$output" == *backend* ]]
' 'shows project list for multi-project workspace'
