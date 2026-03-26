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

# ─── Branch tree helper ───────────────────────────────────────────────────────
# Render branches as a tree in gt-ls style.
# Usage: _grove_tui_render_branch_tree <project_dir> [branch1 branch2 ...]
# Output format (gt ls style):
#   ○   branch-d
#   ○   branch-c
#   │ ○ branch-e        (side branch off branch-b)
#   ○─┘ branch-b        (fork point)
#   ○   branch-a
#
# Linear stacks stay at the same column. Fork points show ─┘ or ─┴─┘.
# Side branches get their own │ column that persists until the fork point.
# Children appear before parents (leaves at top, roots at bottom).
_grove_tui_render_branch_tree() {
    local project_dir="$1"
    shift
    local -a branch_args=("$@")

    # Read parent relationships into parallel arrays
    local -a names=() parents=()
    local line b parent
    if (( ${#branch_args} > 0 )); then
        while read -r line; do
            b="${line%%|*}"
            parent="${line#*|}"
            [[ -n "$b" ]] && names+=("$b") && parents+=("$parent")
        done < <(_grove_worktree_branch_parents "$project_dir" "${branch_args[@]}")
    else
        while read -r line; do
            b="${line%%|*}"
            parent="${line#*|}"
            [[ -n "$b" ]] && names+=("$b") && parents+=("$parent")
        done < <(_grove_worktree_branch_parents "$project_dir")
    fi

    local i j

    # Find children for each branch (by index)
    local -a children_lists=()
    (( i = 1 ))
    while (( i <= ${#names} )); do
        local kids=""
        (( j = 1 ))
        while (( j <= ${#names} )); do
            if [[ "${parents[$j]}" == "${names[$i]}" ]]; then
                [[ -n "$kids" ]] && kids+=" "
                kids+="$j"
            fi
            (( j++ ))
        done
        children_lists+=("$kids")
        (( i++ ))
    done

    # Find roots (branches with no parent)
    local -a roots=()
    (( i = 1 ))
    while (( i <= ${#names} )); do
        [[ -z "${parents[$i]}" ]] && roots+=("$i")
        (( i++ ))
    done

    # Compute max descendant chain depth for a node (for choosing main child)
    _chain_depth() {
        local idx="$1"
        local kids="${children_lists[$idx]}"
        if [[ -z "$kids" ]]; then
            echo "0"
            return
        fi
        local max_d=0 child_d ci
        for ci in ${(s: :)kids}; do
            child_d=$(_chain_depth "$ci")
            (( child_d + 1 > max_d )) && (( max_d = child_d + 1 ))
        done
        echo "$max_d"
    }

    # For a node with multiple children, pick the main child (deepest chain first,
    # then higher index for ties). Returns the index.
    _pick_main_child() {
        local -a child_indices=(${(s: :)1})
        local main_idx="${child_indices[1]}"
        local main_depth=$(_chain_depth "$main_idx")
        local si cd
        (( si = 2 ))
        while (( si <= ${#child_indices} )); do
            cd=$(_chain_depth "${child_indices[$si]}")
            if (( cd > main_depth )) || \
               (( cd == main_depth && child_indices[si] > main_idx )); then
                main_idx="${child_indices[$si]}"
                main_depth="$cd"
            fi
            (( si++ ))
        done
        echo "$main_idx"
    }

    # === gt-ls style rendering ===
    # DFS walk producing ordered lines. Each side branch subtree gets a │ column
    # that persists from its first node down to the fork point.
    #
    # The walk processes: main child subtree first, then each side branch subtree.
    # The fork-point node renders with ─┘ (1 side branch) or ─┴─┘ (2+).

    local -a output_lines=()

    # _gt_walk renders a subtree rooted at node_idx.
    # col_depth: number of │ columns to the LEFT of this subtree (from ancestor forks)
    _gt_walk() {
        local node_idx="$1" col_depth="$2"
        local node_name="${names[$node_idx]}"
        local kids="${children_lists[$node_idx]}"
        local -a child_indices=()
        [[ -n "$kids" ]] && child_indices=(${(s: :)kids})

        local num_children=${#child_indices}

        if (( num_children == 0 )); then
            # Leaf node
            local prefix=""
            (( j = 0 ))
            while (( j < col_depth )); do
                prefix+="│ "
                (( j++ ))
            done
            output_lines+=("${prefix}○ ${node_name}")

        elif (( num_children == 1 )); then
            # Single child — continues the line, no fork
            _gt_walk "${child_indices[1]}" "$col_depth"
            local prefix=""
            (( j = 0 ))
            while (( j < col_depth )); do
                prefix+="│ "
                (( j++ ))
            done
            output_lines+=("${prefix}○ ${node_name}")

        else
            # Multiple children — fork point
            local main_child=$(_pick_main_child "$kids")
            local -a side_children=()
            local ci
            for ci in "${child_indices[@]}"; do
                [[ "$ci" != "$main_child" ]] && side_children+=("$ci")
            done
            local num_sides=${#side_children}

            # Walk main child at current col_depth (it continues the main line)
            _gt_walk "$main_child" "$col_depth"

            # Walk each side branch at increasing col_depth
            local si=0
            for ci in "${side_children[@]}"; do
                _gt_walk "$ci" "$(( col_depth + si + 1 ))"
                (( si++ ))
            done

            # Render fork point: ○─┘ or ○─┴─┘ etc.
            local prefix=""
            (( j = 0 ))
            while (( j < col_depth )); do
                prefix+="│ "
                (( j++ ))
            done
            prefix+="○"
            (( j = 0 ))
            while (( j < num_sides )); do
                if (( j == num_sides - 1 )); then
                    prefix+="─┘"
                else
                    prefix+="─┴"
                fi
                (( j++ ))
            done
            output_lines+=("${prefix} ${node_name}")
        fi
    }

    # Walk each root
    for i in "${roots[@]}"; do
        _gt_walk "$i" "0"
    done

    # Output all lines
    local l
    for l in "${output_lines[@]}"; do
        echo "$l"
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

    # tmux status
    local session_name=$(_grove_tmux_session_name "$ws_name" "$instance_name")
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "\e[0;33m● tmux session active\e[0m ($session_name)"
    else
        echo "No tmux session"
    fi
    echo ""

    # Collect all branches per project and kick off parallel PR fetches
    local -A pr_tmpfiles=()
    local project_dir project branch repo_url head_branch
    local -a all_branches
    local tmpf b

    if command -v gh &>/dev/null; then
        for project_dir in "$instance_dir"/*(N/); do
            project="${project_dir:t}"
            [[ "$project" == .* ]] && continue
            if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
                repo_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null)
                all_branches=("${(@f)$(_grove_worktree_branches "$project_dir")}")
                for b in "${all_branches[@]}"; do
                    [[ -z "$b" ]] && continue
                    tmpf=$(mktemp)
                    pr_tmpfiles["${project}:${b}"]="$tmpf"
                    gh pr view "$b" --repo "$repo_url" \
                        --json number,url,state,mergeable,reviewDecision,statusCheckRollup \
                        --jq '{number, url, state, mergeable, reviewDecision, ci: ([.statusCheckRollup[] | if .status == "COMPLETED" then (if .conclusion == "SUCCESS" or .conclusion == "SKIPPED" then "ok" else "fail" end) elif .status == "IN_PROGRESS" then "pending" else "ok" end] | if any(. == "fail") then "FAILURE" elif any(. == "pending") then "PENDING" else "SUCCESS" end)}' \
                        > "$tmpf" 2>/dev/null &
                done
            fi
        done
        wait
    fi

    # Helper: format PR status from fetched data
    _grove_tui_format_pr() {
        local pr_data="$1"
        if [[ -z "$pr_data" ]]; then
            echo "\e[0;90mNo PR\e[0m"
            return
        fi
        local pr_state pr_mergeable pr_review pr_ci_status pr_number pr_url
        pr_state=$(echo "$pr_data" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
        pr_number=$(echo "$pr_data" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)
        pr_url=$(echo "$pr_data" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
        pr_mergeable=$(echo "$pr_data" | grep -o '"mergeable":"[^"]*"' | head -1 | cut -d'"' -f4)
        pr_review=$(echo "$pr_data" | grep -o '"reviewDecision":"[^"]*"' | head -1 | cut -d'"' -f4)
        pr_ci_status=$(echo "$pr_data" | grep -o '"ci":"[^"]*"' | head -1 | cut -d'"' -f4)

        # PR number as clickable link (OSC 8 hyperlink)
        local result=""
        if [[ -n "$pr_number" && -n "$pr_url" ]]; then
            result+="\e]8;;${pr_url}\e\\PR #${pr_number}\e]8;;\e\\"
        else
            result+="PR"
        fi
        result+="  "
        case "$pr_state" in
            OPEN)    result+="\e[0;32mOpen\e[0m" ;;
            MERGED)  result+="\e[0;35mMerged\e[0m" ;;
            CLOSED)  result+="\e[0;31mClosed\e[0m" ;;
            *)       result+="$pr_state" ;;
        esac
        case "$pr_review" in
            APPROVED)          result+="  \e[0;32m✓ Approved\e[0m" ;;
            CHANGES_REQUESTED) result+="  \e[0;31m✗ Changes requested\e[0m" ;;
            REVIEW_REQUIRED)   result+="  \e[0;33m● Review required\e[0m" ;;
        esac
        case "$pr_mergeable" in
            MERGEABLE)   result+="  \e[0;32m↑ Mergeable\e[0m" ;;
            CONFLICTING) result+="  \e[0;31m⚡ Conflicts\e[0m" ;;
        esac
        case "$pr_ci_status" in
            FAILURE) result+="  \e[0;31m✗ CI failing\e[0m" ;;
            PENDING) result+="  \e[0;33m● CI running\e[0m" ;;
            SUCCESS) result+="  \e[0;32m✓ CI passed\e[0m" ;;
        esac
        echo "$result"
    }

    # Per-project details with all branches
    local status_line pr_data pr_display tree_line indent marker suffix pr_key pr_indent
    for project_dir in "$instance_dir"/*(N/); do
        project="${project_dir:t}"
        [[ "$project" == .* ]] && continue
        if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
            head_branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
            all_branches=("${(@f)$(_grove_worktree_branches "$project_dir")}")

            # Check dirty status
            if ! git -C "$project_dir" diff --quiet 2>/dev/null || \
               ! git -C "$project_dir" diff --cached --quiet 2>/dev/null || \
               [[ -n "$(git -C "$project_dir" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                status_line="\e[0;31m[dirty]\e[0m"
            else
                status_line="\e[0;32m[clean]\e[0m"
            fi

            echo "\e[0;33m${project}\e[0m  ${status_line}"

            # Render branch tree
            while read -r tree_line; do
                [[ -z "$tree_line" ]] && continue

                # Extract branch name: everything after the last "○" connector + space
                # Formats: "○ name", "│ ○ name", "○─┘ name", "○─┴─┘ name"
                # The name always follows the last space in the line
                b="${tree_line##* }"
                indent="${tree_line% *}"

                # Build colored version of the line (replace ○ with marker)
                marker="○"
                suffix=""
                if [[ "$b" == "$head_branch" ]]; then
                    marker="\e[1;37m◉\e[0m"
                    suffix="  \e[0;90m← HEAD\e[0m"
                fi

                # PR status
                pr_data=""
                pr_key="${project}:${b}"
                if [[ -n "${pr_tmpfiles["$pr_key"]}" ]]; then
                    pr_data=$(<"${pr_tmpfiles["$pr_key"]}")
                    rm -f "${pr_tmpfiles["$pr_key"]}"
                fi
                pr_display=$(_grove_tui_format_pr "$pr_data")

                # Replace ○ in indent with colored marker
                local colored_indent="${indent//○/${marker}}"

                echo "  ${colored_indent} \e[0;32m${b}\e[0m${suffix}"
                # PR line: replace all drawing chars with spaces for alignment
                local pr_indent="${indent//[○│─┘┴]/ }"
                echo "  ${pr_indent}  ${pr_display}"
            done < <(_grove_tui_render_branch_tree "$project_dir")
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
