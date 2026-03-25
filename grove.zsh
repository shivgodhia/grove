#!/usr/bin/env zsh
# grove - Multi-project workspace manager with git worktrees and tmux integration
#
# Manages workspaces that can span multiple git repos. Each workspace groups
# one or more projects, creating worktrees with the same branch name in each,
# all inside one tmux session.
#
# WORKSPACE TYPES:
# - Single-project (implicit): Any project directory is automatically a workspace.
#   `grove my-api fix-auth` creates one worktree.
# - Multi-project (explicit): Define named workspaces in config.
#   `grove fullstack fix-auth` creates worktrees in frontend + backend.
#
# BRANCH RESOLUTION:
# When you run `grove <workspace> <name>`, it checks (in order):
# 1. Existing workspace directory with that name → cd into it
# 2. Remote branch matching <name> on any project's origin → track it where it exists,
#    create new branch elsewhere
# 3. Otherwise → create new branch as <prefix>/<name> off origin/main in all projects
#
# DIRECTORY STRUCTURE:
#   workspaces/<workspace>/<name>/<project>/   (worktree)
#
# TMUX INTEGRATION:
# Each workspace instance gets a dedicated tmux session named "grove/<workspace>/<name>".
# - Single-project: tmux opens in the worktree itself
# - Multi-project: tmux opens at workspace root, with .claude/skills/ symlinked from children
#
# See README.md for installation and usage instructions.

# ─── Configuration (defaults) ────────────────────────────────────────────────
# Override any of these in grove.local.zsh (see below).
: ${GROVE_PROJECTS_DIR:="$HOME/groveyard"}
: ${GROVE_BASE_BRANCH:="origin/main"}
: ${GROVE_BRANCH_PREFIX:="$USER"}

# Post-create hooks — commands to run after creating a worktree for a project.
typeset -gA grove_post_create_commands

# Post-startup hooks — commands to run every time a new tmux session is created
# for a workspace (after post-create hooks, if any). Use for launching agents,
# adding tmux splits/panes, or any per-session setup.
# Set a default for all workspaces, then override per-workspace as needed.
: ${GROVE_DEFAULT_POST_STARTUP_COMMAND:=""}
typeset -gA grove_post_startup_commands

# Workspace definitions — map workspace names to space-separated project lists.
# Project names are auto-claimed as implicit single-project workspaces.
# Explicit workspace names must be distinct from project directory names.
typeset -gA grove_workspaces

# ─── Local overrides ────────────────────────────────────────────────────────
# Source user-specific config (projects dir, workspace definitions, hooks, etc.)
# from a file alongside this one. This file is gitignored so you can
# `git pull` updates to grove.zsh without conflicts.
#
# Example grove.local.zsh:
#   GROVE_PROJECTS_DIR="$HOME/Desktop/clones/projects"
#   GROVE_BRANCH_PREFIX="shivgodhia"
#   grove_workspaces[fullstack]="frontend backend"
#   grove_post_create_commands[my-api]="yarn && npx prisma generate"
#
local _grove_script_dir="${${(%):-%x}:A:h}"
if [[ -f "$_grove_script_dir/grove.local.zsh" ]]; then
    source "$_grove_script_dir/grove.local.zsh"
fi

# Derived defaults (set after local overrides so they pick up custom GROVE_PROJECTS_DIR)
: ${GROVE_WORKSPACES_DIR:="$GROVE_PROJECTS_DIR/workspaces"}

# ─── Validation ──────────────────────────────────────────────────────────────
# Validate workspace config: workspace names must not collide with project directory names.
# Project names are auto-claimed as implicit single-project workspaces.
_grove_validate_workspace_config() {
    local name
    for name in ${(k)grove_workspaces}; do
        if [[ -d "$GROVE_PROJECTS_DIR/$name/.git" ]]; then
            echo "grove: WARNING: workspace name '$name' conflicts with project directory '$GROVE_PROJECTS_DIR/$name'." >&2
            echo "  Project names are auto-claimed as implicit single-project workspaces." >&2
            echo "  Removing workspace definition for '$name'. Use a different name." >&2
            unset "grove_workspaces[$name]"
        fi
    done
}
_grove_validate_workspace_config

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Generate tmux session name from workspace and instance name
# Format: grove/<workspace>/<name> (dots/colons replaced with underscores for tmux compat)
_grove_tmux_session_name() {
    local name="grove/$1/$2"
    # tmux doesn't allow dots or colons in session names
    echo "${name//[.:]/_}"
}

# Resolve which projects belong to a workspace.
# Returns space-separated list of project names.
_grove_resolve_workspace_projects() {
    local workspace="$1"

    # 1. Explicit workspace definition
    if [[ -n "${grove_workspaces[$workspace]+x}" ]]; then
        if [[ -z "${grove_workspaces[$workspace]}" ]]; then
            echo "grove: workspace '$workspace' has empty project list" >&2
            return 1
        fi
        echo "${grove_workspaces[$workspace]}"
        return 0
    fi

    # 2. Implicit single-project workspace (project directory exists)
    if [[ -d "$GROVE_PROJECTS_DIR/$workspace/.git" ]]; then
        echo "$workspace"
        return 0
    fi

    echo "grove: unknown workspace '$workspace'" >&2
    echo "  Not found as a workspace definition or project directory in $GROVE_PROJECTS_DIR" >&2
    return 1
}

# Check if a workspace has more than one project
_grove_is_multi_project() {
    local workspace="$1"
    local projects
    projects=$(_grove_resolve_workspace_projects "$workspace") || return 1
    local -a project_list=(${(s: :)projects})
    (( ${#project_list} > 1 ))
}

# Resolve branch name, checking for conflicts on remote.
# If $GROVE_BRANCH_PREFIX/$name conflicts with any repo, use date-prefixed version.
# Outputs the resolved branch name.
_grove_resolve_branch_name() {
    local workspace="$1" name="$2"
    local candidate="$GROVE_BRANCH_PREFIX/$name"
    local projects
    projects=$(_grove_resolve_workspace_projects "$workspace") || return 1
    local -a project_list=(${(s: :)projects})

    local project conflict=0 remote_check
    for project in "${project_list[@]}"; do
        remote_check=$(git -C "$GROVE_PROJECTS_DIR/$project" ls-remote --heads origin "$candidate" 2>/dev/null)
        if [[ -n "$remote_check" ]]; then
            conflict=1
            break
        fi
    done

    if (( conflict )); then
        echo "$GROVE_BRANCH_PREFIX/$(date +%m%d%y)-$name"
    else
        echo "$candidate"
    fi
}

# Copy .claude/skills/* and .cursor/* from each project worktree into workspace root.
# Skills have their frontmatter name: rewritten with a project prefix to avoid collisions.
# Uses ${project}-- prefix to avoid collisions.
_grove_merge_agent_configs() {
    local workspace_root="$1"
    shift
    local -a projects=("$@")

    local project project_dir skill_name link_name target_rel item_name
    for project in "${projects[@]}"; do
        project_dir="$workspace_root/$project"

        # Copy .claude/skills/* with rewritten name: frontmatter
        if [[ -d "$project_dir/.claude/skills" ]]; then
            mkdir -p "$workspace_root/.claude/skills"
            for skill in "$project_dir/.claude/skills"/*(N); do
                skill_name=$(basename "$skill")
                link_name="${project}--${skill_name}"
                if [[ ! -e "$workspace_root/.claude/skills/$link_name" ]]; then
                    if [[ -d "$skill" ]]; then
                        # Skill is a directory (contains SKILL.md) — copy dir and rewrite name in SKILL.md
                        cp -R "$skill" "$workspace_root/.claude/skills/$link_name"
                        if [[ -f "$workspace_root/.claude/skills/$link_name/SKILL.md" ]]; then
                            sed -i '' "s/^name: .*/name: ${project}--${skill_name}/" \
                                "$workspace_root/.claude/skills/$link_name/SKILL.md"
                        fi
                    else
                        # Skill is a plain file — copy and rewrite name
                        sed "s/^name: .*/name: ${project}--${skill_name}/" "$skill" \
                            > "$workspace_root/.claude/skills/$link_name"
                    fi
                fi
            done
        fi

        # Copy .cursor/* — merge contents of rules/, commands/, skills/ into canonical dirs
        # with prefixed filenames; copy other top-level items with prefixed names.
        if [[ -d "$project_dir/.cursor" ]]; then
            mkdir -p "$workspace_root/.cursor"
            for item in "$project_dir/.cursor"/*(N); do
                item_name=$(basename "$item")
                if [[ -d "$item" && ( "$item_name" = rules || "$item_name" = commands || "$item_name" = skills ) ]]; then
                    # Merge contents into canonical subdir with prefixed names
                    mkdir -p "$workspace_root/.cursor/$item_name"
                    for child in "$item"/*(N); do
                        local child_name=$(basename "$child")
                        local prefixed="${project}--${child_name}"
                        if [[ ! -e "$workspace_root/.cursor/$item_name/$prefixed" ]]; then
                            cp -R "$child" "$workspace_root/.cursor/$item_name/$prefixed"
                        fi
                    done
                else
                    # Top-level file/dir — copy with prefixed name
                    link_name="${project}--${item_name}"
                    if [[ ! -e "$workspace_root/.cursor/$link_name" ]]; then
                        cp -R "$item" "$workspace_root/.cursor/$link_name"
                    fi
                fi
            done
        fi
    done
}

# List all workspace names: explicit keys + implicit (project dirs not already in explicit workspaces)
_grove_list_all_workspaces() {
    local -a all_workspaces=()

    # Explicit workspaces
    local name
    for name in ${(k)grove_workspaces}; do
        all_workspaces+=("$name")
    done

    # Implicit single-project workspaces (project dirs not used in explicit workspaces)
    local -a explicit_projects=()
    for name in ${(k)grove_workspaces}; do
        explicit_projects+=(${(s: :)grove_workspaces[$name]})
    done

    if [[ -d "$GROVE_PROJECTS_DIR" ]]; then
        local dir project_name
        for dir in "$GROVE_PROJECTS_DIR"/*(N/); do
            if [[ -d "$dir/.git" ]]; then
                project_name="${dir:t}"
                # Add as implicit workspace (even if used in explicit workspaces —
                # it's still valid as a single-project workspace)
                if (( ! ${all_workspaces[(Ie)$project_name]} )); then
                    all_workspaces+=("$project_name")
                fi
            fi
        done
    fi

    echo "${all_workspaces[*]}"
}

# ─── Main function ───────────────────────────────────────────────────────────
gv() {
    local projects_dir="$GROVE_PROJECTS_DIR"
    local workspaces_dir="$GROVE_WORKSPACES_DIR"

    # Handle special flags
    if [[ "$1" == "--help" ]]; then
        cat <<'HELP'
Grove - Workspace Manager with Multi-Repo Worktree Support

QUICK START
  gv my-app my-feature           Single-project workspace
  gv fullstack my-feature        Multi-project workspace (if configured)
  ... do your work ...
  gv --rm my-app my-feature      Delete workspace when done

HOW IT WORKS
  A workspace groups one or more projects. Each project gets a git worktree
  with the same branch name, all inside one tmux session.

  Single-project workspaces are implicit — any git repo in your projects
  directory is automatically a workspace. Multi-project workspaces are
  defined in your config (e.g. grove_workspaces[fullstack]="frontend backend").

CREATING A WORKSPACE
  gv <workspace> <name>

  The first argument is a workspace name (either an explicit definition or
  a project directory name). The second is a name for your instance — usually
  a feature or branch name like "add-search" or "fix-login-bug".

  What happens:
    1. Fetches all repos in the workspace from origin
    2. If the branch exists on any remote, tracks it; otherwise creates a new
       branch (prefixed with your username) off origin/main
    3. Creates worktrees for all projects in the workspace
    4. Opens a tmux session (at worktree dir for single-project, workspace root
       for multi-project)
    5. Runs post-create hooks (first time) and post-startup hooks (every time)

  For multi-project workspaces, .claude/skills/ and .cursor/ from each project
  are symlinked into the workspace root so AI agents can see all project configs.

FINDING AND RETURNING TO A WORKSPACE
  gv <workspace> <name>

  Same command — if the workspace already exists, it switches to the tmux session.
  Use tab completion to see existing instances.

DELETING A WORKSPACE
  gv --rm <workspace> <name>
  gv --rm --force <workspace> <name>

  Removes all worktrees, deletes local branches, kills the tmux session.
  Add --force for uncommitted changes.

  gv --kms [--force]

  Remove the current workspace (run from inside a workspace directory).

RUNNING A ONE-OFF COMMAND
  gv <workspace> <name> <command>

  Runs a command in the workspace directory without tmux.

OTHER COMMANDS
  gv --list     List all workspaces and their instances
  gv --home     cd to your projects directory
  gv --help     Show this help

CONFIGURATION
  Override defaults in grove.local.zsh (gitignored):
    GROVE_PROJECTS_DIR         Where git repos live (default: ~/groveyard)
    GROVE_BASE_BRANCH          Base branch for new worktrees (default: origin/main)
    GROVE_BRANCH_PREFIX        Prefix for new branches (default: your username)
    GROVE_WORKSPACES_DIR       Where workspaces are created (default: $GROVE_PROJECTS_DIR/workspaces)

  Workspace definitions (multi-project):
    grove_workspaces[fullstack]="frontend backend"

  Post-create hooks (per project, run on first worktree creation):
    grove_post_create_commands[my-api]="yarn && npx prisma generate"

  Post-startup hooks (per workspace, run every tmux session creation):
    GROVE_DEFAULT_POST_STARTUP_COMMAND="claude"
    grove_post_startup_commands[fullstack]="claude --dangerously-skip-permissions"
HELP
        return 0
    elif [[ "$1" == "--home" ]]; then
        cd "$projects_dir"
        return 0
    elif [[ "$1" == "--list" ]]; then
        local -a all_ws=(${(s: :)$(_grove_list_all_workspaces)})
        local ws_dir projects instance_name session_name branch project _b
        local -a project_list multi_ws single_ws
        local -a divergent_branches

        # Color definitions
        local c_reset=$'\e[0m'
        local c_header=$'\e[1;37m'          # bold white – section headers
        local c_single_ws=$'\e[1;36m'       # bold cyan – single-repo workspace names
        local c_multi_ws=$'\e[1;36m'        # bold cyan – multi-repo workspace names (same as single)
        local c_instance=$'\e[0;37m'        # white – instance names
        local c_branch=$'\e[0;32m'          # green – branch names
        local c_tmux=$'\e[0;90m'            # dim gray – tmux session info
        local c_repo=$'\e[0;33m'            # yellow – repo/project names
        local c_divergent=$'\e[0;31m'       # red – divergent branch indicator

        # Separate into multi-repo and single-repo workspaces
        for ws_name in "${all_ws[@]}"; do
            projects=$(_grove_resolve_workspace_projects "$ws_name" 2>/dev/null) || continue
            project_list=(${(s: :)projects})
            if (( ${#project_list} > 1 )); then
                multi_ws+=("$ws_name")
            else
                single_ws+=("$ws_name")
            fi
        done

        # ── Single-Repo Workspaces ──
        if (( ${#single_ws} > 0 )); then
            echo "${c_header}=== Single-Repo Workspaces ===${c_reset}"
            for ws_name in "${single_ws[@]}"; do
                ws_dir="$workspaces_dir/$ws_name"

                echo "\n${c_single_ws}[$ws_name]${c_reset}"

                for instance_dir in "$ws_dir"/*(N/); do
                    instance_name=$(basename "$instance_dir")
                    session_name=$(_grove_tmux_session_name "$ws_name" "$instance_name")

                    # Get branch from the single project worktree
                    branch=""
                    for project_dir in "$instance_dir"/*(N/); do
                        project=$(basename "$project_dir")
                        [[ "$project" == .* ]] && continue
                        if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
                            branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                            break
                        fi
                    done

                    if tmux has-session -t "$session_name" 2>/dev/null; then
                        echo "  • ${c_instance}$instance_name${c_reset}  ${c_branch}$branch${c_reset}  ${c_tmux}[tmux: $session_name]${c_reset}"
                    else
                        echo "  • ${c_instance}$instance_name${c_reset}  ${c_branch}$branch${c_reset}"
                    fi
                done
            done
        fi

        # ── Multi-Repo Workspaces ──
        if (( ${#multi_ws} > 0 )); then
            if (( ${#single_ws} > 0 )); then
                echo ""
            fi
            echo "${c_header}=== Multi-Repo Workspaces ===${c_reset}"
            for ws_name in "${multi_ws[@]}"; do
                ws_dir="$workspaces_dir/$ws_name"
                projects=$(_grove_resolve_workspace_projects "$ws_name" 2>/dev/null) || continue
                project_list=(${(s: :)projects})

                local colored_projects=()
                for _p in "${project_list[@]}"; do
                    colored_projects+=("${c_repo}$_p${c_reset}")
                done
                echo "\n${c_multi_ws}[$ws_name]${c_reset} (${(j:, :)colored_projects})"

                for instance_dir in "$ws_dir"/*(N/); do
                    instance_name=$(basename "$instance_dir")
                    session_name=$(_grove_tmux_session_name "$ws_name" "$instance_name")

                    # Determine the expected branch for this instance.
                    # At creation, the branch is either the raw instance name
                    # (if it matched a remote) or $GROVE_BRANCH_PREFIX/$instance_name.
                    # Reconstruct: check if any repo is on $PREFIX/$instance_name;
                    # otherwise fall back to $instance_name itself.
                    local expected_branch="$instance_name"
                    local prefixed_branch="$GROVE_BRANCH_PREFIX/$instance_name"
                    local -A repo_branches=()
                    for project_dir in "$instance_dir"/*(N/); do
                        project=$(basename "$project_dir")
                        [[ "$project" == .* ]] && continue
                        if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
                            _b=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                            repo_branches[$project]="$_b"
                            if [[ "$_b" == "$prefixed_branch" ]]; then
                                expected_branch="$prefixed_branch"
                            fi
                        fi
                    done

                    if tmux has-session -t "$session_name" 2>/dev/null; then
                        echo "  • ${c_instance}$instance_name${c_reset}  ${c_branch}$expected_branch${c_reset}  ${c_tmux}[tmux: $session_name]${c_reset}"
                    else
                        echo "  • ${c_instance}$instance_name${c_reset}  ${c_branch}$expected_branch${c_reset}"
                    fi

                    # Show per-project branches that diverge from expected
                    divergent_branches=()
                    for project _b in "${(@kv)repo_branches}"; do
                        if [[ "$_b" != "$expected_branch" ]]; then
                            divergent_branches+=("$project:$_b")
                        fi
                    done
                    if (( ${#divergent_branches} > 0 )); then
                        for entry in "${divergent_branches[@]}"; do
                            echo "    ${c_divergent}^${c_reset} ${c_repo}${entry%%:*}${c_reset} on ${c_branch}${entry#*:}${c_reset}"
                        done
                    fi
                done
            done
        fi
        return 0
    elif [[ "$1" == "--kms" ]]; then
        # "Kill myself" — remove the current workspace from within it
        shift
        local force_flag=""
        if [[ "$1" == "--force" ]]; then
            force_flag="--force"
            shift
        fi
        local cwd="$PWD"
        # Check if we're inside the workspaces directory
        if [[ "$cwd" != "$workspaces_dir/"* ]]; then
            echo "Not inside a grove-managed workspace"
            return 1
        fi
        # Extract workspace and instance from path: $workspaces_dir/<workspace>/<instance>/...
        local relative="${cwd#$workspaces_dir/}"
        local workspace="${relative%%/*}"
        local instance="${${relative#*/}%%/*}"
        if [[ -z "$workspace" || -z "$instance" ]]; then
            echo "Could not determine workspace/instance from current path"
            return 1
        fi
        echo "Removing workspace instance: $workspace/$instance"
        gv --rm $force_flag "$workspace" "$instance"
        return $?
    elif [[ "$1" == "--rm" ]]; then
        shift
        local force_flag=""
        if [[ "$1" == "--force" ]]; then
            force_flag="--force"
            shift
        fi
        local workspace="$1"
        local instance="$2"
        if [[ -z "$workspace" || -z "$instance" ]]; then
            echo "Usage: gv --rm [--force] <workspace> <name>"
            return 1
        fi
        # Sanitize instance name for directory (replace / with -)
        local dir_name="${instance//\//-}"
        local workspace_root="$workspaces_dir/$workspace/$dir_name"
        if [[ ! -d "$workspace_root" ]]; then
            echo "Workspace instance not found: $workspace_root"
            return 1
        fi

        # Scan actual directories on disk (not config) to handle config drift
        local rc=0 project branch_name

        # Pre-flight: if not forcing, check all worktrees for uncommitted changes
        # before removing anything (atomic: all-or-nothing)
        if [[ -z "$force_flag" ]]; then
            local dirty_worktrees=()
            for project_dir in "$workspace_root"/*(N/); do
                project=$(basename "$project_dir")
                [[ "$project" == .* ]] && continue
                if [[ -d "$GROVE_PROJECTS_DIR/$project/.git" ]]; then
                    if ! git -C "$project_dir" diff --quiet 2>/dev/null || \
                       ! git -C "$project_dir" diff --cached --quiet 2>/dev/null || \
                       [[ -n "$(git -C "$project_dir" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                        dirty_worktrees+=("$project")
                    fi
                fi
            done
            if (( ${#dirty_worktrees} > 0 )); then
                echo "Cannot remove workspace: uncommitted changes in:"
                for project in "${dirty_worktrees[@]}"; do
                    echo "  - $project"
                done
                echo "Use --force to remove anyway: gv --rm --force $workspace $instance"
                return 1
            fi
        fi

        for project_dir in "$workspace_root"/*(N/); do
            project=$(basename "$project_dir")
            # Skip non-worktree directories (like .claude, .cursor)
            if [[ "$project" == .* ]]; then
                continue
            fi
            if [[ -d "$GROVE_PROJECTS_DIR/$project/.git" ]]; then
                branch_name=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                echo "Removing worktree: $project ($branch_name)"
                git -C "$GROVE_PROJECTS_DIR/$project" worktree remove $force_flag "$project_dir" || rc=1
                if [[ $rc -eq 0 && -n "$branch_name" && "$branch_name" != "HEAD" ]]; then
                    git -C "$GROVE_PROJECTS_DIR/$project" branch -D "$branch_name" 2>/dev/null
                fi
            fi
        done

        # Clean up workspace root (symlinks, empty dirs)
        rm -rf "$workspace_root"
        # Remove workspace dir if empty
        rmdir "$workspaces_dir/$workspace" 2>/dev/null

        # Kill tmux session LAST — if inside it, kills our terminal
        local session_name=$(_grove_tmux_session_name "$workspace" "$dir_name")
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "Killing tmux session: $session_name"
            tmux kill-session -t "$session_name"
        fi
        return $rc
    fi

    # Normal usage: grove <workspace> <name> [command...]
    local workspace="$1"
    local name="$2"
    shift 2 2>/dev/null
    local command=("$@")

    if [[ -z "$workspace" || -z "$name" ]]; then
        echo "Usage: gv <workspace> <name>              # attach to tmux session (creates workspace if needed)"
        echo "       gv <workspace> <name> <command>    # run command in workspace (no tmux)"
        echo "       gv --list"
        echo "       gv --rm [--force] <workspace> <name>"
        echo "       gv --kms [--force]                  # remove current workspace (from inside it)"
        echo "       gv --home"
        echo "       gv --help"
        return 1
    fi

    # Resolve projects for this workspace
    local projects
    projects=$(_grove_resolve_workspace_projects "$workspace") || return 1
    local -a project_list=(${(s: :)projects})

    # Validate all projects exist
    local project
    for project in "${project_list[@]}"; do
        if [[ ! -d "$projects_dir/$project/.git" ]]; then
            echo "Project not found: $projects_dir/$project"
            return 1
        fi
    done

    local is_multi=0
    (( ${#project_list} > 1 )) && is_multi=1

    # Sanitize name for directory (replace / with -)
    local dir_name="${name//\//-}"
    local workspace_root="$workspaces_dir/$workspace/$dir_name"

    # Track if this is a new creation (for post-create hooks)
    local -a newly_created_projects=()

    # 1. Check if workspace instance already exists
    if [[ ! -d "$workspace_root" ]]; then
        # 2. Creation flow
        echo "Creating workspace: $workspace/$dir_name"

        # a. Fetch all repos
        for project in "${project_list[@]}"; do
            echo "Fetching $project from origin..."
            git -C "$projects_dir/$project" fetch origin
        done

        # b. Branch resolution
        # Check if raw $name (no prefix) exists on origin for any repo
        local raw_branch_exists=0 remote_check
        for project in "${project_list[@]}"; do
            remote_check=$(git -C "$projects_dir/$project" ls-remote --heads origin "$name" 2>/dev/null)
            if [[ -n "$remote_check" ]]; then
                raw_branch_exists=1
                break
            fi
        done

        local branch_name
        if (( raw_branch_exists )); then
            # User is tracking an existing branch — use raw name
            branch_name="$name"
            echo "Found existing remote branch: $name"
        else
            # New branch — compute prefixed name with conflict check
            branch_name=$(_grove_resolve_branch_name "$workspace" "$name") || return 1
            echo "Creating new branch: $branch_name"
        fi

        # c. Create workspace root
        mkdir -p "$workspace_root"

        # d. Create worktrees for each project
        local creation_failed=0 wt_path this_remote
        for project in "${project_list[@]}"; do
            wt_path="$workspace_root/$project"

            if (( raw_branch_exists )); then
                # Per-repo: track remote if that repo has it, else create new branch off base
                this_remote=$(git -C "$projects_dir/$project" ls-remote --heads origin "$name" 2>/dev/null)
                if [[ -n "$this_remote" ]]; then
                    echo "  $project: tracking origin/$name"
                    git -C "$projects_dir/$project" worktree add "$wt_path" -b "$name" "origin/$name" || {
                        creation_failed=1
                        break
                    }
                else
                    echo "  $project: creating $name off $GROVE_BASE_BRANCH"
                    git -C "$projects_dir/$project" worktree add "$wt_path" -b "$name" $GROVE_BASE_BRANCH || {
                        creation_failed=1
                        break
                    }
                fi
            else
                echo "  $project: creating $branch_name off $GROVE_BASE_BRANCH"
                git -C "$projects_dir/$project" worktree add "$wt_path" -b "$branch_name" $GROVE_BASE_BRANCH || {
                    creation_failed=1
                    break
                }
            fi

            # direnv allow if .envrc exists
            if [[ -f "$wt_path/.envrc" ]] && command -v direnv &> /dev/null; then
                (cd "$wt_path" && direnv allow)
            fi

            newly_created_projects+=("$project")
        done

        # Rollback on failure
        if (( creation_failed )); then
            echo "grove: creation failed, rolling back..."
            local b
            for project in "${newly_created_projects[@]}"; do
                wt_path="$workspace_root/$project"
                if [[ -d "$wt_path" ]]; then
                    b=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
                    git -C "$projects_dir/$project" worktree remove --force "$wt_path" 2>/dev/null
                    if [[ -n "$b" && "$b" != "HEAD" ]]; then
                        git -C "$projects_dir/$project" branch -D "$b" 2>/dev/null
                    fi
                fi
            done
            rm -rf "$workspace_root"
            rmdir "$workspaces_dir/$workspace" 2>/dev/null
            return 1
        fi

        # e. Merge agent configs for multi-project
        if (( is_multi )); then
            _grove_merge_agent_configs "$workspace_root" "${project_list[@]}"
        fi
    fi

    # Determine the working directory for commands/tmux
    local work_dir
    if (( is_multi )); then
        work_dir="$workspace_root"
    else
        work_dir="$workspace_root/${project_list[1]}"
    fi

    # Command passthrough
    if [[ ${#command[@]} -gt 0 ]]; then
        local old_pwd="$PWD"
        cd "$work_dir"
        eval "${command[@]}"
        local exit_code=$?
        cd "$old_pwd"
        return $exit_code
    fi

    # Tmux session
    local session_name=$(_grove_tmux_session_name "$workspace" "$dir_name")

    if tmux has-session -t "$session_name" 2>/dev/null; then
        # Session exists — attach or switch to it
        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$session_name"
        else
            tmux attach-session -t "$session_name"
        fi
    else
        # Create new tmux session
        tmux new-session -d -s "$session_name" -c "$work_dir"

        if (( is_multi )); then
            tmux rename-window -t "$session_name" "root"
        fi

        # Build the full command to send into the new session.
        # Chain: per-project post-create hooks (for newly created projects) → post-startup hook
        local full_cmd=""

        if (( ${#newly_created_projects} > 0 )); then
            local -a create_parts=()
            local project_wt
            for project in "${newly_created_projects[@]}"; do
                if [[ -n "${grove_post_create_commands[$project]}" ]]; then
                    project_wt="$workspace_root/$project"
                    create_parts+=("(cd '$project_wt' && ${grove_post_create_commands[$project]})")
                fi
            done
            if (( ${#create_parts} > 0 )); then
                full_cmd="${(j: && :)create_parts}"
            fi
        fi

        # Post-startup hook (per workspace)
        local startup_cmd="${grove_post_startup_commands[$workspace]:-$GROVE_DEFAULT_POST_STARTUP_COMMAND}"
        if [[ -n "$startup_cmd" ]]; then
            if [[ -n "$full_cmd" ]]; then
                full_cmd="${full_cmd} && ${startup_cmd}"
            else
                full_cmd="$startup_cmd"
            fi
        fi

        if [[ -n "$full_cmd" ]]; then
            tmux send-keys -t "$session_name" "$full_cmd" Enter
        fi

        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$session_name"
        else
            tmux attach-session -t "$session_name"
        fi
    fi
}

# ─── Tab completion ──────────────────────────────────────────────────────────

# FZF-powered fuzzy-find completion for grove.
# Provides fuzzy matching with colored match highlights for both
# workspace names and instance names. Falls back to standard zsh
# completion if fzf is not installed.

# Build annotated workspace list for fzf display.
# Multi-repo workspaces get " (proj1, proj2)" suffix.
# Output: one entry per line, suitable for fzf.
_grove_annotated_workspaces() {
    local -a all_ws=(${(s: :)$(_grove_list_all_workspaces)})
    local ws_name projects
    local -a project_list
    for ws_name in "${all_ws[@]}"; do
        if [[ -n "${grove_workspaces[$ws_name]+x}" ]]; then
            projects="${grove_workspaces[$ws_name]}"
            project_list=(${(s: :)projects})
            echo "$ws_name (${(j:, :)project_list})"
        else
            echo "$ws_name"
        fi
    done
}

_grove_fzf_available() {
    (( $+commands[fzf] ))
}

# Pipe candidates through fzf for fuzzy selection.
# Args: $1 = query (current word being typed), rest = candidates
# Returns selected candidate on stdout, exit code 0 if selected.
_grove_fzf_select() {
    local query="$1"; shift
    local -a candidates=("$@")
    if (( ${#candidates} == 0 )); then
        return 1
    fi
    # Single exact match — skip fzf
    if (( ${#candidates} == 1 )); then
        echo "${candidates[1]}"
        return 0
    fi
    printf '%s\n' "${candidates[@]}" | fzf \
        --height=~40% \
        --layout=reverse \
        --query="$query" \
        --select-1 \
        --exit-0 \
        --color='hl:magenta:underline,hl+:magenta:underline' \
        --no-info \
        --no-sort \
        --nth=1 \
        --bind='tab:accept'
}

# ZLE widget: intercepts tab when typing a `grove` command and uses fzf
# for fuzzy workspace/instance selection. For other commands, falls
# through to the normal tab-completion widget.
_grove_fzf_complete_widget() {
    local tokens=(${(z)LBUFFER})
    local cmd="${tokens[1]}"

    # Only intercept for the gv command
    if [[ "$cmd" != "gv" ]]; then
        zle "${_grove_orig_tab_widget:-expand-or-complete}"
        return
    fi

    local nargs=${#tokens}
    # If cursor is right after a space, we're starting a new argument
    local current_word=""
    if [[ "$LBUFFER" == *" " ]]; then
        (( nargs++ ))
    else
        current_word="${tokens[-1]}"
    fi

    local workspaces_dir="$GROVE_WORKSPACES_DIR"

    # Determine what we're completing based on argument position
    case "$nargs" in
        1)
            # Just "grove" with cursor right after — complete workspaces (position 2)
            ;& # fall through
        2)
            # Completing first argument: flags + workspaces
            local -a candidates=()

            # Add flags
            candidates+=("--help" "--home" "--kms" "--list" "--rm")

            # Add annotated workspaces (multi-repo get project list suffix)
            candidates+=("${(@f)$(_grove_annotated_workspaces)}")

            local selection
            selection=$(_grove_fzf_select "$current_word" "${candidates[@]}")
            if [[ -n "$selection" ]]; then
                # Strip annotation suffix " (...)" to get bare workspace name
                selection="${selection%% \(*}"
                if [[ -n "$current_word" ]]; then
                    LBUFFER="${LBUFFER%${current_word}}${selection} "
                else
                    LBUFFER+="${selection} "
                fi
                zle reset-prompt
            fi
            ;;
        3)
            local arg1="${tokens[2]}"
            case "$arg1" in
                --list|--home|--help|--kms)
                    return 0
                    ;;
                --rm)
                    # Completing workspace for --rm (also offer --force)
                    local -a candidates=("--force")
                    candidates+=("${(@f)$(_grove_annotated_workspaces)}")
                    local selection
                    selection=$(_grove_fzf_select "$current_word" "${candidates[@]}")
                    if [[ -n "$selection" ]]; then
                        selection="${selection%% \(*}"
                        if [[ -n "$current_word" ]]; then
                            LBUFFER="${LBUFFER%${current_word}}${selection} "
                        else
                            LBUFFER+="${selection} "
                        fi
                        zle reset-prompt
                    fi
                    ;;
                *)
                    # Completing instance for a workspace
                    local workspace="$arg1"
                    local -a candidates=()
                    if [[ -d "$workspaces_dir/$workspace" ]]; then
                        for inst_dir in "$workspaces_dir/$workspace"/*(N/); do
                            candidates+=(${inst_dir:t})
                        done
                    fi
                    if (( ${#candidates} == 0 )); then
                        zle -M "No existing instances for $workspace — type a new name"
                        return 0
                    fi
                    local selection
                    selection=$(_grove_fzf_select "$current_word" "${candidates[@]}")
                    if [[ -n "$selection" ]]; then
                        if [[ -n "$current_word" ]]; then
                            LBUFFER="${LBUFFER%${current_word}}${selection} "
                        else
                            LBUFFER+="${selection} "
                        fi
                        zle reset-prompt
                    fi
                    ;;
            esac
            ;;
        4)
            local arg1="${tokens[2]}"
            case "$arg1" in
                --rm)
                    local arg2="${tokens[3]}"
                    if [[ "$arg2" == "--force" ]]; then
                        # Completing workspace after --rm --force
                        local -a candidates=()
                        candidates+=("${(@f)$(_grove_annotated_workspaces)}")
                        local selection
                        selection=$(_grove_fzf_select "$current_word" "${candidates[@]}")
                        if [[ -n "$selection" ]]; then
                            selection="${selection%% \(*}"
                            if [[ -n "$current_word" ]]; then
                                LBUFFER="${LBUFFER%${current_word}}${selection} "
                            else
                                LBUFFER+="${selection} "
                            fi
                            zle reset-prompt
                        fi
                    else
                        # Completing instance for --rm <workspace>
                        local workspace="$arg2"
                        local -a candidates=()
                        if [[ -d "$workspaces_dir/$workspace" ]]; then
                            for inst_dir in "$workspaces_dir/$workspace"/*(N/); do
                                candidates+=(${inst_dir:t})
                            done
                        fi
                        if (( ${#candidates} == 0 )); then
                            zle -M "No instances for $workspace"
                            return 0
                        fi
                        local selection
                        selection=$(_grove_fzf_select "$current_word" "${candidates[@]}")
                        if [[ -n "$selection" ]]; then
                            if [[ -n "$current_word" ]]; then
                                LBUFFER="${LBUFFER%${current_word}}${selection} "
                            else
                                LBUFFER+="${selection} "
                            fi
                            zle reset-prompt
                        fi
                    fi
                    ;;
                *)
                    # Position 4 for normal flow: command completion — fall through to default
                    zle "${_grove_orig_tab_widget:-expand-or-complete}"
                    return
                    ;;
            esac
            ;;
        5)
            local arg1="${tokens[2]}"
            if [[ "$arg1" == "--rm" && "${tokens[3]}" == "--force" ]]; then
                # Completing instance for --rm --force <workspace>
                local workspace="${tokens[4]}"
                local -a candidates=()
                if [[ -d "$workspaces_dir/$workspace" ]]; then
                    for inst_dir in "$workspaces_dir/$workspace"/*(N/); do
                        candidates+=(${inst_dir:t})
                    done
                fi
                if (( ${#candidates} == 0 )); then
                    zle -M "No instances for $workspace"
                    return 0
                fi
                local selection
                selection=$(_grove_fzf_select "$current_word" "${candidates[@]}")
                if [[ -n "$selection" ]]; then
                    if [[ -n "$current_word" ]]; then
                        LBUFFER="${LBUFFER%${current_word}}${selection} "
                    else
                        LBUFFER+="${selection} "
                    fi
                    zle reset-prompt
                fi
            else
                zle "${_grove_orig_tab_widget:-expand-or-complete}"
                return
            fi
            ;;
        *)
            # Beyond our completion positions — fall through to default
            zle "${_grove_orig_tab_widget:-expand-or-complete}"
            return
            ;;
    esac
}

# Register the fzf completion widget, preserving the original tab binding
if _grove_fzf_available; then
    # Save whatever widget is currently bound to tab, skipping our own widget
    _grove_orig_tab_widget="${$(bindkey '^I' 2>/dev/null)##*\" }"
    if [[ "$_grove_orig_tab_widget" == "_grove_fzf_complete_widget" || -z "$_grove_orig_tab_widget" ]]; then
        _grove_orig_tab_widget="expand-or-complete"
    fi

    # Stub _grove_comp so any cached compdef doesn't error when standard
    # completion falls through (e.g. position 4+ for command args)
    _grove_comp() { return 0; }
    compdef _grove_comp gv

    zle -N _grove_fzf_complete_widget
    bindkey '^I' _grove_fzf_complete_widget
else
    # Fallback: standard zsh completion without fzf
    _grove_comp() {
        local workspaces_dir="$GROVE_WORKSPACES_DIR"

        _grove_workspaces_list() {
            local -a ws_names displays
            local -a all_ws=(${(s: :)$(_grove_list_all_workspaces)})
            for name in "${all_ws[@]}"; do
                ws_names+=("$name")
                displays+=("$name")
            done
            compadd -l -d displays -V workspaces -a ws_names
        }

        _grove_instances() {
            local workspace="$1"
            local -a instances displays
            if [[ -d "$workspaces_dir/$workspace" ]]; then
                for inst_dir in "$workspaces_dir/$workspace"/*(N/); do
                    instances+=(${inst_dir:t})
                    displays+=("${inst_dir:t}")
                done
            fi
            if (( ${#instances} > 0 )); then
                compadd -l -d displays -V instances -a instances
            else
                _message 'new instance name'
            fi
        }

        case "${words[2]}" in
            --list|--home|--help|--kms)
                return 0
                ;;
            --rm)
                case $CURRENT in
                    3)
                        local -a force_opt=('--force:Force remove workspace with uncommitted changes')
                        _describe -t options 'option' force_opt
                        _grove_workspaces_list
                        ;;
                    4)
                        if [[ "${words[3]}" == "--force" ]]; then
                            _grove_workspaces_list
                        else
                            _grove_instances "${words[3]}"
                        fi
                        ;;
                    5)
                        if [[ "${words[3]}" == "--force" ]]; then
                            _grove_instances "${words[4]}"
                        fi
                        ;;
                esac
                ;;
            *)
                case $CURRENT in
                    2)
                        local -a flags=('--help:Show usage guide' '--home:cd to projects directory' '--kms:Remove current workspace' '--list:List all workspaces' '--rm:Remove a workspace')
                        _describe -t flags 'flag' flags
                        _grove_workspaces_list
                        ;;
                    3)
                        _grove_instances "${words[2]}"
                        ;;
                    4)
                        local -a common_commands=(
                            'claude:Start Claude Code session'
                            'gst:Git status'
                            'gaa:Git add all'
                            'gcmsg:Git commit with message'
                            'gp:Git push'
                            'gco:Git checkout'
                            'gd:Git diff'
                            'gl:Git log'
                            'npm:Run npm commands'
                            'yarn:Run yarn commands'
                            'make:Run make commands'
                        )
                        _describe -t commands 'command' common_commands
                        _command_names -e
                        ;;
                    *)
                        _normal
                        ;;
                esac
                ;;
        esac
    }
    compdef _grove_comp gv
fi
