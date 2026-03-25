#!/usr/bin/env zsh
# Integration tests: detecting branch already exists in another worktree

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# When branch-b is created inside branch-a's worktree via git checkout -b,
# running gv myrepo branch-b should redirect to the branch-a workspace
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    # Simulate: user creates branch-b inside the worktree
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    MOCK_TMUX_CALLS=()
    gv myapp branch-b &>/dev/null
    # Should NOT create a new workspace directory
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-b" ]]
' 'redirects to existing worktree instead of creating new workspace'

# Should attach to the existing tmux session, not create a new one
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    MOCK_TMUX_CALLS=()
    gv myapp branch-b &>/dev/null
    # Should attach to branch-a session, not create new
    mock_tmux_was_called_with "grove/myapp/branch-a"
' 'attaches to the worktree session containing the branch'

# Should print a helpful message about which workspace the branch is in
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    local output=$(gv myapp branch-b 2>&1)
    [[ "$output" == *"already exists in workspace"* ]] &&
    [[ "$output" == *"myapp/branch-a"* ]]
' 'prints message about which workspace contains the branch'

# Return 0 (success) when redirecting
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    gv myapp branch-b &>/dev/null
    (( $? == 0 ))
' 'returns success when redirecting to existing worktree'

# Multi-project: no redirect — should fail, not silently redirect
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/fullstack/branch-a/frontend"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    gv fullstack branch-b &>/dev/null
    # Should fail (branch already exists in git), not redirect
    (( $? != 0 ))
' 'multi-project: does not redirect when branch exists in worktree'

# Single-repo: does not redirect across different workspaces
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    # Create single-repo backend/branch-a
    gv backend branch-a &>/dev/null
    # Request fullstack/branch-a — should not redirect to backend/branch-a
    gv fullstack branch-a &>/dev/null
    local rc=$?
    # Should fail (branch exists in backend repo), not redirect across workspaces
    (( rc != 0 ))
' 'does not redirect across different workspaces'

# When user provides the full prefixed branch name (with slash),
# it should still find the existing workspace
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]]
    # Now request same workspace using full prefix: testuser/branch-a
    MOCK_TMUX_CALLS=()
    gv myapp testuser/branch-a &>/dev/null
    # Should NOT create a new "testuser-branch-a" directory
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/testuser-branch-a" ]]
' 'strips branch prefix from name so slash does not create new directory'

# Redirect should work when user provides full prefixed branch name
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    MOCK_TMUX_CALLS=()
    # Use full prefixed name — should still redirect
    gv myapp testuser/branch-b &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/testuser-branch-b" ]] &&
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-b" ]]
' 'redirect works when user provides full prefixed branch name with slash'

# --rm should work with full prefixed branch name
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]]
    gv --rm testuser/branch-a 2>/dev/null || gv --rm myapp testuser/branch-a &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]]
' 'rm with full prefixed branch name removes correct workspace'

# When a branch with a different prefix (e.g. shiv/branch-b) is created
# inside a worktree, searching by that exact name should redirect
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    # Create a branch with a non-matching prefix (not testuser/)
    git -C "$wt_dir" checkout -b "shiv/branch-b" --quiet
    MOCK_TMUX_CALLS=()
    gv myapp shiv/branch-b &>/dev/null
    # Should redirect, not create a new workspace
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/shiv-branch-b" ]]
' 'redirect works for branches with arbitrary slash prefixes'
