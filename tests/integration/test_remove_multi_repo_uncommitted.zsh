#!/usr/bin/env zsh
# Integration tests: gv --rm with uncommitted changes in multi-repo workspaces
# Tests that removal without --force is atomic: either all repos are cleaned up
# properly, or none are (no partial deletion).

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# ── Dirty second repo: uncommitted change in B (alphabetically second) ───────

# When the dirty worktree is in the second repo, the first repo's worktree
# gets removed but the second fails. rm -rf then nukes the workspace dir,
# leaving an orphaned worktree registration in git for the second repo.
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null

    # Dirty only backend (alphabetically second when globbed)
    echo "dirty" > "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend/uncommitted.txt"
    git -C "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend" add uncommitted.txt

    gv --rm fullstack my-feature &>/dev/null

    # The command should fail
    local exit_code=$?
    (( exit_code != 0 )) || return 1

    # ATOMICITY CHECK: since removal failed, the workspace dir should still
    # exist with both worktrees intact (no partial deletion)
    [[ -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" ]] &&
    [[ -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend" ]]
' 'multi-repo: dirty second repo — removal is atomic (no partial deletion)'

# When removal fails, worktrees should still be registered in git
# (not orphaned by rm -rf)
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null

    # Dirty only backend
    echo "dirty" > "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend/uncommitted.txt"
    git -C "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend" add uncommitted.txt

    gv --rm fullstack my-feature &>/dev/null

    # Both worktrees should still be properly registered in git
    local frontend_wt=$(git -C "$GROVE_PROJECTS_DIR/frontend" worktree list --porcelain | grep -c "worktree.*my-feature")
    local backend_wt=$(git -C "$GROVE_PROJECTS_DIR/backend" worktree list --porcelain | grep -c "worktree.*my-feature")
    (( frontend_wt > 0 )) && (( backend_wt > 0 ))
' 'multi-repo: dirty second repo — no orphaned worktree registrations'

# ── Dirty first repo: uncommitted change in A (alphabetically first) ─────────

# When the dirty worktree is in the first repo, it fails immediately but the
# second repo may still get its worktree removed, causing partial cleanup.
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null

    # Dirty only frontend (alphabetically first when globbed — fails first)
    echo "dirty" > "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend/uncommitted.txt"
    git -C "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" add uncommitted.txt

    gv --rm fullstack my-feature &>/dev/null

    # The command should fail
    local exit_code=$?
    (( exit_code != 0 )) || return 1

    # ATOMICITY CHECK: since removal failed, the workspace dir should still
    # exist with both worktrees intact (no partial deletion)
    [[ -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" ]] &&
    [[ -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend" ]]
' 'multi-repo: dirty first repo — removal is atomic (no partial deletion)'

# When the first repo is dirty, the second repo's branch should not be deleted
# (since the overall operation failed)
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null

    # Dirty only frontend
    echo "dirty" > "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend/uncommitted.txt"
    git -C "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" add uncommitted.txt

    gv --rm fullstack my-feature &>/dev/null

    # Both branches should still exist since the operation failed
    local fe_branch=$(git -C "$GROVE_PROJECTS_DIR/frontend" branch --list "testuser/my-feature")
    local be_branch=$(git -C "$GROVE_PROJECTS_DIR/backend" branch --list "testuser/my-feature")
    [[ -n "$fe_branch" ]] && [[ -n "$be_branch" ]]
' 'multi-repo: dirty first repo — no branches deleted on failed removal'
