#!/usr/bin/env zsh
# Tests for _grove_resolve_branch_name

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# No conflict: returns prefix/name
ztr test '
    create_test_repo myapp
    local result=$(_grove_resolve_branch_name myapp "new-feature")
    [[ "$result" == "testuser/new-feature" ]]
' 'no conflict returns prefixed name'

# Conflict on remote: returns date-prefixed name
ztr test '
    create_test_repo myapp
    create_remote_branch myapp "testuser/existing"
    local result=$(_grove_resolve_branch_name myapp "existing")
    [[ "$result" == testuser/[0-9][0-9][0-9][0-9][0-9][0-9]-existing ]]
' 'conflict returns date-prefixed name'

# Multi-project: conflict on any repo triggers date prefix
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    create_remote_branch backend "testuser/shared"
    local result=$(_grove_resolve_branch_name fullstack "shared")
    [[ "$result" == testuser/[0-9][0-9][0-9][0-9][0-9][0-9]-shared ]]
' 'multi-project conflict on any repo triggers date prefix'

# Multi-project: no conflict on any repo returns plain prefix
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    local result=$(_grove_resolve_branch_name fullstack "brand-new")
    [[ "$result" == "testuser/brand-new" ]]
' 'multi-project no conflict returns prefixed name'
