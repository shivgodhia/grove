#!/usr/bin/env zsh
# Tests for _grove_validate_workspace_config

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Conflicting workspace name (same as project dir) is removed
ztr test '
    create_test_repo myapp
    grove_workspaces[myapp]="frontend backend"
    _grove_validate_workspace_config 2>/dev/null
    [[ -z "${grove_workspaces[myapp]+x}" ]]
' 'conflicting workspace name removed'

# Non-conflicting workspace is preserved
ztr test '
    create_test_repo frontend
    grove_workspaces[fullstack]="frontend backend"
    _grove_validate_workspace_config 2>/dev/null
    [[ -n "${grove_workspaces[fullstack]+x}" ]]
' 'non-conflicting workspace preserved'

# Multiple conflicts: all conflicting ones removed, others kept
ztr test '
    create_test_repo alpha
    create_test_repo beta
    grove_workspaces[alpha]="x y"
    grove_workspaces[beta]="x y"
    grove_workspaces[gamma]="alpha beta"
    _grove_validate_workspace_config 2>/dev/null
    [[ -z "${grove_workspaces[alpha]+x}" ]] &&
    [[ -z "${grove_workspaces[beta]+x}" ]] &&
    [[ -n "${grove_workspaces[gamma]+x}" ]]
' 'multiple conflicts all removed, non-conflicting kept'

# No project dirs means no conflicts
ztr test '
    grove_workspaces[myws]="proj1 proj2"
    _grove_validate_workspace_config 2>/dev/null
    [[ -n "${grove_workspaces[myws]+x}" ]]
' 'no project dirs means no conflicts'
