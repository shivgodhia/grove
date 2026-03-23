#!/usr/bin/env zsh
# Tests for _grove_annotated_workspaces

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Multi-project workspace shows project list suffix
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    local output=$(_grove_annotated_workspaces)
    [[ "$output" == *"fullstack (frontend, backend)"* ]]
' 'multi-project workspace shows project list suffix'

# Implicit workspace shows plain name (no suffix)
ztr test '
    create_test_repo myapp
    local output=$(_grove_annotated_workspaces)
    [[ "$output" == *myapp* ]] && [[ "$output" != *"myapp ("* ]]
' 'implicit workspace shows plain name without suffix'

# Both implicit and explicit appear
ztr test '
    create_test_repo solo
    grove_workspaces[multi]="a b"
    local output=$(_grove_annotated_workspaces)
    [[ "$output" == *solo* ]] && [[ "$output" == *"multi (a, b)"* ]]
' 'both implicit and explicit workspaces appear'
