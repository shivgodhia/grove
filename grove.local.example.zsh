# grove.local.zsh — User-specific configuration
#
# Copy this file to grove.local.zsh and edit it.
# That file is gitignored, so your settings won't conflict with updates.

# Where your git projects live
GROVE_PROJECTS_DIR="$HOME/groveyard"

# Base branch for new worktrees (default: origin/main)
# GROVE_BASE_BRANCH="origin/main"

# Prefix for new branches when the name doesn't exist on remote (default: $USER)
GROVE_BRANCH_PREFIX="$USER"

# Where workspaces are created (default: $GROVE_PROJECTS_DIR/workspaces)
# GROVE_WORKSPACES_DIR="$GROVE_PROJECTS_DIR/workspaces"

# Workspace definitions (multi-project)
# Each workspace maps to a space-separated list of project names.
# Project names are auto-claimed as implicit single-project workspaces,
# so workspace names must be distinct from project directory names.
grove_workspaces[fullstack]="frontend backend"
grove_workspaces[admin]="backend admin-panel"

# Post-create hooks — commands to run after creating a worktree for a project
# These run per-project, regardless of which workspace the project belongs to.
grove_post_create_commands[backend]="yarn && npx prisma generate"
grove_post_create_commands[frontend]="pnpm install"

# Post-startup hooks — commands to run every time a new tmux session is created
# for a workspace (after post-create hooks). Use for launching agents, tmux panes, etc.
# Default applies to all workspaces; per-workspace entries override it.
GROVE_DEFAULT_POST_STARTUP_COMMAND="claude --dangerously-skip-permissions"    # or "codex", "cursor .", etc.
grove_post_startup_commands[fullstack]="cursor ."

# Any other env vars or shell config you need
