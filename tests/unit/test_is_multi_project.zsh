#!/usr/bin/env zsh
# Tests for _grove_is_multi_project

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Multi-project workspace returns true
ztr test '
    grove_workspaces[fullstack]="frontend backend"
    _grove_is_multi_project fullstack
' 'multi-project workspace returns true'

# Single-project explicit workspace returns false
ztr test '
    grove_workspaces[solo]="myapp"
    ! _grove_is_multi_project solo
' 'single-project explicit workspace returns false'

# Implicit single-project workspace returns false
ztr test '
    create_test_repo myapp
    ! _grove_is_multi_project myapp
' 'implicit single-project workspace returns false'

# Unknown workspace returns error
ztr test '
    ! _grove_is_multi_project nonexistent 2>/dev/null
' 'unknown workspace returns error'

# Three-project workspace returns true
ztr test '
    grove_workspaces[big]="alpha beta gamma"
    _grove_is_multi_project big
' 'three-project workspace returns true'
