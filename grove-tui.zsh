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

    # Calculate max column widths based on terminal width
    # fzf preview takes ~40%, so list area is ~60% of terminal
    local term_cols=${COLUMNS:-120}
    local list_cols=$(( term_cols * 60 / 100 ))
    local tmux_col=4  # "Tmux" / "  ● "
    local gaps=4       # tab stops between columns
    local avail=$(( list_cols - tmux_col - gaps ))

    # Allocate: workspace gets its natural width (capped at 25%),
    # then name and branch split the remainder
    local max_ws_cap=$(( avail * 25 / 100 ))
    (( max_ws > max_ws_cap )) && max_ws=$max_ws_cap
    local remaining=$(( avail - max_ws ))
    local max_inst_cap=$(( remaining * 45 / 100 ))
    local max_br_cap=$(( remaining * 55 / 100 ))

    # Clamp to caps (but don't expand beyond natural width)
    (( max_inst > max_inst_cap )) && max_inst=$max_inst_cap

    # Truncation helper: truncate string to max len with ".." suffix
    _grove_tui_trunc() {
        local str="$1" max="$2"
        if (( ${#str} > max )); then
            echo "${str[1, max - 2]}.."
        else
            echo "$str"
        fi
    }

    # Column headings
    local c_dim=$'\e[0;90m'
    local ws_hdr=$(printf "%-${max_ws}s" "Workspace")
    local inst_hdr=$(printf "%-${max_inst}s" "Name")
    echo "${c_dim}${ws_hdr}${c_reset}\t${c_dim}Tmux${c_reset}\t${c_dim}${inst_hdr}${c_reset}\t${c_dim}Branch${c_reset}"

    # Data rows
    local row ws inst br tmux_flag tmux_icon ws_padded inst_padded br_display
    for row in "${rows[@]}"; do
        ws="${row%%|*}";        row="${row#*|}"
        inst="${row%%|*}";      row="${row#*|}"
        br="${row%%|*}";        tmux_flag="${row##*|}"

        if (( tmux_flag )); then
            tmux_icon="  ${c_tmux_on}●${c_reset} "
        else
            tmux_icon="  ${c_tmux_off}✗${c_reset} "
        fi

        local ws_text=$(_grove_tui_trunc "[${ws}]" $max_ws)
        local inst_text=$(_grove_tui_trunc "$inst" $max_inst)
        br_display=$(_grove_tui_trunc "$br" $max_br_cap)

        ws_padded=$(printf "%-${max_ws}s" "$ws_text")
        inst_padded=$(printf "%-${max_inst}s" "$inst_text")

        echo "${c_ws}${ws_padded}${c_reset}\t${tmux_icon}\t${c_inst}${inst_padded}${c_reset}\t${c_branch}${br_display}${c_reset}"
    done
}

# ─── Preview label ────────────────────────────────────────────────────────────
# Generate the dynamic preview pane border title.
_grove_tui_label() {
    local REPLY_WS REPLY_INST
    _grove_tui_parse_selection "$1"
    local t="single-repo"
    _grove_is_multi_project "$REPLY_WS" 2>/dev/null && t="multi-repo"
    echo " [${REPLY_WS}]/${REPLY_INST} | ${t} "
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

    # tmux status
    local session_name=$(_grove_tmux_session_name "$ws_name" "$instance_name")
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "\e[0;33m● tmux session active\e[0m ($session_name)"
    else
        echo "No tmux session"
    fi
    echo ""

    # Kick off parallel PR status fetches for all projects
    local -A pr_tmpfiles=()
    local project_dir project branch repo_url
    if command -v gh &>/dev/null; then
        for project_dir in "$instance_dir"/*(N/); do
            project="${project_dir:t}"
            [[ "$project" == .* ]] && continue
            if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
                branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
                repo_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null)
                if [[ -n "$branch" && -n "$repo_url" ]]; then
                    local tmpf=$(mktemp)
                    pr_tmpfiles[$project]="$tmpf"
                    gh pr view "$branch" --repo "$repo_url" \
                        --json state,mergeable,reviewDecision,statusCheckRollup \
                        --jq '{state, mergeable, reviewDecision, ci: ([.statusCheckRollup[] | if .status == "COMPLETED" then (if .conclusion == "SUCCESS" or .conclusion == "SKIPPED" then "ok" else "fail" end) elif .status == "IN_PROGRESS" then "pending" else "ok" end] | if any(. == "fail") then "FAILURE" elif any(. == "pending") then "PENDING" else "SUCCESS" end)}' \
                        > "$tmpf" 2>/dev/null &
                fi
            fi
        done
        wait
    fi

    # Per-project details
    local last_commit status_line pr_info
    local pr_state pr_mergeable pr_review pr_ci_status pr_data
    local pr_state_display pr_review_display pr_merge_display pr_ci_display
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

            # Read PR status from parallel fetch
            pr_info=""
            if [[ -n "${pr_tmpfiles[$project]}" ]]; then
                pr_data=$(<"${pr_tmpfiles[$project]}")
                rm -f "${pr_tmpfiles[$project]}"
                if [[ -n "$pr_data" ]]; then
                    pr_state=$(echo "$pr_data" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
                    pr_mergeable=$(echo "$pr_data" | grep -o '"mergeable":"[^"]*"' | head -1 | cut -d'"' -f4)
                    pr_review=$(echo "$pr_data" | grep -o '"reviewDecision":"[^"]*"' | head -1 | cut -d'"' -f4)
                    pr_ci_status=$(echo "$pr_data" | grep -o '"ci":"[^"]*"' | head -1 | cut -d'"' -f4)

                    pr_state_display=""
                    case "$pr_state" in
                        OPEN)    pr_state_display="\e[0;32mOpen\e[0m" ;;
                        MERGED)  pr_state_display="\e[0;35mMerged\e[0m" ;;
                        CLOSED)  pr_state_display="\e[0;31mClosed\e[0m" ;;
                        *)       pr_state_display="$pr_state" ;;
                    esac

                    pr_review_display=""
                    case "$pr_review" in
                        APPROVED)          pr_review_display="  \e[0;32m✓ Approved\e[0m" ;;
                        CHANGES_REQUESTED) pr_review_display="  \e[0;31m✗ Changes requested\e[0m" ;;
                        REVIEW_REQUIRED)   pr_review_display="  \e[0;33m● Review required\e[0m" ;;
                    esac

                    pr_merge_display=""
                    case "$pr_mergeable" in
                        MERGEABLE)   pr_merge_display="  \e[0;32m↑ Mergeable\e[0m" ;;
                        CONFLICTING) pr_merge_display="  \e[0;31m⚡ Conflicts\e[0m" ;;
                    esac

                    pr_ci_display=""
                    case "$pr_ci_status" in
                        FAILURE) pr_ci_display="  \e[0;31m✗ CI failing\e[0m" ;;
                        PENDING) pr_ci_display="  \e[0;33m● CI running\e[0m" ;;
                        SUCCESS) pr_ci_display="  \e[0;32m✓ CI passed\e[0m" ;;
                    esac

                    pr_info="  PR:     ${pr_state_display}${pr_review_display}${pr_merge_display}${pr_ci_display}"
                else
                    pr_info="  PR:     \e[0;90mNo PR\e[0m"
                fi
            fi

            echo "\e[0;33m${project}\e[0m  ${status_line}"
            echo "  Branch: \e[0;32m${branch}\e[0m"
            echo "  Last:   ${last_commit}"
            [[ -n "$pr_info" ]] && echo "$pr_info"
            echo ""
        fi
    done

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

    # Extract workspace/instance + repo type for preview label
    local label_cmd="zsh -c 'source \"${_grove_tui_script_dir}/grove.zsh\"; _grove_tui_label \"\$1\"' -- {}"

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
        --preview-label="" \
        --bind="focus:transform-preview-label($label_cmd)" \
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
