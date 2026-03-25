#!/usr/bin/env zsh
# grove-tui.zsh — Interactive TUI mode for grove (fzf-powered dashboard)
#
# Provides `_grove_tui` which is invoked when `gv` is called with no arguments.
# Shows all workspace instances in an fzf list with preview, plus keybindings
# for creating and removing instances.
#
# Requires fzf. Sourced by grove.zsh; all helper functions come from there.

# Guard: skip entirely if fzf is not available
_grove_fzf_available 2>/dev/null || return 0

# ─── Parsing helper ──────────────────────────────────────────────────────────
# Parse workspace and instance from an fzf entry line.
# Sets REPLY_WS and REPLY_INST in the caller's scope.
_grove_tui_parse_selection() {
    local line="$1"
    # Strip ANSI escape codes
    local clean=$(echo "$line" | sed $'s/\x1b\\[[0-9;]*m//g')
    # Field 1 (tab-separated): [workspace]  →  extract name from brackets
    local field1="${clean%%$'\t'*}"
    REPLY_WS="${field1%%]*}"
    REPLY_WS="${REPLY_WS#\[}"
    REPLY_WS="${REPLY_WS## }"
    REPLY_WS="${REPLY_WS%% }"
    # Field 2 is tmux icon — skip it
    local rest="${clean#*$'\t'}"
    rest="${rest#*$'\t'}"
    # Field 3 (tab-separated): instance name (may have trailing spaces from padding)
    local field3="${rest%%$'\t'*}"
    # Trim leading/trailing spaces (use sed for reliable multi-space trim)
    REPLY_INST=$(echo "$field3" | sed 's/^ *//;s/ *$//')
}

# ─── List entries ────────────────────────────────────────────────────────────
# Generate one line per workspace instance for the fzf main screen.
# Format: [workspace]  ●/✗  instance  branch
# Columns are tab-separated, space-padded and aligned; ANSI colors for display.
_grove_tui_list_entries() {
    local workspaces_dir="$GROVE_WORKSPACES_DIR"
    local -a all_ws=(${(s: :)$(_grove_list_all_workspaces)})

    local c_reset=$'\e[0m'
    local c_ws=$'\e[1;36m'        # bold cyan — workspace name
    local c_inst=$'\e[0;37m'      # white — instance name
    local c_branch=$'\e[0;32m'    # green — branch
    local c_tmux_on=$'\e[0;32m'   # green — tmux active
    local c_tmux_off=$'\e[0;31m'  # red — no tmux

    # Pass 1: collect data and measure column widths
    local -a rows=()  # each row: ws_name|instance_name|branch|has_tmux
    local max_ws=0 max_inst=0
    local ws_name instance_dir instance_name session_name branch project_dir project

    for ws_name in "${all_ws[@]}"; do
        [[ -d "$workspaces_dir/$ws_name" ]] || continue

        for instance_dir in "$workspaces_dir/$ws_name"/*(N/); do
            instance_name="${instance_dir:t}"
            session_name=$(_grove_tmux_session_name "$ws_name" "$instance_name")

            # Get branch from first project worktree
            branch=""
            for project_dir in "$instance_dir"/*(N/); do
                project="${project_dir:t}"
                [[ "$project" == .* ]] && continue
                if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
                    branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                    break
                fi
            done

            local has_tmux=0
            tmux has-session -t "$session_name" 2>/dev/null && has_tmux=1

            # Track max widths (including brackets for workspace)
            local ws_display="[${ws_name}]"
            (( ${#ws_display} > max_ws )) && max_ws=${#ws_display}
            (( ${#instance_name} > max_inst )) && max_inst=${#instance_name}

            rows+=("${ws_name}|${instance_name}|${branch}|${has_tmux}")
        done
    done

    # Ensure headings fit
    (( ${#:- Workspace} > max_ws )) && max_ws=${#:- Workspace}
    (( ${#:-Name} > max_inst )) && max_inst=${#:-Name}

    # Column headings
    local c_dim=$'\e[0;90m'
    local ws_hdr=$(printf "%-${max_ws}s" "Workspace")
    local inst_hdr=$(printf "%-${max_inst}s" "Name")
    echo "${c_dim}${ws_hdr}${c_reset}\t${c_dim}Tmux${c_reset}\t${c_dim}${inst_hdr}${c_reset}\t${c_dim}Branch${c_reset}"

    # Data rows
    local row ws inst br tmux_flag tmux_icon ws_padded inst_padded
    for row in "${rows[@]}"; do
        ws="${row%%|*}";        row="${row#*|}"
        inst="${row%%|*}";      row="${row#*|}"
        br="${row%%|*}";        tmux_flag="${row##*|}"

        if (( tmux_flag )); then
            tmux_icon="  ${c_tmux_on}●${c_reset} "
        else
            tmux_icon="  ${c_tmux_off}✗${c_reset} "
        fi

        ws_padded=$(printf "%-${max_ws}s" "[${ws}]")
        inst_padded=$(printf "%-${max_inst}s" "$inst")

        echo "${c_ws}${ws_padded}${c_reset}\t${tmux_icon}\t${c_inst}${inst_padded}${c_reset}\t${c_branch}${br}${c_reset}"
    done
}

# ─── Preview ─────────────────────────────────────────────────────────────────
# Show details for the highlighted instance in fzf's preview pane.
# Receives the raw fzf line as $1, parses out workspace and instance.
_grove_tui_preview() {
    local line="$1"
    local workspaces_dir="$GROVE_WORKSPACES_DIR"

    local REPLY_WS REPLY_INST
    _grove_tui_parse_selection "$line"
    local ws_name="$REPLY_WS"
    local instance_name="$REPLY_INST"

    local instance_dir="$workspaces_dir/$ws_name/$instance_name"
    if [[ ! -d "$instance_dir" ]]; then
        echo "Instance not found"
        return 1
    fi

    # Header
    local projects
    projects=$(_grove_resolve_workspace_projects "$ws_name" 2>/dev/null)
    local -a project_list=(${(s: :)projects})

    echo "\e[1;36m[$ws_name]\e[0m"
    if (( ${#project_list} > 1 )); then
        echo "Type: multi-repo"
        echo "Projects: ${(j:, :)project_list}"
    else
        echo "Type: single-repo"
    fi
    echo ""

    # Per-project details
    local project_dir project branch last_commit status_line
    for project_dir in "$instance_dir"/*(N/); do
        project="${project_dir:t}"
        [[ "$project" == .* ]] && continue
        if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
            branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
            last_commit=$(git -C "$project_dir" log -1 --format="%h %s" 2>/dev/null)

            # Check dirty status
            if ! git -C "$project_dir" diff --quiet 2>/dev/null || \
               ! git -C "$project_dir" diff --cached --quiet 2>/dev/null || \
               [[ -n "$(git -C "$project_dir" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                status_line="\e[0;31m[dirty]\e[0m"
            else
                status_line="\e[0;32m[clean]\e[0m"
            fi

            echo "\e[0;33m${project}\e[0m  ${status_line}"
            echo "  Branch: \e[0;32m${branch}\e[0m"
            echo "  Last:   ${last_commit}"
            echo ""
        fi
    done

    # tmux status
    local session_name=$(_grove_tmux_session_name "$ws_name" "$instance_name")
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "\e[0;33m● tmux session active\e[0m ($session_name)"
    else
        echo "No tmux session"
    fi
}

# ─── New instance flow ───────────────────────────────────────────────────────
_grove_tui_new() {
    # Step 1: select workspace
    local -a candidates=("${(@f)$(_grove_annotated_workspaces)}")
    if (( ${#candidates} == 0 )); then
        echo "No workspaces configured and no project directories found."
        return 1
    fi

    echo "Select a workspace:"
    local workspace
    workspace=$(_grove_fzf_select "" "${candidates[@]}") || return 1
    # Strip annotation suffix " (...)"
    workspace="${workspace%% \(*}"

    if [[ -z "$workspace" ]]; then
        return 1
    fi

    # Step 2: enter instance name
    local name=""
    echo ""
    read -r "name?Instance name: "
    if [[ -z "$name" ]]; then
        echo "No name provided."
        return 1
    fi

    # Step 3: create
    gv "$workspace" "$name"
}

# ─── Main TUI ───────────────────────────────────────────────────────────────
_grove_tui() {
    local entries
    entries=$(_grove_tui_list_entries)

    # Empty state: jump straight to new instance flow
    if [[ -z "$entries" ]]; then
        echo "No workspace instances yet. Let's create one."
        echo ""
        _grove_tui_new
        return $?
    fi

    # Determine preview command — need to re-source grove.zsh in the subprocess
    local _grove_tui_script_dir="${${(%):-%x}:A:h}"
    local preview_cmd="zsh -c 'source \"${_grove_tui_script_dir}/grove.zsh\"; _grove_tui_preview \"\$1\"' -- {}"

    # Main fzf screen with --expect to capture keybindings
    local result
    result=$(echo "$entries" | fzf \
        --ansi \
        --delimiter=$'\t' \
        --nth=1,3 \
        --tabstop=2 \
        --header="Grove  (enter: open  ctrl-n: new  del/ctrl-x: remove)" \
        --header-lines=1 \
        --preview="$preview_cmd" \
        --preview-window=right:40%:wrap \
        --height=80% \
        --layout=reverse \
        --no-sort \
        --color='hl:magenta:underline,hl+:magenta:underline' \
        --no-info \
        --expect="ctrl-n,ctrl-x,del")

    # --expect outputs two lines: first is the key pressed, second is the selected item
    local key="${result%%$'\n'*}"
    local selection="${result#*$'\n'}"

    if [[ -z "$selection" ]]; then
        return 0
    fi

    # Parse workspace and instance from the selected line
    local REPLY_WS REPLY_INST
    _grove_tui_parse_selection "$selection"
    local ws_name="$REPLY_WS"
    local instance_name="$REPLY_INST"

    if [[ -z "$ws_name" || -z "$instance_name" ]]; then
        return 0
    fi

    case "$key" in
        ctrl-n)
            _grove_tui_new
            ;;
        ctrl-x|del)
            # Remove the currently highlighted instance
            local confirm=""
            read -r "confirm?Remove ${ws_name}/${instance_name}? [Y/n] "
            if [[ -z "$confirm" || "$confirm" == [yY] ]]; then
                gv --rm "$ws_name" "$instance_name"
            else
                echo "Cancelled."
            fi
            ;;
        *)
            gv "$ws_name" "$instance_name"
            ;;
    esac
}
