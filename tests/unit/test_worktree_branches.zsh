#!/usr/bin/env zsh
# Tests for _grove_worktree_branches and _grove_worktree_branch_parents

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# ── _grove_worktree_branches ────────────────────────────────────────────────

# Single branch worktree returns just that branch
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    local branches=$(_grove_worktree_branches "$wt_dir")
    [[ "$branches" == *"testuser/my-feature"* ]]
' 'single branch worktree returns HEAD branch'

# Multiple branches returns all of them
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    local branches=$(_grove_worktree_branches "$wt_dir")
    [[ "$branches" == *"testuser/my-feature"* ]] &&
    [[ "$branches" == *"testuser/branch-b"* ]] &&
    [[ "$branches" == *"testuser/branch-c"* ]]
' 'multiple branches all returned'

# Base branch (main) is filtered out
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    local branches=$(_grove_worktree_branches "$wt_dir")
    [[ "$branches" != *"main"* ]]
' 'base branch filtered out'

# HEAD literal is filtered out
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    local branches=$(_grove_worktree_branches "$wt_dir")
    local line
    while read -r line; do
        [[ "$line" == "HEAD" ]] && return 1
    done <<< "$branches"
    return 0
' 'HEAD literal filtered out'

# ── _grove_worktree_branch_parents ──────────────────────────────────────────

# Linear stack: A -> B -> C (C created from B, B created from A)
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    local output=$(_grove_worktree_branch_parents "$wt_dir")
    # branch-c parent should be branch-b
    [[ "$output" == *"testuser/branch-c|testuser/branch-b"* ]] &&
    # branch-b parent should be branch-a
    [[ "$output" == *"testuser/branch-b|testuser/branch-a"* ]] &&
    # branch-a is root (parent is main, which is filtered)
    [[ "$output" == *"testuser/branch-a|"* ]]
' 'linear stack: C->B->A parentage correct'

# Forked branches: A -> B and A -> C (both created from A)
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    local output=$(_grove_worktree_branch_parents "$wt_dir")
    # Both B and C should have A as parent
    [[ "$output" == *"testuser/branch-b|testuser/branch-a"* ]] &&
    [[ "$output" == *"testuser/branch-c|testuser/branch-a"* ]]
' 'forked branches: B and C both parented on A'

# Root branch has empty parent
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    local output=$(_grove_worktree_branch_parents "$wt_dir")
    # my-feature was created from main, which is filtered → empty parent
    local parent_line
    while read -r parent_line; do
        if [[ "$parent_line" == "testuser/my-feature|"* ]]; then
            local parent="${parent_line#*|}"
            [[ -z "$parent" ]] && return 0
        fi
    done <<< "$output"
    return 1
' 'root branch has empty parent'

# Deep stack: A -> B -> C -> D
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-d" --quiet
    git -C "$wt_dir" commit --allow-empty -m "d" --quiet
    local output=$(_grove_worktree_branch_parents "$wt_dir")
    [[ "$output" == *"testuser/branch-d|testuser/branch-c"* ]] &&
    [[ "$output" == *"testuser/branch-c|testuser/branch-b"* ]] &&
    [[ "$output" == *"testuser/branch-b|testuser/branch-a"* ]] &&
    [[ "$output" == *"testuser/branch-a|"* ]]
' 'deep stack: D->C->B->A parentage correct'

# Switching back and forth doesnt break parentage
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    # Switch back to A, then back to B — should not change parentage
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    git -C "$wt_dir" checkout "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    local output=$(_grove_worktree_branch_parents "$wt_dir")
    # B parent is still A (not changed by switching)
    [[ "$output" == *"testuser/branch-b|testuser/branch-a"* ]] &&
    # C parent is B (created from B)
    [[ "$output" == *"testuser/branch-c|testuser/branch-b"* ]]
' 'switching back and forth preserves original parentage'

# Graphite parent chain with gaps: A -> B -> C -> D -> E in Graphite metadata,
# but only A, C, E are in the worktree. B and D exist in other worktrees.
# Should resolve: E -> C (skipping D), C -> A (skipping B)
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    # Create all branches in the worktree first
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-d" --quiet
    git -C "$wt_dir" commit --allow-empty -m "d" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-e" --quiet
    git -C "$wt_dir" commit --allow-empty -m "e" --quiet

    # Write Graphite metadata: A -> B -> C -> D -> E
    local _write_gt() {
        local b="$1" p="$2"
        local blob=$(echo "{\"parentBranchName\": \"$p\"}" | git -C "$wt_dir" hash-object -w --stdin)
        git -C "$wt_dir" update-ref "refs/branch-metadata/$b" "$blob"
    }
    _write_gt "testuser/branch-a" "main"
    _write_gt "testuser/branch-b" "testuser/branch-a"
    _write_gt "testuser/branch-c" "testuser/branch-b"
    _write_gt "testuser/branch-d" "testuser/branch-c"
    _write_gt "testuser/branch-e" "testuser/branch-d"

    # Now delete B and D from the worktree (simulate them being in other worktrees)
    git -C "$wt_dir" checkout "testuser/branch-e" --quiet
    git -C "$wt_dir" branch -D "testuser/branch-b" --quiet 2>/dev/null
    git -C "$wt_dir" branch -D "testuser/branch-d" --quiet 2>/dev/null

    local output=$(_grove_worktree_branch_parents "$wt_dir")
    # E parent should be C (nearest ancestor in set, skipping D)
    [[ "$output" == *"testuser/branch-e|testuser/branch-c"* ]] &&
    # C parent should be A (nearest ancestor in set, skipping B)
    [[ "$output" == *"testuser/branch-c|testuser/branch-a"* ]] &&
    # A parent is main (via Graphite metadata)
    [[ "$output" == *"testuser/branch-a|main"* ]] &&
    # main is the virtual root
    [[ "$output" == *"main|"* ]]
' 'Graphite parent chain with gaps resolves to nearest ancestor in set'
