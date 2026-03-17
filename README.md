# grove - Multi-Repo Worktree Manager for Zsh

A Zsh function that manages multi-repo [git worktrees](https://git-scm.com/docs/git-worktree) with tmux integration. Group multiple projects into a workspace so they all get worktrees with the same branch name, inside one tmux session.

## Why Grove?

You're working on features that span multiple repos — a frontend and backend, a server and admin panel. You need worktrees in each repo with the same branch name, set up together, accessible from one tmux session. Grove does this in one command.

## How it works

You define workspaces that group projects together. `grove <workspace> <name>` is all you need:

1. **Single-project**: Any git repo is automatically a workspace.
2. **Multi-project**: Define workspace groups in config. `grove fullstack fix-auth` creates worktrees in both `frontend` and `backend`.

For each project in the workspace:
1. Fetches from origin
2. If the branch exists on any remote, tracks it where available; creates new branch elsewhere
3. Creates worktrees for all projects under one workspace directory
4. For multi-project: symlinks `.claude/skills/` and `.cursor/` from each project into the workspace root
5. Opens a tmux session and runs post-create + post-startup hooks

## Features

- **Multi-repo workspaces**: Group projects together — one command creates worktrees across all of them
- **Smart branch resolution**: Tracks existing remote branches where they exist, creates new branches elsewhere
- **Consistent branch naming**: All projects in a workspace get the same branch name
- **Agent config merging**: `.claude/skills/` and `.cursor/` from each project are symlinked into the workspace root
- **Post-create hooks**: Per-project setup commands (dependency install, codegen)
- **Post-startup hooks**: Per-workspace commands (launch AI agents, tmux layouts)
- **tmux session integration**: One session per workspace instance
- **Fuzzy-find completion**: fzf-powered Tab completion for workspaces and instances
- **direnv support**: Auto-runs `direnv allow` for new worktrees
- **Rollback on failure**: If any worktree creation fails, all are cleaned up

## Installation

Copy this prompt into Claude Code (or your AI tool of choice):

```
Clone [grove](https://github.com/shivgodhia/grove) to ~/.zsh/grove and add `source ~/.zsh/grove/grove.zsh`
to my .zshrc. Then walk me through setting up ~/.zsh/grove/grove.local.zsh step by step,
asking me one question at a time:

1. Ask where my "projects directory" is — explain this is a single parent folder where all my git clones
   live for grove, and that workspaces get created in a `workspaces/` subdirectory inside it. This MUST be
   Suggest ~/groveyard as a default.
2. Ask what branch prefix I want (default: $USER). Explain this is used for naming new branches as
   <prefix>/branch-name.
3. Iteratively ask me for git repos to clone into the projects directory. For each one:
   - Clone it into the projects directory.
   - Read the project's README to figure out what setup commands are needed (e.g. npm install,
     pnpm install, yarn && npx prisma generate) and suggest a post-create hook for it.
   - After each clone, ask if I want to add another repo or if I'm done.
4. Ask if I want to define any multi-project workspaces. Explain the concept: a workspace groups
   multiple repos so they all get worktrees with the same branch name in one command. For example,
   grove_workspaces[fullstack]="frontend backend" means `grove fullstack fix-auth` creates
   worktrees in both repos. Workspace names must be distinct from project directory names (project
   names are auto-claimed as implicit single-project workspaces). Iteratively ask for workspace
   definitions until done.
5. Ask if I want an AI agent (like Claude Code) to launch automatically in every new workspace session.
   Explain this is a post-startup hook that runs every time a tmux session is created, not just on first
   creation. If yes, ask which agent command to use (default: `claude`) and set it as
   GROVE_DEFAULT_POST_STARTUP_COMMAND. Then ask if any specific workspaces need a different startup
   command (e.g. a tmux split pane layout) — if so, configure those as per-workspace overrides
   with grove_post_startup_commands[workspace].
6. Copy grove.local.example.zsh to grove.local.zsh, then edit it with all the
   collected configuration.
7. Ask if I want terminal tab titles to automatically show the workspace name. Explain that this
   makes tmux set the terminal tab title to the session name (e.g. "grove/fullstack/fix-auth"), so
   each tab is easy to identify. If yes, find my tmux config (~/.config/tmux/tmux.conf or
   ~/.tmux.conf) and add `set-option -g set-titles on` and `set-option -g set-titles-string '#S'`
   if they aren't already present. Then ask which terminal emulator they use (e.g. iTerm2, Alacritty,
   Kitty, WezTerm, Terminal.app) and walk them through enabling the setting that lets applications
   change the tab/window title — for example, in iTerm2 this is under Profiles → General → Title
   where "Applications in terminal may change the title" must be checked.
8. Ask if they want recommended tmux settings for a better workspace experience. Explain that
   `set -g mouse on` enables mouse support (scroll through output, click to switch panes, drag
   to resize them) and `set -g history-limit 50000` increases the scrollback buffer so you don't
   lose output from long-running commands. If yes, find their tmux config and add these settings
   if they aren't already present, then reload with `tmux source-file <path-to-config>`.
```

Or do it manually:

1. Clone this repo:

   ```sh
   git clone <repo-url> ~/.zsh/grove
   ```

2. Add to your `.zshrc`:

   ```sh
   source ~/.zsh/grove/grove.zsh
   ```

3. Copy and edit the example config:

   ```sh
   cp ~/.zsh/grove/grove.local.example.zsh \
      ~/.zsh/grove/grove.local.zsh
   ```

4. Restart your terminal or run `source ~/.zshrc`.

Default: `~/groveyard`.

### Configuration

Edit `grove.local.zsh`:

#### Directories

- `GROVE_PROJECTS_DIR` — where your git repos live (default: `~/groveyard`)
- `GROVE_WORKSPACES_DIR` — where workspaces are created (default: `$GROVE_PROJECTS_DIR/workspaces`)
- `GROVE_BASE_BRANCH` — base branch for new worktrees (default: `origin/main`)
- `GROVE_BRANCH_PREFIX` — prefix for new branch names (default: `$USER`)

#### Workspace definitions

Group projects into named workspaces. Project names are **auto-claimed** as implicit single-project workspaces, so workspace names must be distinct from project directory names.

```sh
grove_workspaces[fullstack]="frontend backend"
grove_workspaces[admin]="backend admin-panel"
```

#### Post-create hooks

Per-project commands that run when a worktree is first created:

```sh
grove_post_create_commands[backend]="yarn && npx prisma generate"
grove_post_create_commands[frontend]="pnpm install"
```

#### Post-startup hooks

Per-workspace commands that run every time a new tmux session is created:

```sh
GROVE_DEFAULT_POST_STARTUP_COMMAND="claude --dangerously-skip-permissions"
grove_post_startup_commands[fullstack]="claude --dangerously-skip-permissions"
```

## Usage

```sh
grove <workspace> <name>                  # create/attach to workspace
grove <workspace> <name> <command>        # run command in workspace (no tmux)
grove --list                              # list all workspaces and instances
grove --rm <workspace> <name>             # remove workspace instance
grove --rm --force <workspace> <name>     # force remove (uncommitted changes)
grove --kms [--force]                     # remove current workspace (from inside it)
grove --home                              # cd to projects directory
grove --help                              # show usage guide
```

### Examples

```sh
# Single-project workspace (implicit)
grove backend fix-auth

# Multi-project workspace
grove fullstack fix-auth

# Check out a teammate's branch across all workspace projects
grove fullstack someone/fix-bug

# Run a command in the workspace
grove fullstack fix-auth git status

# List everything
grove --list

# Clean up when done
grove --rm fullstack fix-auth
```

## Directory structure

```
~/groveyard/                        # git repos live here
├── frontend/                            # main repo checkout
├── backend/                             # another repo
└── workspaces/                          # all workspace instances
    ├── fullstack/                       # multi-project workspace
    │   └── fix-auth/                    # instance
    │       ├── .claude/skills/          # symlinked from children
    │       ├── frontend/                # worktree → branch
    │       └── backend/                 # worktree → branch
    └── backend/                         # single-project workspace
        └── add-caching/                 # instance
            └── backend/                 # worktree → branch
```

## Claude Code skill

This repo includes a [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) for managing workspaces with `/grove` inside Claude Code.

**Install:**

```sh
mkdir -p ~/.claude/skills
ln -s ~/.zsh/grove/skills/grove ~/.claude/skills/grove
```

**Usage:**

```
/grove create fix the auth bug
/grove list
/grove cd fix-auth-bug
/grove delete fix-auth-bug
```

## Recommended tmux settings

Add these to your tmux config (`~/.config/tmux/tmux.conf` or `~/.tmux.conf`):

```
# Enable mouse support (scroll, click panes, resize)
set -g mouse on

# Increase scrollback buffer
set -g history-limit 50000

# Show workspace name as terminal tab title
set-option -g set-titles on
set-option -g set-titles-string '#S'
```

Then reload your config:

```sh
tmux source-file ~/.config/tmux/tmux.conf
```

**Mouse support** lets you scroll through output, click to switch panes, and drag to resize them — it just works so much better.

**Tab titles** — `grove` creates tmux sessions named `grove/<workspace>/<name>`, and `set-titles` pushes that to your terminal as the tab name. Instead of a sea of identical "zsh" tabs, you see exactly which workspace each tab is for. Ghostty picks up the tmux title automatically — no extra config needed. In iTerm2, you'll also need to enable **Profiles → General → Title → "Applications in terminal may change the title"**.

## Requirements

- Zsh
- Git 2.5+ (for worktree support)
- tmux
- fzf (optional, for fuzzy Tab completion)
