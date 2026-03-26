#!/usr/bin/env zsh
# Tests for _grove_tui_render_branch_tree display output
# These tests create worktrees with specific branch topologies and verify
# the tree renderer produces the correct visual output (without PR data).

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Helper: render tree for a worktree dir, stripping ANSI and PR lines
# Outputs just the branch display lines (with indent/markers)
_test_render_tree() {
    local wt_dir="$1"
    _grove_tui_render_branch_tree "$wt_dir" | while read -r line; do
        local depth="${line%%|*}"
        local name="${line#*|}"
        # Build indent: for a linear stack, depth stays the same
        # For now just output depth and name for assertion
        echo "${depth}|${name}"
    done
}

# ── Linear stack: A -> B -> C (no forks) ────────────────────────────────────

# Linear stack should show all at depths forming a chain
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet

    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    # C is deepest (child of B), B is child of A, A is root
    # Should be: C at depth 2, B at depth 1, A at depth 0
    [[ "$output" == *"2|testuser/branch-c"* ]] &&
    [[ "$output" == *"1|testuser/branch-b"* ]] &&
    [[ "$output" == *"0|testuser/branch-a"* ]]
' 'linear stack depths: C=2, B=1, A=0'

# ── Fork: A -> B and A -> C ────────────────────────────────────────────────

# Forked branches should both be children of A
ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet

    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    # B and C are both at depth 1 (children of A), A at depth 0
    [[ "$output" == *"1|testuser/branch-b"* ]] &&
    [[ "$output" == *"1|testuser/branch-c"* ]] &&
    [[ "$output" == *"0|testuser/branch-a"* ]]
' 'fork: B and C both at depth 1, A at depth 0'

# ── Deep stack: A -> B -> C -> D ────────────────────────────────────────────

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

    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == *"3|testuser/branch-d"* ]] &&
    [[ "$output" == *"2|testuser/branch-c"* ]] &&
    [[ "$output" == *"1|testuser/branch-b"* ]] &&
    [[ "$output" == *"0|testuser/branch-a"* ]]
' 'deep stack: D=3, C=2, B=1, A=0'

# ── Stack with a side branch: A -> B -> C, B -> D ──────────────────────────

ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    git -C "$wt_dir" checkout "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-d" --quiet
    git -C "$wt_dir" commit --allow-empty -m "d" --quiet

    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    # C and D are both children of B (depth 2), B child of A (depth 1), A root (depth 0)
    [[ "$output" == *"2|testuser/branch-c"* ]] &&
    [[ "$output" == *"2|testuser/branch-d"* ]] &&
    [[ "$output" == *"1|testuser/branch-b"* ]] &&
    [[ "$output" == *"0|testuser/branch-a"* ]]
' 'stack with side branch: C=2, D=2, B=1, A=0'

# ── Single branch ──────────────────────────────────────────────────────────

ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "0|testuser/my-feature" ]]
' 'single branch at depth 0'
