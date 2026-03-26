#!/usr/bin/env zsh
# Tests for _grove_tui_render_branch_tree display output
# These tests create worktrees with specific branch topologies and verify
# the tree renderer produces the correct visual output.
#
# Output format: each line is "prefix|branch_name" where prefix contains
# the tree-drawing characters (○, │, etc.)

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# ── Single branch ──────────────────────────────────────────────────────────

ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "○ testuser/my-feature" ]]
' 'single branch renders plain'

# ── Linear stack: A -> B -> C (no forks) ────────────────────────────────────
# A linear stack should stay at the SAME indent level, like gt co:
#   ○ branch-c
#   ○ branch-b
#   ○ branch-a

ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet

    local expected="○ testuser/branch-c
○ testuser/branch-b
○ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'linear stack: all branches at same indent'

# ── Deep stack: A -> B -> C -> D ────────────────────────────────────────────
# Same as linear — all at same indent:
#   ○ branch-d
#   ○ branch-c
#   ○ branch-b
#   ○ branch-a

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

    local expected="○ testuser/branch-d
○ testuser/branch-c
○ testuser/branch-b
○ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'deep stack: all branches at same indent'

# ── Fork: A -> B and A -> C ────────────────────────────────────────────────
# When A has two children, the second child branches off:
#   ○ testuser/branch-b
#   │ ○ testuser/branch-c
#   ○ testuser/branch-a

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
    # Both B and C should be shown as children of A
    # One continues the main line, the other branches off with │
    [[ "$output" == *"testuser/branch-b"* ]] &&
    [[ "$output" == *"testuser/branch-c"* ]] &&
    [[ "$output" == *"testuser/branch-a"* ]] &&
    # At least one line should have │ (the side branch)
    [[ "$output" == *"│"* ]]
' 'fork: side branch indented with │'

# ── Stack with side branch: A -> B -> C, B -> D ──────────────────────────
# C continues the main line, D branches off B:
#   ○ testuser/branch-c
#   │ ○ testuser/branch-d
#   ○ testuser/branch-b
#   ○ testuser/branch-a

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

    local expected="○ testuser/branch-c
│ ○ testuser/branch-d
○ testuser/branch-b
○ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'stack with side branch: side branch indented'

# ── Stack with deeper side branch: A -> B -> C -> D, B -> E ──────────────
# D continues the main line from C from B, E branches off B:
#   ○ testuser/branch-d
#   ○ testuser/branch-c
#   │ ○ testuser/branch-e
#   ○ testuser/branch-b
#   ○ testuser/branch-a

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
    git -C "$wt_dir" checkout "testuser/branch-b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-e" --quiet
    git -C "$wt_dir" commit --allow-empty -m "e" --quiet

    local expected="○ testuser/branch-d
○ testuser/branch-c
│ ○ testuser/branch-e
○ testuser/branch-b
○ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'deep stack with side branch off middle'
