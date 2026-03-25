#!/usr/bin/env zsh
# Integration tests: gv --rm

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Removes worktree directory
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv --rm myapp my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/my-feature" ]]
' 'removes worktree directory'

# Deletes local branch
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv --rm myapp my-feature &>/dev/null
    local branches=$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/my-feature")
    [[ -z "$branches" ]]
' 'deletes local branch'

# Kills tmux session
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    MOCK_TMUX_CALLS=()
    gv --rm myapp my-feature &>/dev/null
    mock_tmux_was_called_with "kill-session"
' 'kills tmux session'

# Cleans up empty parent dir
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    gv --rm myapp my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp" ]]
' 'cleans up empty parent dir'

# Non-existent workspace returns error
ztr test '
    gv --rm nonexistent blah &>/dev/null
    (( $? != 0 ))
' 'removing non-existent workspace returns error'

# Parent dir preserved when other instances exist
ztr test '
    create_test_repo myapp
    gv myapp feature1 &>/dev/null
    gv myapp feature2 &>/dev/null
    gv --rm myapp feature1 &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/myapp" ]] &&
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/feature2" ]] &&
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/feature1" ]]
' 'parent dir preserved when other instances exist'

# Multi-project removal cleans all worktrees
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    gv --rm fullstack my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature" ]]
' 'multi-project removal cleans all worktrees'

# rm with multiple branches: HEAD on branch-c (last created)
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    gv --rm myapp branch-a &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-a")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-b")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-c")" ]]
' 'rm deletes all branches when HEAD on last created branch'

# rm with multiple branches: HEAD on branch-b (middle)
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" checkout "testuser/branch-b" --quiet
    gv --rm myapp branch-a &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-a")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-b")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-c")" ]]
' 'rm deletes all branches when HEAD on middle branch'

# rm with multiple branches: HEAD on branch-a (original)
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    gv --rm myapp branch-a &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-a")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-b")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-c")" ]]
' 'rm deletes all branches when HEAD back on original branch'

# rm only deletes branches from this worktree, not branches from other worktrees
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    gv myapp branch-1 &>/dev/null
    local wt_a="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    # Create branch-b inside branch-a worktree
    git -C "$wt_a" checkout -b "testuser/branch-b" --quiet
    gv --rm myapp branch-a &>/dev/null
    # branch-a workspace should be gone
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/branch-a" ]] &&
    # branches from branch-a worktree should be deleted
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-a")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-b")" ]] &&
    # branch-1 should survive — it was never checked out in branch-a worktree
    [[ -n "$(git -C "$GROVE_PROJECTS_DIR/myapp" branch --list "testuser/branch-1")" ]] &&
    # branch-1 worktree should be unaffected
    [[ -d "$GROVE_WORKSPACES_DIR/myapp/branch-1/myapp" ]]
' 'rm does not delete branches checked out in other worktrees'

# Multi-project: rm deletes reflog branches from each project independently
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack branch-a &>/dev/null
    local wt_fe="$GROVE_WORKSPACES_DIR/fullstack/branch-a/frontend"
    local wt_be="$GROVE_WORKSPACES_DIR/fullstack/branch-a/backend"
    # Create branch-b in frontend only, branch-c in backend only
    git -C "$wt_fe" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_be" checkout -b "testuser/branch-c" --quiet
    gv --rm fullstack branch-a &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/fullstack/branch-a" ]] &&
    # frontend: both branch-a and branch-b deleted
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/frontend" branch --list "testuser/branch-a")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/frontend" branch --list "testuser/branch-b")" ]] &&
    # backend: both branch-a and branch-c deleted
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/backend" branch --list "testuser/branch-a")" ]] &&
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/backend" branch --list "testuser/branch-c")" ]] &&
    # frontend should NOT have branch-c (it was never there)
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/frontend" branch --list "testuser/branch-c")" ]] &&
    # backend should NOT have branch-b (it was never there)
    [[ -z "$(git -C "$GROVE_PROJECTS_DIR/backend" branch --list "testuser/branch-b")" ]]
' 'multi-project rm deletes reflog branches per project independently'
