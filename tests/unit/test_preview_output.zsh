#!/usr/bin/env zsh
# Integration tests for _grove_tui_preview output
# Tests the full rendered output for variable leaks and formatting

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Helper: render preview for a workspace/instance and check for variable leaks
_test_preview() {
    local ws="$1" inst="$2"
    # Simulate an fzf selection line (tab-separated: [ws] \t tmux \t inst \t branch)
    local fake_line="[${ws}]"$'\t'"  ○ "$'\t'"${inst}"$'\t'"testuser/${inst}"
    _grove_tui_preview "$fake_line" 2>/dev/null
}

# No variable leaks in simple preview
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    local output=$(_test_preview myapp my-feature)
    # Should not contain any variable assignment leaks
    [[ "$output" != *"tree_prefix="* ]] &&
    [[ "$output" != *"tree_bars="* ]] &&
    [[ "$output" != *"pad_count="* ]] &&
    [[ "$output" != *"padding="* ]] &&
    [[ "$output" != *"prefix_part="* ]] &&
    [[ "$output" != *"colored_prefix="* ]] &&
    [[ "$output" != *"max_prefix_len="* ]] &&
    [[ "$output" != *"pr_pad="* ]] &&
    [[ "$output" != *"bars_pad="* ]] &&
    [[ "$output" != *"p=0"* ]]
' 'no variable leaks in preview output'

# Preview with stacked branches has no leaks
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

    local output=$(_test_preview myapp branch-a)
    # No variable leaks
    [[ "$output" != *"tree_prefix="* ]] &&
    [[ "$output" != *"pad_count="* ]] &&
    [[ "$output" != *"p=0"* ]] &&
    # Branch names should appear
    [[ "$output" == *"testuser/branch-a"* ]] &&
    [[ "$output" == *"testuser/branch-b"* ]] &&
    [[ "$output" == *"testuser/branch-c"* ]] &&
    [[ "$output" == *"testuser/branch-d"* ]]
' 'stacked branches preview has no leaks and shows all branches'

# Multi-project preview has no leaks
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    local wt_fe="$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend"
    local wt_be="$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend"
    git -C "$wt_fe" checkout -b "testuser/branch-b" --quiet
    git -C "$wt_fe" commit --allow-empty -m "b" --quiet

    local output=$(_test_preview fullstack my-feature)
    [[ "$output" != *"tree_prefix="* ]] &&
    [[ "$output" != *"pad_count="* ]] &&
    [[ "$output" != *"p=0"* ]] &&
    [[ "$output" == *"frontend"* ]] &&
    [[ "$output" == *"backend"* ]]
' 'multi-project preview has no leaks'
