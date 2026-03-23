#!/usr/bin/env zsh
# Test helpers for grove.zsh — tmux mock, temp repo builders, setup/teardown

# ── tmux mock ────────────────────────────────────────────────────────────────
# grove.zsh uses bare `tmux` (not `command tmux`), so this function intercepts
# all tmux calls during tests.

typeset -ga MOCK_TMUX_CALLS=()
typeset -gA MOCK_TMUX_SESSIONS=()

tmux() {
    MOCK_TMUX_CALLS+=("$*")
    case "$1" in
        has-session)
            local idx=${@[(i)-t]}
            local sn=${@[$((idx+1))]}
            [[ -n ${MOCK_TMUX_SESSIONS[$sn]+x} ]] && return 0 || return 1
            ;;
        new-session)
            local idx=${@[(i)-s]}
            local sn=${@[$((idx+1))]}
            MOCK_TMUX_SESSIONS[$sn]="1"
            return 0
            ;;
        kill-session)
            local idx=${@[(i)-t]}
            local sn=${@[$((idx+1))]}
            unset "MOCK_TMUX_SESSIONS[$sn]"
            return 0
            ;;
        switch-client|attach-session|rename-window|send-keys)
            return 0
            ;;
    esac
}

# ── Test lifecycle ───────────────────────────────────────────────────────────

# One-time init: copy grove.zsh to isolated dir (avoids sourcing real grove.local.zsh),
# then source it with test defaults.
grove_test_init() {
    GROVE_TEST_BASE=$(mktemp -d)

    # Copy grove.zsh to isolated dir so it won't find grove.local.zsh
    cp "$GROVE_SCRIPT_PATH" "$GROVE_TEST_BASE/grove.zsh"

    # Set config defaults BEFORE sourcing (so source-time validation uses test dirs)
    GROVE_PROJECTS_DIR="$GROVE_TEST_BASE/projects"
    GROVE_WORKSPACES_DIR="$GROVE_TEST_BASE/workspaces"
    GROVE_BASE_BRANCH="origin/main"
    GROVE_BRANCH_PREFIX="testuser"
    GROVE_DEFAULT_POST_STARTUP_COMMAND=""

    mkdir -p "$GROVE_PROJECTS_DIR" "$GROVE_WORKSPACES_DIR"

    # Stub interactive-only zsh builtins that grove.zsh uses for tab completion
    # These aren't available in non-interactive script mode
    (( $+functions[compdef] )) || compdef() { :; }
    bindkey() { :; }
    # zle is a builtin but only works in interactive mode — override with function
    zle() { :; }

    # Source grove.zsh from the isolated copy
    source "$GROVE_TEST_BASE/grove.zsh"
}

# Per-test reset: clean state for each test
# Note: all variables must be explicitly global (typeset -g) because ztr's
# setup/teardown functions run inside emulate -LR zsh scopes.
grove_test_setup() {
    typeset -g TEST_TMPDIR=$(mktemp -d)
    typeset -g GROVE_PROJECTS_DIR="$TEST_TMPDIR/projects"
    typeset -g GROVE_WORKSPACES_DIR="$TEST_TMPDIR/workspaces"
    typeset -g GROVE_BASE_BRANCH="origin/main"
    typeset -g GROVE_BRANCH_PREFIX="testuser"
    typeset -g GROVE_DEFAULT_POST_STARTUP_COMMAND=""

    # Clear config arrays
    typeset -gA grove_workspaces=()
    typeset -gA grove_post_create_commands=()
    typeset -gA grove_post_startup_commands=()

    # Clear mock state
    typeset -ga MOCK_TMUX_CALLS=()
    typeset -gA MOCK_TMUX_SESSIONS=()

    # Unset TMUX to avoid branch in attach vs switch logic
    unset TMUX

    mkdir -p "$GROVE_PROJECTS_DIR" "$GROVE_WORKSPACES_DIR"
}

# Per-test cleanup
grove_test_teardown() {
    if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# ── Git repo helpers ─────────────────────────────────────────────────────────

# Create a test git repo with a bare remote acting as "origin".
# Usage: create_test_repo <name>
# Creates:
#   $GROVE_PROJECTS_DIR/<name>/         (working repo)
#   $TEST_TMPDIR/remotes/<name>.git     (bare "origin")
create_test_repo() {
    local name="$1"
    local repo_dir="$GROVE_PROJECTS_DIR/$name"
    local bare_dir="$TEST_TMPDIR/remotes/${name}.git"

    mkdir -p "$repo_dir"
    git -C "$repo_dir" init -b main --quiet
    git -C "$repo_dir" config user.email "test@test.com"
    git -C "$repo_dir" config user.name "Test"
    git -C "$repo_dir" commit --allow-empty -m "initial" --quiet

    # Create bare remote
    git clone --bare --quiet "$repo_dir" "$bare_dir" 2>/dev/null
    git -C "$repo_dir" remote add origin "$bare_dir"
    git -C "$repo_dir" fetch origin --quiet
}

# Push a branch to a test repo's bare remote.
# Usage: create_remote_branch <repo_name> <branch_name>
create_remote_branch() {
    local repo_name="$1" branch_name="$2"
    local repo_dir="$GROVE_PROJECTS_DIR/$repo_name"
    local bare_dir="$TEST_TMPDIR/remotes/${repo_name}.git"

    git -C "$repo_dir" checkout -b "$branch_name" --quiet
    git -C "$repo_dir" commit --allow-empty -m "branch: $branch_name" --quiet
    git -C "$repo_dir" push origin "$branch_name" --quiet 2>/dev/null
    git -C "$repo_dir" checkout main --quiet
    # Delete local branch so it only exists on remote (like a real remote branch)
    git -C "$repo_dir" branch -D "$branch_name" --quiet
    git -C "$repo_dir" fetch origin --quiet
}

# ── Assertion helpers ────────────────────────────────────────────────────────

# Check if a string appears in the MOCK_TMUX_CALLS array
mock_tmux_was_called_with() {
    local pattern="$1"
    local call
    for call in "${MOCK_TMUX_CALLS[@]}"; do
        if [[ "$call" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}
