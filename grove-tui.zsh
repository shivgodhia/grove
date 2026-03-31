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
    # Column 1 (tab-separated, hidden from display) contains "workspace|instance"
    local metadata="${line%%$'\t'*}"
    REPLY_WS="${metadata%%|*}"
    REPLY_INST="${metadata#*|}"
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
    (( ${#:- Project} > max_ws )) && max_ws=${#:- Project}
    (( ${#:-Workspace} > max_inst )) && max_inst=${#:-Workspace}

    # Calculate max column widths based on terminal width
    # fzf preview takes ~65%, so list area is ~35% of terminal
    local term_cols=${COLUMNS:-120}
    local list_cols=$(( term_cols * 35 / 100 ))
    local tmux_col=4  # "Tmux" / "  ● "
    local gaps=4       # tab stops between columns
    local avail=$(( list_cols - tmux_col - gaps ))

    # Allocate: workspace gets its natural width (capped at 25%),
    # then name and branch split the remainder evenly
    local max_ws_cap=$(( avail * 25 / 100 ))
    (( max_ws > max_ws_cap )) && max_ws=$max_ws_cap
    local remaining=$(( avail - max_ws ))
    local max_inst_cap=$(( remaining * 50 / 100 ))
    local max_br_cap=$(( remaining * 50 / 100 ))

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
    # Hidden column 1 (metadata) + visible columns
    local c_dim=$'\e[0;90m'
    local ws_hdr=$(printf "%-${max_ws}s" "Project")
    local inst_hdr=$(printf "%-${max_inst}s" "Workspace")
    echo "_\t${c_dim}${ws_hdr}${c_reset}\t${c_dim}Tmux${c_reset}\t${c_dim}${inst_hdr}${c_reset}\t${c_dim}Branch${c_reset}"

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

        echo "${ws}|${inst}\t${c_ws}${ws_padded}${c_reset}\t${tmux_icon}\t${c_inst}${inst_padded}${c_reset}\t${c_branch}${br_display}${c_reset}"
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

# ─── Timing Helpers ───────────────────────────────────────────────────────────
# Opt-in via GROVE_TUI_TIMING=1 (or "stderr"). Logs to:
#   ${GROVE_TUI_TIMING_LOG_FILE:-${TMPDIR:-/tmp}/grove-tui-timing.log}
_grove_tui_timing_enabled() {
    [[ -n "$GROVE_TUI_TIMING" ]]
}

_grove_tui_now_us() {
    zmodload -F zsh/datetime b:EPOCHREALTIME 2>/dev/null || true
    local t="${EPOCHREALTIME-}"
    if [[ -z "$t" ]]; then
        # Fallback for environments where EPOCHREALTIME is unavailable.
        # Only used when timing is enabled.
        perl -MTime::HiRes=time -e 'printf("%.0f\n", time()*1000000)' 2>/dev/null && return
        echo $(( SECONDS * 1000000 ))
        return
    fi
    local sec="${t%%.*}"
    local frac="${t#*.}"
    frac="${frac}000000"
    frac="${frac[1,6]}"
    echo $(( 10#$sec * 1000000 + 10#$frac ))
}

_grove_tui_timing_log() {
    _grove_tui_timing_enabled || return 0
    local label="$1" start_us="$2" details="$3"
    local end_us delta_us log_file ts line
    end_us=$(_grove_tui_now_us)
    delta_us=$(( end_us - start_us ))
    log_file="${GROVE_TUI_TIMING_LOG_FILE:-${TMPDIR:-/tmp}/grove-tui-timing.log}"
    ts=$(printf '%(%H:%M:%S)T' -1 2>/dev/null)
    line="[grove-tui timing] ${ts} ${label}: $((delta_us / 1000.0))ms"
    [[ -n "$details" ]] && line="${line} (${details})"
    print -r -- "$line" >> "$log_file"
    [[ "$GROVE_TUI_TIMING" == "stderr" ]] && print -u2 -r -- "$line"
}

# ─── PR cache helpers ─────────────────────────────────────────────────────────
# Cache gh pr view results briefly so preview refreshes do not re-hit the API.
_grove_tui_pr_cache_dir() {
    local cache_dir="${TMPDIR:-/tmp}/grove-pr-cache-${USER}"
    mkdir -p "$cache_dir" 2>/dev/null || return 1
    echo "$cache_dir"
}

_grove_tui_pr_cache_key() {
    local repo_url="$1" branch="$2" sum
    sum=$(printf '%s\n%s' "$repo_url" "$branch" | cksum | awk '{print $1}')
    echo "$sum"
}

_grove_tui_pr_cache_get() {
    local repo_url="$1" branch="$2" ttl="$3"
    local cache_dir cache_file now ts payload age no_pr_ttl err_ttl
    cache_dir=$(_grove_tui_pr_cache_dir) || return 1
    cache_file="$cache_dir/$(_grove_tui_pr_cache_key "$repo_url" "$branch").cache"
    [[ -f "$cache_file" ]] || return 1

    IFS= read -r ts < "$cache_file" || return 1
    [[ "$ts" == <-> ]] || return 1
    now=$(date +%s)
    age=$(( now - ts ))

    payload=$(tail -n +2 "$cache_file" 2>/dev/null)
    no_pr_ttl="${GROVE_TUI_NO_PR_CACHE_TTL:-300}"
    err_ttl="${GROVE_TUI_ERR_CACHE_TTL:-30}"
    if [[ "$payload" == "__NO_PR__" ]]; then
        (( age <= no_pr_ttl )) || return 1
        echo ""
        return 0
    fi
    if [[ "$payload" == "__ERR__" ]]; then
        (( age <= err_ttl )) || return 1
        echo "__ERR__"
        return 0
    fi
    (( age <= ttl )) || return 1

    echo "$payload"
    return 0
}

_grove_tui_pr_cache_put() {
    local repo_url="$1" branch="$2" payload="$3"
    # Do not cache empty payloads; they can be transient.
    [[ -n "$payload" ]] || return 0
    local cache_dir cache_file tmpf now
    cache_dir=$(_grove_tui_pr_cache_dir) || return 1
    cache_file="$cache_dir/$(_grove_tui_pr_cache_key "$repo_url" "$branch").cache"
    tmpf=$(mktemp "${TMPDIR:-/tmp}/grove-pr-cache.XXXXXX") || return 1
    now=$(date +%s)
    {
        echo "$now"
        echo "$payload"
    } > "$tmpf"
    mv "$tmpf" "$cache_file" 2>/dev/null || {
        rm -f "$tmpf"
        return 1
    }
}

# Fetch PR data for a branch and emit one of:
# - JSON object (success)
# - __NO_PR__ (confirmed no PR for this branch)
# - __ERR__ (transient/API error)
_grove_tui_fetch_pr_payload() {
    local branch="$1" repo_url="$2"
    local errf out rc
    errf=$(mktemp "${TMPDIR:-/tmp}/grove-pr-fetch.XXXXXX") || return 1
    out=$(gh pr view "$branch" --repo "$repo_url" \
        --json number,url,state,isDraft,mergeable,reviewDecision,statusCheckRollup \
        --jq '{number, url, state, isDraft, mergeable, reviewDecision, ci: ([.statusCheckRollup[] | if .status == "COMPLETED" then (if .conclusion == "SUCCESS" or .conclusion == "SKIPPED" then "ok" else "fail" end) elif .status == "IN_PROGRESS" then "pending" else "ok" end] | if any(. == "fail") then "FAILURE" elif any(. == "pending") then "PENDING" else "SUCCESS" end)}' \
        2>"$errf")
    rc=$?
    if (( rc == 0 )) && [[ -n "$out" ]]; then
        print -r -- "$out"
    elif grep -qiE 'no pull requests found|could not resolve to a pullrequest' "$errf"; then
        print -r -- "__NO_PR__"
    else
        print -r -- "__ERR__"
    fi
    rm -f "$errf"
}

_grove_tui_prefetch_instance_prs() {
    local ws_name="$1" instance_name="$2"
    local instance_dir="$GROVE_WORKSPACES_DIR/$ws_name/$instance_name"
    [[ -d "$instance_dir" ]] || return 0
    command -v gh &>/dev/null || return 0

    # Prevent duplicate overlapping prefetch for the same instance.
    # Clear stale locks (e.g. killed background job) so prefetch does not get stuck off.
    local lock_dir="${TMPDIR:-/tmp}/grove-prefetch-locks-${USER}"
    mkdir -p "$lock_dir" 2>/dev/null || return 0
    local lock_key lock_path lock_pid stale_ttl now mtime
    lock_key=$(printf '%s\n%s' "$ws_name" "$instance_name" | cksum | awk '{print $1}')
    lock_path="$lock_dir/$lock_key.lock"
    if ! mkdir "$lock_path" 2>/dev/null; then
        if [[ -f "$lock_path/pid" ]]; then
            IFS= read -r lock_pid < "$lock_path/pid" || lock_pid=""
            if [[ "$lock_pid" == <-> ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$lock_path" 2>/dev/null || return 0
                mkdir "$lock_path" 2>/dev/null || return 0
            else
                return 0
            fi
        else
            stale_ttl="${GROVE_TUI_PREFETCH_LOCK_STALE_SECS:-300}"
            now=$(date +%s)
            mtime=$(stat -f %m "$lock_path" 2>/dev/null || stat -c %Y "$lock_path" 2>/dev/null || echo 0)
            if (( now - mtime > stale_ttl )); then
                rm -rf "$lock_path" 2>/dev/null || return 0
                mkdir "$lock_path" 2>/dev/null || return 0
            else
                return 0
            fi
        fi
    fi
    print -r -- "$$" > "$lock_path/pid" 2>/dev/null || true
    trap 'rm -f "$lock_path/pid" 2>/dev/null || true; rmdir "$lock_path" 2>/dev/null || true' EXIT INT TERM

    local -A pr_tmpfiles=()
    local -A pr_repo_for_key=()
    local -A pr_branch_for_key=()
    local -a all_branches
    local project_dir project repo_url b tmpf pr_key cache_data
    local cache_ttl="${GROVE_TUI_PR_CACHE_TTL:-300}"
    local prefetch_start_us hits=0 misses=0 spawned=0
    _grove_tui_timing_enabled && prefetch_start_us=$(_grove_tui_now_us)

    for project_dir in "$instance_dir"/*(N/); do
        project="${project_dir:t}"
        [[ "$project" == .* ]] && continue
        if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
            repo_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null)
            all_branches=("${(@f)$(_grove_worktree_branches "$project_dir")}")
            for b in "${all_branches[@]}"; do
                [[ -z "$b" ]] && continue
                cache_data=$(_grove_tui_pr_cache_get "$repo_url" "$b" "$cache_ttl")
                if [[ $? -eq 0 ]]; then
                    (( hits++ ))
                    continue
                fi
                (( misses++ ))

                pr_key="${project}:${b}"
                tmpf=$(mktemp)
                pr_tmpfiles["$pr_key"]="$tmpf"
                pr_repo_for_key["$pr_key"]="$repo_url"
                pr_branch_for_key["$pr_key"]="$b"
                (( spawned++ ))
                _grove_tui_fetch_pr_payload "$b" "$repo_url" > "$tmpf" 2>/dev/null &
            done
        fi
    done
    wait

    for pr_key tmpf in "${(@kv)pr_tmpfiles}"; do
        cache_data=$(<"$tmpf")
        rm -f "$tmpf"
        _grove_tui_pr_cache_put "${pr_repo_for_key[$pr_key]}" "${pr_branch_for_key[$pr_key]}" "$cache_data" >/dev/null 2>&1
    done

    _grove_tui_timing_enabled && _grove_tui_timing_log "prefetch_instance:${ws_name}/${instance_name}" "$prefetch_start_us" "hits=${hits},misses=${misses},spawned=${spawned}"
    trap - EXIT INT TERM
    rm -f "$lock_path/pid" 2>/dev/null || true
    rmdir "$lock_path" 2>/dev/null || true
}

_grove_tui_prefetch_entries_file() {
    local entries_file="$1"
    local max_items="${2:-8}"
    [[ -f "$entries_file" ]] || return 0
    command -v gh &>/dev/null || return 0

    local start_us
    _grove_tui_timing_enabled && start_us=$(_grove_tui_now_us)

    local line meta ws inst count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        meta="${line%%$'\t'*}"
        [[ "$meta" == "_" ]] && continue
        ws="${meta%%|*}"
        inst="${meta#*|}"
        _grove_tui_prefetch_instance_prs "$ws" "$inst" >/dev/null 2>&1 || true
        (( count++ ))
        (( count >= max_items )) && break
    done < "$entries_file"

    _grove_tui_timing_enabled && _grove_tui_timing_log "prefetch_startup" "$start_us" "items=${count}"
}

_grove_tui_prefetch_window() {
    local ws_name="$1" instance_name="$2" entries_file="$3"
    [[ -n "$entries_file" && -f "$entries_file" ]] || return 0

    local -a metas=()
    local line meta i
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        meta="${line%%$'\t'*}"
        [[ "$meta" == "_" ]] && continue
        metas+=("$meta")
    done < "$entries_file"

    (( ${#metas} > 0 )) || return 0

    local current_meta="${ws_name}|${instance_name}"
    local idx=0
    for (( i = 1; i <= ${#metas}; i++ )); do
        if [[ "${metas[$i]}" == "$current_meta" ]]; then
            idx="$i"
            break
        fi
    done
    (( idx > 0 )) || return 0

    local start=$(( idx - 2 ))
    local end=$(( idx + 2 ))
    (( start < 1 )) && start=1
    (( end > ${#metas} )) && end=${#metas}

    local m target_ws target_inst
    for (( i = start; i <= end; i++ )); do
        m="${metas[$i]}"
        target_ws="${m%%|*}"
        target_inst="${m#*|}"
        (_grove_tui_prefetch_instance_prs "$target_ws" "$target_inst" >/dev/null 2>&1) &!
    done
}

# ─── Branch Parent Cache ──────────────────────────────────────────────────────
# Cache expensive branch-parent derivation (_grove_worktree_branch_parents).
_grove_tui_branch_parent_cache_dir() {
    local cache_dir="${TMPDIR:-/tmp}/grove-branch-parent-cache-${USER}"
    mkdir -p "$cache_dir" 2>/dev/null || return 1
    echo "$cache_dir"
}

_grove_tui_branch_parent_cache_key() {
    local project_dir="$1"
    shift
    local branch_sig="${(j:\n:)@}"
    local sum
    sum=$(printf '%s\n%s' "$project_dir" "$branch_sig" | cksum | awk '{print $1}')
    echo "$sum"
}

_grove_tui_branch_parent_cache_get() {
    local project_dir="$1" ttl="$2"
    shift 2
    local cache_dir cache_file now ts payload
    cache_dir=$(_grove_tui_branch_parent_cache_dir) || return 1
    cache_file="$cache_dir/$(_grove_tui_branch_parent_cache_key "$project_dir" "$@").cache"
    [[ -f "$cache_file" ]] || return 1

    IFS= read -r ts < "$cache_file" || return 1
    [[ "$ts" == <-> ]] || return 1
    now=$(date +%s)
    (( now - ts <= ttl )) || return 1

    payload=$(tail -n +2 "$cache_file" 2>/dev/null)
    echo "$payload"
    return 0
}

_grove_tui_branch_parent_cache_put() {
    local project_dir="$1" payload="$2"
    shift 2
    local cache_dir cache_file tmpf now
    cache_dir=$(_grove_tui_branch_parent_cache_dir) || return 1
    cache_file="$cache_dir/$(_grove_tui_branch_parent_cache_key "$project_dir" "$@").cache"
    tmpf=$(mktemp "${TMPDIR:-/tmp}/grove-branch-parent-cache.XXXXXX") || return 1
    now=$(date +%s)
    {
        echo "$now"
        echo "$payload"
    } > "$tmpf"
    mv "$tmpf" "$cache_file" 2>/dev/null || {
        rm -f "$tmpf"
        return 1
    }
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
    local branch_parent_cache_ttl="${GROVE_TUI_BRANCH_PARENT_CACHE_TTL:-20}"
    local tree_start_us
    _grove_tui_timing_enabled && tree_start_us=$(_grove_tui_now_us)

    # Read parent relationships into parallel arrays
    local -a names=() parents=()
    local line b parent parent_lines
    local parent_cache_hit=1
    parent_lines=$(_grove_tui_branch_parent_cache_get "$project_dir" "$branch_parent_cache_ttl" "${branch_args[@]}")
    if [[ $? -ne 0 ]]; then
        parent_cache_hit=0
        if (( ${#branch_args} > 0 )); then
            parent_lines=$(_grove_worktree_branch_parents "$project_dir" "${branch_args[@]}")
        else
            parent_lines=$(_grove_worktree_branch_parents "$project_dir")
        fi
        _grove_tui_branch_parent_cache_put "$project_dir" "$parent_lines" "${branch_args[@]}" >/dev/null 2>&1
    fi
    while read -r line; do
        b="${line%%|*}"
        parent="${line#*|}"
        [[ -n "$b" ]] && names+=("$b") && parents+=("$parent")
    done <<< "$parent_lines"

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

    # Compute max descendant chain depth for a node (for choosing main child).
    # Returns depth in REPLY and memoizes results by node index.
    local -A chain_depth_cache=()
    _chain_depth() {
        local idx="$1"
        if [[ -n "${chain_depth_cache[$idx]+x}" ]]; then
            REPLY="${chain_depth_cache[$idx]}"
            return
        fi

        local kids="${children_lists[$idx]}"
        if [[ -z "$kids" ]]; then
            chain_depth_cache[$idx]=0
            REPLY=0
            return
        fi

        local max_d=0 child_d ci
        for ci in ${(s: :)kids}; do
            _chain_depth "$ci"
            child_d="$REPLY"
            (( child_d + 1 > max_d )) && (( max_d = child_d + 1 ))
        done
        chain_depth_cache[$idx]="$max_d"
        REPLY="$max_d"
    }

    # For a node with multiple children, pick the main child (deepest chain first,
    # then higher index for ties). Returns index in REPLY.
    _pick_main_child() {
        local -a child_indices=(${(s: :)1})
        local main_idx="${child_indices[1]}"
        _chain_depth "$main_idx"
        local main_depth="$REPLY"
        local si cd
        (( si = 2 ))
        while (( si <= ${#child_indices} )); do
            _chain_depth "${child_indices[$si]}"
            cd="$REPLY"
            if (( cd > main_depth )) || \
               (( cd == main_depth && child_indices[si] > main_idx )); then
                main_idx="${child_indices[$si]}"
                main_depth="$cd"
            fi
            (( si++ ))
        done
        REPLY="$main_idx"
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
    # _gt_walk renders a subtree rooted at node_idx.
    # col_depth: column position of this node's ○ marker
    # total_cols: total active columns from ancestor forks
    _gt_walk() {
        local node_idx="$1" col_depth="$2" total_cols="${3:-$2}"
        local node_name="${names[$node_idx]}"
        local kids="${children_lists[$node_idx]}"
        local -a child_indices=()
        [[ -n "$kids" ]] && child_indices=(${(s: :)kids})

        local num_children=${#child_indices}

        # Helper: build │ bar pattern for PR/continuation lines
        # Columns 0..col_depth-1: │ (from ancestor forks)
        # Column col_depth: space (the node's own position)
        # Columns col_depth+1..total_cols: │ (side branches from this node's parent fork)
        local _bars=""
        if (( total_cols > col_depth )); then
            (( j = 0 ))
            while (( j <= total_cols )); do
                if (( j == col_depth )); then
                    _bars+="  "
                else
                    _bars+="│ "
                fi
                (( j++ ))
            done
        elif (( col_depth > 0 )); then
            (( j = 0 ))
            while (( j < col_depth )); do
                _bars+="│ "
                (( j++ ))
            done
        fi

        if (( num_children == 0 )); then
            # Leaf node
            local prefix=""
            (( j = 0 ))
            while (( j < col_depth )); do
                prefix+="│ "
                (( j++ ))
            done
            output_lines+=("${_bars}"$'\t'"${prefix}○ ${node_name}")

        elif (( num_children == 1 )); then
            # Single child — continues the line, no fork
            _gt_walk "${child_indices[1]}" "$col_depth" "$total_cols"
            local prefix=""
            (( j = 0 ))
            while (( j < col_depth )); do
                prefix+="│ "
                (( j++ ))
            done
            output_lines+=("${_bars}"$'\t'"${prefix}○ ${node_name}")

        else
            # Multiple children — fork point
            local main_child
            _pick_main_child "$kids"
            main_child="$REPLY"
            local -a side_children=()
            local ci
            for ci in "${child_indices[@]}"; do
                [[ "$ci" != "$main_child" ]] && side_children+=("$ci")
            done
            local num_sides=${#side_children}

            # Walk main child
            _gt_walk "$main_child" "$col_depth" "$(( col_depth + num_sides ))"

            # Walk each side branch
            local si=0
            for ci in "${side_children[@]}"; do
                _gt_walk "$ci" "$(( col_depth + si + 1 ))" "$(( col_depth + num_sides ))"
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

            # Bars for fork point: just the cols to the left of the fork
            local fork_bars=""
            (( j = 0 ))
            while (( j < col_depth )); do
                fork_bars+="│ "
                (( j++ ))
            done

            output_lines+=("${fork_bars}"$'\t'"${prefix} ${node_name}")
        fi
    }

    # Walk each root (suppress stdout from _gt_walk to avoid local variable leaks)
    for i in "${roots[@]}"; do
        _gt_walk "$i" "0"
    done

    # Output all lines (format: bars\tprefix name)
    local l
    for l in "${output_lines[@]}"; do
        echo "$l"
    done

    if _grove_tui_timing_enabled; then
        _grove_tui_timing_log \
            "tree:${project_dir:t}" \
            "$tree_start_us" \
            "branches=${#names},cache_hit=${parent_cache_hit}"
    fi
}

# Colorize a rendered tree prefix using a depth-cycled rainbow palette.
# Input is the "prefix" portion from _grove_tui_render_branch_tree output,
# for example: "│ │ ○─┴─┘".
_grove_tui_colorize_tree_prefix() {
    local prefix="$1"
    local marker="$2"

    local c_reset=$'\e[0m'
    local -a c_rainbow=(
        $'\e[38;2;76;203;241m'   # #4ccbf1
        $'\e[38;2;77;201;125m'   # #4dc97d
        $'\e[38;2;110;172;39m'   # #6eac27
        $'\e[38;2;245;200;1m'    # #f5c801
        $'\e[38;2;248;144;73m'   # #f89049
        $'\e[38;2;244;98;81m'    # #f46251
        $'\e[38;2;235;129;188m'  # #eb81bc
        $'\e[38;2;235;129;188m'  # #eb81bc
        $'\e[38;2;80;132;242m'   # #5084f2
    )
    local rainbow_len=${#c_rainbow}

    local out=""
    local pos=1
    local depth=0
    local color_idx color ch

    # Color each leading "│ " column by depth.
    while [[ "$prefix[$pos,$((pos + 1))]" == "│ " ]]; do
        color_idx=$(( (depth % rainbow_len) + 1 ))
        color="${c_rainbow[$color_idx]}"
        out+="${color}│${c_reset} "
        (( pos += 2 ))
        (( depth++ ))
    done

    # Color the node marker in the current depth color unless caller already
    # passed an ANSI-colored marker (used for HEAD).
    ch="$prefix[$pos]"
    if [[ "$ch" == "○" || "$ch" == "◉" ]]; then
        if [[ "$marker" == *$'\e['* ]]; then
            out+="$marker"
        else
            color_idx=$(( (depth % rainbow_len) + 1 ))
            color="${c_rainbow[$color_idx]}"
            out+="${color}${marker}${c_reset}"
        fi
        (( pos++ ))
    fi

    # Color fork connectors (─┴┘│) lane-by-lane.
    # Horizontal segments use current lane; ┴/┘ step into the next lane color.
    local connector_depth="$depth"
    while (( pos <= ${#prefix} )); do
        ch="$prefix[$pos]"
        case "$ch" in
            "┴"|"┘")
                (( connector_depth++ ))
                color_idx=$(( (connector_depth % rainbow_len) + 1 ))
                color="${c_rainbow[$color_idx]}"
                out+="${color}${ch}${c_reset}"
                ;;
            "─"|"│")
                color_idx=$(( (connector_depth % rainbow_len) + 1 ))
                color="${c_rainbow[$color_idx]}"
                out+="${color}${ch}${c_reset}"
                ;;
            *)
                out+="$ch"
                ;;
        esac
        (( pos++ ))
    done

    echo "$out"
}

# Return the rainbow color escape for a tree prefix's node depth.
# Depth is the count of leading "│ " columns.
_grove_tui_tree_depth_color() {
    local prefix="$1"
    local -a c_rainbow=(
        $'\e[38;2;76;203;241m'   # #4ccbf1
        $'\e[38;2;77;201;125m'   # #4dc97d
        $'\e[38;2;110;172;39m'   # #6eac27
        $'\e[38;2;245;200;1m'    # #f5c801
        $'\e[38;2;248;144;73m'   # #f89049
        $'\e[38;2;244;98;81m'    # #f46251
        $'\e[38;2;235;129;188m'  # #eb81bc
        $'\e[38;2;235;129;188m'  # #eb81bc
        $'\e[38;2;80;132;242m'   # #5084f2
    )
    local depth=0
    local pos=1
    while [[ "$prefix[$pos,$((pos + 1))]" == "│ " ]]; do
        (( depth++ ))
        (( pos += 2 ))
    done
    local idx=$(( (depth % ${#c_rainbow}) + 1 ))
    echo "${c_rainbow[$idx]}"
}

# ─── PR status formatting ────────────────────────────────────────────────────

# Format a single PR status column: returns "icon label\tcolor_code".
# Usage: _grove_tui_format_pr_column <col_name> <value>
#
# Column definitions:
#   status:      Open / Closed / Merged / Draft
#   review:      Approved / Changes Req. / Awaiting
#   merge:       Mergeable / Conflicts / Checking
#   ci:          Passed / Failing / Running
_grove_tui_format_pr_column() {
    local col="$1" val="$2"
    local icon="" label="" color=""
    case "$col" in
        status)
            case "$val" in
                OPEN)    icon="●"; label="Open";   color="32" ;;
                MERGED)  icon="●"; label="Merged"; color="35" ;;
                CLOSED)  icon="●"; label="Closed"; color="31" ;;
                DRAFT)   icon="●"; label="Draft";  color="90" ;;
                *)       icon="●"; label="Open";   color="32" ;;
            esac
            ;;
        review)
            case "$val" in
                APPROVED)          icon="✓"; label="Approved";     color="32" ;;
                CHANGES_REQUESTED) icon="✗"; label="Changes Req."; color="31" ;;
                *)                 icon="○"; label="Awaiting";     color="90" ;;
            esac
            ;;
        merge)
            case "$val" in
                MERGEABLE)   icon="↑"; label="Mergeable"; color="32" ;;
                CONFLICTING) icon="⚡"; label="Conflicts"; color="31" ;;
                *)           icon="○"; label="Checking";  color="90" ;;
            esac
            ;;
        ci)
            case "$val" in
                SUCCESS) icon="✓"; label="Passed";  color="32" ;;
                FAILURE) icon="✗"; label="Failing"; color="31" ;;
                PENDING) icon="●"; label="Running"; color="33" ;;
                *)       icon="○"; label="Running"; color="33" ;;
            esac
            ;;
    esac
    echo "${icon} ${label}"$'\t'"${color}"
}

# Column widths (max visible chars of "icon label" per column).
# Status: "● Merged"=8, Review: "✗ Changes Req."=14, Merge: "⚡ Conflicts"=11, CI: "● Running"=9
typeset -gA _GROVE_PR_COL_WIDTHS=(
    [status]=8
    [review]=14
    [merge]=11
    [ci]=9
)

# Pad a string to a fixed visible width. ANSI codes are not counted.
# Usage: _grove_tui_pad_ansi <ansi_string> <target_width>
_grove_tui_pad_ansi() {
    local str="$1" target="$2"
    # Strip ANSI to measure visible length
    local plain="${str//$'\e'\[*m/}"
    local vis_len=${#plain}
    local pad=$(( target - vis_len ))
    local spaces=""
    (( pad > 0 )) && printf -v spaces '%*s' "$pad" ''
    echo "${str}${spaces}"
}

_grove_tui_format_pr() {
    local pr_data="$1"
    if [[ "$pr_data" == "__LOADING__" ]]; then
        echo "\e[0;90mPR loading...\e[0m"
        return
    fi
    if [[ "$pr_data" == "__ERR__" ]]; then
        echo "\e[0;90mPR unavailable\e[0m"
        return
    fi
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
    local pr_draft=$(echo "$pr_data" | grep -o '"isDraft":true' | head -1)

    # Override state to DRAFT if isDraft is true
    [[ -n "$pr_draft" ]] && pr_state="DRAFT"

    # PR number as clickable link (OSC 8 hyperlink)
    local result=""
    if [[ -n "$pr_number" && -n "$pr_url" ]]; then
        result+="\e]8;;${pr_url}\e\\PR #${pr_number}\e]8;;\e\\"
    else
        result+="PR"
    fi

    local col_name col_val col_raw col_color col_rendered
    for col_name col_val in status "$pr_state" review "$pr_review" merge "$pr_mergeable" ci "$pr_ci_status"; do
        col_raw=$(_grove_tui_format_pr_column "$col_name" "$col_val")
        local plain_text="${col_raw%%$'\t'*}"
        col_color="${col_raw##*$'\t'}"
        col_rendered="\e[0;${col_color}m${plain_text}\e[0m"
        col_rendered=$(_grove_tui_pad_ansi "$col_rendered" "${_GROVE_PR_COL_WIDTHS[$col_name]}")
        result+="  ${col_rendered}"
    done
    echo "$result"
}

# ─── Preview ─────────────────────────────────────────────────────────────────
# Show details for the highlighted instance in fzf's preview pane.
# Receives the raw fzf line as $1, parses out workspace and instance.
_grove_tui_preview() {
    setopt localoptions typesetsilent

    local line="$1"
    local entries_file="$2"
    local workspaces_dir="$GROVE_WORKSPACES_DIR"
    local preview_total_start_us
    _grove_tui_timing_enabled && preview_total_start_us=$(_grove_tui_now_us)

    local REPLY_WS REPLY_INST
    _grove_tui_parse_selection "$line"
    local ws_name="$REPLY_WS"
    local instance_name="$REPLY_INST"

    # Warm neighboring entries (current ±2) in the background.
    if _grove_tui_timing_enabled; then
        local prefetch_start_us=$(_grove_tui_now_us)
        _grove_tui_prefetch_window "$ws_name" "$instance_name" "$entries_file"
        _grove_tui_timing_log "preview_prefetch_window" "$prefetch_start_us" "${ws_name}/${instance_name}"
    else
        _grove_tui_prefetch_window "$ws_name" "$instance_name" "$entries_file"
    fi

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
    local -A pr_repo_for_key=()
    local -A pr_branch_for_key=()
    local -A pr_results=()
    local project_dir project branch repo_url head_branch
    local -a all_branches
    local tmpf b cache_ttl cache_data pr_key
    local pr_fetch_start_us fetch_hits=0 fetch_misses=0 fetch_spawned=0
    local queued_prefetch=0
    _grove_tui_timing_enabled && pr_fetch_start_us=$(_grove_tui_now_us)
    cache_ttl="${GROVE_TUI_PR_CACHE_TTL:-300}"

    if command -v gh &>/dev/null; then
        for project_dir in "$instance_dir"/*(N/); do
            project="${project_dir:t}"
            [[ "$project" == .* ]] && continue
            if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
                repo_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null)
                all_branches=("${(@f)$(_grove_worktree_branches "$project_dir")}")
                for b in "${all_branches[@]}"; do
                    [[ -z "$b" ]] && continue
                    pr_key="${project}:${b}"
                    cache_data=$(_grove_tui_pr_cache_get "$repo_url" "$b" "$cache_ttl")
                    if [[ $? -eq 0 ]]; then
                        pr_results["$pr_key"]="$cache_data"
                        (( fetch_hits++ ))
                        continue
                    fi
                    (( fetch_misses++ ))
                    pr_results["$pr_key"]="__LOADING__"
                done
            fi
        done
        # Queue background fill for current instance; lock prevents duplicates.
        if (( fetch_misses > 0 )); then
            ((_grove_tui_prefetch_instance_prs "$ws_name" "$instance_name" >/dev/null 2>&1) &!)
            queued_prefetch=1
        fi
    fi
    _grove_tui_timing_enabled && _grove_tui_timing_log "preview_pr_fetch" "$pr_fetch_start_us" "hits=${fetch_hits},misses=${fetch_misses},spawned=${fetch_spawned},queued_prefetch=${queued_prefetch}"

    # Per-project details with all branches
    local status_line pr_data pr_display tree_line indent marker suffix pr_key
    local -a tree_lines_arr
    local tree_prefix colored_prefix b max_prefix_len pad_count padding p branch_color
    local max_branch_detail_len branch_detail_len pr_pad_count pr_padding
    local head_plain
    for project_dir in "$instance_dir"/*(N/); do
        project="${project_dir:t}"
        [[ "$project" == .* ]] && continue
        if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
            local project_render_start_us
            _grove_tui_timing_enabled && project_render_start_us=$(_grove_tui_now_us)
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

            # Collect tree lines from renderer.
            # Format: bars\tprefix name
            tree_lines_arr=()
            while IFS= read -r tree_line; do
                [[ -n "$tree_line" ]] && tree_lines_arr+=("$tree_line")
            done < <(_grove_tui_render_branch_tree "$project_dir")

            # Align branch-name column: compute max tree-prefix width first.
            max_prefix_len=0
            for tree_line in "${tree_lines_arr[@]}"; do
                tree_prefix="${tree_line#*$'\t'}"
                tree_prefix="${tree_prefix% *}"
                (( ${#tree_prefix} > max_prefix_len )) && max_prefix_len=${#tree_prefix}
            done
            max_branch_detail_len=0
            for tree_line in "${tree_lines_arr[@]}"; do
                tree_prefix="${tree_line#*$'\t'}"
                b="${tree_prefix##* }"
                branch_detail_len=${#b}
                (( branch_detail_len > max_branch_detail_len )) && max_branch_detail_len=$branch_detail_len
            done

            # Render each branch in a single line (gt ls style).
            for tree_line in "${tree_lines_arr[@]}"; do
                tree_prefix="${tree_line#*$'\t'}"
                b="${tree_prefix##* }"
                tree_prefix="${tree_prefix% *}"

                # Build colored version of the prefix (replace ○/◉ with marker)
                marker="○"
                if [[ "$b" == "$head_branch" ]]; then
                    marker="◉"
                fi
                colored_prefix=$(_grove_tui_colorize_tree_prefix "$tree_prefix" "$marker")
                branch_color=$(_grove_tui_tree_depth_color "$tree_prefix")
                pad_count=$(( max_prefix_len - ${#tree_prefix} ))
                padding=""
                p=0
                while (( p < pad_count )); do
                    padding+=" "
                    (( p++ ))
                done

                # PR status
                pr_data=""
                pr_key="${project}:${b}"
                pr_data="${pr_results["$pr_key"]-}"
                pr_display=$(_grove_tui_format_pr "$pr_data")

                pr_pad_count=$(( max_branch_detail_len - ${#b} ))
                pr_padding=""
                p=0
                while (( p < pr_pad_count )); do
                    pr_padding+=" "
                    (( p++ ))
                done

                echo "  ${colored_prefix}${padding} ${branch_color}${b}\e[0m${pr_padding}  ${pr_display}"
            done
            echo ""
            _grove_tui_timing_enabled && _grove_tui_timing_log "preview_project_render:${project}" "$project_render_start_us" "branches=${#all_branches}"
        fi
    done

    _grove_tui_timing_enabled && _grove_tui_timing_log "preview_total:${ws_name}/${instance_name}" "$preview_total_start_us"
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
    local entries_file
    entries_file=$(mktemp)
    printf '%s\n' "$entries" > "$entries_file"

    # Empty state: jump straight to new instance flow
    if [[ -z "$entries" ]]; then
        rm -f "$entries_file"
        echo "No workspace instances yet. Let's create one."
        echo ""
        _grove_tui_new
        return $?
    fi

    # Warm startup entries in the background so initial navigation hits cache.
    local startup_prefetch_count="${GROVE_TUI_STARTUP_PREFETCH_COUNT:-8}"
    (_grove_tui_prefetch_entries_file "$entries_file" "$startup_prefetch_count" >/dev/null 2>&1) &!

    # Determine preview command — need to re-source grove.zsh in the subprocess
    local _grove_tui_script_dir="${${(%):-%x}:A:h}"
    local preview_cmd="zsh -c 'source \"${_grove_tui_script_dir}/grove.zsh\"; _grove_tui_preview \"\$1\" \"\$2\"' -- {} \"$entries_file\""

    # Extract workspace/instance + repo type for preview label
    local label_cmd="zsh -c 'source \"${_grove_tui_script_dir}/grove.zsh\"; _grove_tui_label \"\$1\"' -- {}"

    # Main fzf screen with --expect to capture keybindings
    local result
    result=$(echo "$entries" | fzf \
        --ansi \
        --delimiter=$'\t' \
        --with-nth=2.. \
        --nth=2,4 \
        --tabstop=2 \
        --header="Grove  (enter: open  ctrl-n: new  del/ctrl-x: remove)" \
        --header-lines=1 \
        --preview="$preview_cmd" \
        --preview-window=right:65%:wrap \
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
        rm -f "$entries_file"
        return 0
    fi

    # Parse workspace and instance from the selected line
    local REPLY_WS REPLY_INST
    _grove_tui_parse_selection "$selection"
    local ws_name="$REPLY_WS"
    local instance_name="$REPLY_INST"

    if [[ -z "$ws_name" || -z "$instance_name" ]]; then
        rm -f "$entries_file"
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

    rm -f "$entries_file"
}
