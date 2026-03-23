#!/usr/bin/env zsh
# Integration tests: creating a multi-project workspace

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# All project worktrees created
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    [[ -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" ]] &&
    [[ -d "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend" ]]
' 'all project worktrees created'

# All on same branch
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    local b1=$(git -C "$GROVE_WORKSPACES_DIR/fullstack/my-feature/frontend" rev-parse --abbrev-ref HEAD)
    local b2=$(git -C "$GROVE_WORKSPACES_DIR/fullstack/my-feature/backend" rev-parse --abbrev-ref HEAD)
    [[ "$b1" == "testuser/my-feature" ]] && [[ "$b2" == "testuser/my-feature" ]]
' 'all worktrees on same branch'

# Agent configs merged into workspace root
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"

    # Add skills to source repo and push to remote so worktree (based off origin/main) has them
    mkdir -p "$GROVE_PROJECTS_DIR/frontend/.claude/skills"
    printf "---\nname: lint\n---\nLint" > "$GROVE_PROJECTS_DIR/frontend/.claude/skills/lint.md"
    git -C "$GROVE_PROJECTS_DIR/frontend" add -A && git -C "$GROVE_PROJECTS_DIR/frontend" commit -m "add skill" --quiet
    git -C "$GROVE_PROJECTS_DIR/frontend" push origin main --quiet 2>/dev/null

    gv fullstack my-feature &>/dev/null

    [[ -f "$GROVE_WORKSPACES_DIR/fullstack/my-feature/.claude/skills/frontend--lint.md" ]]
' 'agent configs merged into workspace root'

# tmux rename-window called for multi-project
ztr test '
    create_test_repo frontend
    create_test_repo backend
    grove_workspaces[fullstack]="frontend backend"
    gv fullstack my-feature &>/dev/null
    mock_tmux_was_called_with "rename-window"
' 'tmux rename-window called for multi-project'
