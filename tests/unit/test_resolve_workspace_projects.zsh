#!/usr/bin/env zsh
# Tests for _grove_resolve_workspace_projects

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Explicit workspace returns project list
ztr test '
    grove_workspaces[fullstack]="frontend backend"
    local result=$(_grove_resolve_workspace_projects fullstack)
    [[ "$result" == "frontend backend" ]]
' 'explicit workspace returns project list'

# Implicit workspace (project dir with .git)
ztr test '
    create_test_repo myapp
    local result=$(_grove_resolve_workspace_projects myapp)
    [[ "$result" == "myapp" ]]
' 'implicit workspace from git project dir'

# Unknown workspace returns error
ztr test '
    _grove_resolve_workspace_projects nonexistent 2>/dev/null
    (( $? != 0 ))
' 'unknown workspace returns error'

# Empty project list returns error
ztr test '
    grove_workspaces[empty]=""
    _grove_resolve_workspace_projects empty 2>/dev/null
    (( $? != 0 ))
' 'empty project list returns error'

# Explicit workspace takes priority (even if project dir exists with same name)
# Note: _grove_validate_workspace_config would normally remove this, but we test the raw function
ztr test '
    create_test_repo myapp
    grove_workspaces[myapp]="frontend backend"
    local result=$(_grove_resolve_workspace_projects myapp)
    [[ "$result" == "frontend backend" ]]
' 'explicit workspace takes priority over implicit'
