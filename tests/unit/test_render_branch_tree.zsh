#!/usr/bin/env zsh
# Tests for _grove_tui_render_branch_tree display output
# Output format mimics gt ls: vertical │ columns for active branches,
# ─┘ or ─┴─┘ at fork points.

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

# ── Linear stack: A -> B -> C ────────────────────────────────────────────
# All at same indent, no fork connectors:
#   ○ testuser/branch-c
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

    local expected="○ testuser/branch-c
○ testuser/branch-b
○ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'linear stack: all at same indent'

# ── Deep stack: A -> B -> C -> D ────────────────────────────────────────

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
' 'deep stack: all at same indent'

# ── Fork: A has two children B and C ──────────────────────────────────────
# B continues main line, C is a side branch:
#   │ ○ testuser/branch-c
#   ○─┘ testuser/branch-b  (wrong -- b is not a fork point)
# Actually: A is the fork point with children B and C:
#   ○   testuser/branch-b
#   │ ○ testuser/branch-c
#   ○─┘ testuser/branch-a

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
    # A is fork point with two children — one continues, one branches
    [[ "$output" == *"testuser/branch-b"* ]] &&
    [[ "$output" == *"testuser/branch-c"* ]] &&
    [[ "$output" == *"testuser/branch-a"* ]] &&
    # Fork point should have ─┘ connector
    [[ "$output" == *"─┘"* ]]
' 'fork: has ─┘ connector at fork point'

# ── Stack with one side branch: A -> B -> C, A -> D ──────────────────────
# B->C continues main line (deepest chain), D branches off A:
#   ○ testuser/branch-c
#   ○ testuser/branch-b
#   │ ○ testuser/branch-d
#   ○─┘ testuser/branch-a

ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-d" --quiet
    git -C "$wt_dir" commit --allow-empty -m "d" --quiet

    local expected="○ testuser/branch-c
○ testuser/branch-b
│ ○ testuser/branch-d
○─┘ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'stack with side branch: gt ls style'

# ── Stack with side branch off middle: A -> B -> C -> D, B -> E ──────────
# D is top, E branches off B:
#   ○ testuser/branch-d
#   ○ testuser/branch-c
#   │ ○ testuser/branch-e
#   ○─┘ testuser/branch-b
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
○─┘ testuser/branch-b
○ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'side branch off middle: gt ls style'

# ── Two side branches off same node: A -> B, A -> C, A -> D ──────────────
# B continues main, C and D branch off A:
#   ○ testuser/branch-b
#   │ ○ testuser/branch-d
#   │ │ ○ testuser/branch-c
#   ○─┴─┘ testuser/branch-a

ztr test '
    create_test_repo myapp
    gv myapp branch-a &>/dev/null
    local wt_dir="$GROVE_WORKSPACES_DIR/myapp/branch-a/myapp"
    git -C "$wt_dir" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_dir" commit --allow-empty -m "b" --quiet
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-c" --quiet
    git -C "$wt_dir" commit --allow-empty -m "c" --quiet
    git -C "$wt_dir" checkout "testuser/branch-a" --quiet
    git -C "$wt_dir" checkout -b "testuser/branch-d" --quiet
    git -C "$wt_dir" commit --allow-empty -m "d" --quiet

    local expected="○ testuser/branch-b
│ ○ testuser/branch-d
│ │ ○ testuser/branch-c
○─┴─┘ testuser/branch-a"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'two side branches: gt ls style with ─┴─┘'

# ── Graphite chain with gaps ────────────────────────────────────────────
# A -> [B] -> C -> [D] -> E (B and D not in worktree)
# Should render as linear: E -> C -> A

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
    git -C "$wt_dir" checkout -b "testuser/branch-e" --quiet
    git -C "$wt_dir" commit --allow-empty -m "e" --quiet

    # Write Graphite metadata
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

    git -C "$wt_dir" checkout "testuser/branch-e" --quiet
    git -C "$wt_dir" branch -D "testuser/branch-b" --quiet 2>/dev/null
    git -C "$wt_dir" branch -D "testuser/branch-d" --quiet 2>/dev/null

    local expected="○ testuser/branch-e
○ testuser/branch-c
○ testuser/branch-a
○ main"
    local output=$(_grove_tui_render_branch_tree "$wt_dir")
    [[ "$output" == "$expected" ]]
' 'Graphite chain with gaps renders as linear stack with main root'
