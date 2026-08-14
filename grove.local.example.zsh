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
#
# Tip: for slow installs, background the work so the worktree (and your agent)
# is usable immediately instead of blocking on `pnpm install` etc. Run any fast,
# ordering-sensitive steps in the foreground first, then detach the rest with
# nohup and log it so you can tail progress:
#
#   grove_post_create_commands[backend]="npx prisma generate && nohup zsh -c 'yarn' > /tmp/grove-backend-install.log 2>&1 &"
#
# Watch it with:  tail -f /tmp/grove-backend-install.log
grove_post_create_commands[backend]="nohup zsh -c 'yarn && npx prisma generate' > /tmp/grove-backend-install.log 2>&1 &"
grove_post_create_commands[frontend]="nohup zsh -c 'pnpm install' > /tmp/grove-frontend-install.log 2>&1 &"

# Post-startup hooks — commands to run every time a new tmux session is created
# for a workspace (after post-create hooks). Use for launching agents, tmux panes, etc.
# Default applies to all workspaces; per-workspace entries override it.
#
# Tip: worktrees are long-lived but tmux sessions are ephemeral (they die on
# reboot or `tmux kill-session`). When you re-open a workspace whose session is
# gone, the startup command runs again in a fresh session. Adding Claude Code's
# `--continue` makes it resume the most recent conversation for that worktree
# instead of starting cold — so you pick up where you left off. The `|| claude`
# fallback handles the first run, when there's no prior conversation to continue.
# (Codex has an equivalent via `codex resume --last`.)
GROVE_DEFAULT_POST_STARTUP_COMMAND="claude --permission-mode auto --continue || claude --permission-mode auto"    # or "codex", "cursor .", etc.
grove_post_startup_commands[fullstack]="cursor ."

# Any other env vars or shell config you need
