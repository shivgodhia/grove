#!/usr/bin/env zsh
# Integration tests: rollback on creation failure

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# If second worktree creation fails, first is cleaned up
ztr test '
    create_test_repo frontend
    # Do NOT create "backend" repo — it will cause worktree creation to fail
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    local rc=$?
    # Should have failed
    (( rc != 0 )) &&
    # First project worktree should be rolled back
    [[ ! -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" ]] &&
    # Workspace root should be cleaned up
    [[ ! -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature" ]]
' 'rollback cleans up on failure'

# Branch deleted during rollback
ztr test '
    create_test_repo frontend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    # Check that the branch was cleaned up from frontend
    local branches=$(git -C "$GROVE_PROJECTS_DIR/frontend" branch --list "testuser/my-feature")
    [[ -z "$branches" ]]
' 'branch deleted during rollback'
