#!/usr/bin/env zsh
# Tests for _grove_list_all_workspaces

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Explicit workspaces included
ztr test '
    grove_workspaces[fullstack]="frontend backend"
    local result=$(_grove_list_all_workspaces)
    [[ "$result" == *fullstack* ]]
' 'explicit workspaces included'

# Implicit project dirs included
ztr test '
    create_test_repo myapp
    local result=$(_grove_list_all_workspaces)
    [[ "$result" == *myapp* ]]
' 'implicit project dirs included'

# Non-git dirs excluded
ztr test '
    mkdir -p "$GROVE_PROJECTS_DIR/notgit"
    create_test_repo realrepo
    local result=$(_grove_list_all_workspaces)
    [[ "$result" != *notgit* ]] && [[ "$result" == *realrepo* ]]
' 'non-git dirs excluded'

# No duplicates when project dir matches explicit workspace project
ztr test '
    create_test_repo frontend
    grove_workspaces[fullstack]="frontend backend"
    local result=$(_grove_list_all_workspaces)
    local -a ws_list=(${(s: :)result})
    local count=0
    local w
    for w in "${ws_list[@]}"; do
        [[ "$w" == "frontend" ]] && (( count++ ))
    done
    (( count <= 1 ))
' 'no duplicate workspace entries'

# Both explicit and implicit appear together
ztr test '
    create_test_repo solo
    grove_workspaces[multi]="a b"
    local result=$(_grove_list_all_workspaces)
    [[ "$result" == *multi* ]] && [[ "$result" == *solo* ]]
' 'both explicit and implicit appear'
