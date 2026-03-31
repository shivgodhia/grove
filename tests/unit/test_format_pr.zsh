#!/usr/bin/env zsh
# Tests for _grove_tui_format_pr_column and _grove_tui_format_pr
# Verifies PR status columns produce correct labels and colors for all states.

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Helper: strip ANSI color codes and OSC 8 hyperlinks from a string.
strip_ansi() {
    local esc=$'\e'
    echo "$1" | sed "s/${esc}\[[0-9;]*m//g" | sed "s/${esc}]8;;[^${esc}]*${esc}\\\\//g"
}

# ── _grove_tui_format_pr_column: Status column ─────────────────────────────

ztr test '
    local out=$(_grove_tui_format_pr_column status OPEN)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "● Open" ]] && [[ "$color" == "32" ]]
' 'status OPEN → green ● Open'

ztr test '
    local out=$(_grove_tui_format_pr_column status MERGED)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "● Merged" ]] && [[ "$color" == "35" ]]
' 'status MERGED → magenta ● Merged'

ztr test '
    local out=$(_grove_tui_format_pr_column status CLOSED)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "● Closed" ]] && [[ "$color" == "31" ]]
' 'status CLOSED → red ● Closed'

ztr test '
    local out=$(_grove_tui_format_pr_column status DRAFT)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "● Draft" ]] && [[ "$color" == "90" ]]
' 'status DRAFT → gray ● Draft'

ztr test '
    local out=$(_grove_tui_format_pr_column status "")
    local label="${out%%	*}"
    [[ "$label" == "● Open" ]]
' 'status empty defaults to ● Open'

# ── _grove_tui_format_pr_column: Review column ─────────────────────────────

ztr test '
    local out=$(_grove_tui_format_pr_column review APPROVED)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "✓ Approved" ]] && [[ "$color" == "32" ]]
' 'review APPROVED → green ✓ Approved'

ztr test '
    local out=$(_grove_tui_format_pr_column review CHANGES_REQUESTED)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "✗ Changes Req." ]] && [[ "$color" == "31" ]]
' 'review CHANGES_REQUESTED → red ✗ Changes Req.'

ztr test '
    local out=$(_grove_tui_format_pr_column review "")
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "○ Awaiting" ]] && [[ "$color" == "90" ]]
' 'review empty → gray ○ Awaiting'

ztr test '
    local out=$(_grove_tui_format_pr_column review REVIEW_REQUIRED)
    local label="${out%%	*}"
    [[ "$label" == "○ Awaiting" ]]
' 'review REVIEW_REQUIRED falls through to ○ Awaiting'

# ── _grove_tui_format_pr_column: Merge column ──────────────────────────────

ztr test '
    local out=$(_grove_tui_format_pr_column merge MERGEABLE)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "↑ Mergeable" ]] && [[ "$color" == "32" ]]
' 'merge MERGEABLE → green ↑ Mergeable'

ztr test '
    local out=$(_grove_tui_format_pr_column merge CONFLICTING)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "⚡ Conflicts" ]] && [[ "$color" == "31" ]]
' 'merge CONFLICTING → red ⚡ Conflicts'

ztr test '
    local out=$(_grove_tui_format_pr_column merge "")
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "○ Checking" ]] && [[ "$color" == "90" ]]
' 'merge empty → gray ○ Checking'

ztr test '
    local out=$(_grove_tui_format_pr_column merge UNKNOWN)
    local label="${out%%	*}"
    [[ "$label" == "○ Checking" ]]
' 'merge UNKNOWN falls through to ○ Checking'

# ── _grove_tui_format_pr_column: CI column ──────────────────────────────────

ztr test '
    local out=$(_grove_tui_format_pr_column ci SUCCESS)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "✓ Passed" ]] && [[ "$color" == "32" ]]
' 'ci SUCCESS → green ✓ Passed'

ztr test '
    local out=$(_grove_tui_format_pr_column ci FAILURE)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "✗ Failing" ]] && [[ "$color" == "31" ]]
' 'ci FAILURE → red ✗ Failing'

ztr test '
    local out=$(_grove_tui_format_pr_column ci PENDING)
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "● Running" ]] && [[ "$color" == "33" ]]
' 'ci PENDING → yellow ● Running'

ztr test '
    local out=$(_grove_tui_format_pr_column ci "")
    local label="${out%%	*}"
    local color="${out##*	}"
    [[ "$label" == "○ Running" ]] && [[ "$color" == "33" ]]
' 'ci empty → yellow ○ Running'

# ── _grove_tui_format_pr: full output ──────────────────────────────────────

ztr test '
    local out=$(_grove_tui_format_pr "")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == "No PR" ]]
' 'empty data → No PR'

ztr test '
    local out=$(_grove_tui_format_pr "__LOADING__")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == "PR loading..." ]]
' 'loading state → PR loading...'

ztr test '
    local out=$(_grove_tui_format_pr "__ERR__")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == "PR unavailable" ]]
' 'error state → PR unavailable'

ztr test '
    local json="{\"number\":123,\"url\":\"https://github.com/test/repo/pull/123\",\"state\":\"OPEN\",\"mergeable\":\"CONFLICTING\",\"reviewDecision\":\"APPROVED\",\"ci\":\"FAILURE\"}"
    local out=$(_grove_tui_format_pr "$json")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == *"● Open"* ]] &&
    [[ "$plain" == *"✓ Approved"* ]] &&
    [[ "$plain" == *"⚡ Conflicts"* ]] &&
    [[ "$plain" == *"✗ Failing"* ]]
' 'full PR data renders all four status columns'

ztr test '
    local json="{\"number\":456,\"url\":\"https://github.com/test/repo/pull/456\",\"state\":\"OPEN\",\"mergeable\":\"MERGEABLE\",\"reviewDecision\":\"\",\"ci\":\"SUCCESS\"}"
    local out=$(_grove_tui_format_pr "$json")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == *"○ Awaiting"* ]] &&
    [[ "$plain" == *"↑ Mergeable"* ]] &&
    [[ "$plain" == *"✓ Passed"* ]]
' 'missing review shows Awaiting fallback'

ztr test '
    local json="{\"number\":789,\"url\":\"https://github.com/test/repo/pull/789\",\"state\":\"OPEN\",\"isDraft\":true,\"mergeable\":\"MERGEABLE\",\"reviewDecision\":\"\",\"ci\":\"PENDING\"}"
    local out=$(_grove_tui_format_pr "$json")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == *"● Draft"* ]]
' 'isDraft true overrides state to Draft'

ztr test '
    local json="{\"number\":100,\"url\":\"https://github.com/test/repo/pull/100\",\"state\":\"MERGED\",\"mergeable\":\"\",\"reviewDecision\":\"APPROVED\",\"ci\":\"SUCCESS\"}"
    local out=$(_grove_tui_format_pr "$json")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == *"● Merged"* ]] &&
    [[ "$plain" == *"✓ Approved"* ]] &&
    [[ "$plain" == *"○ Checking"* ]] &&
    [[ "$plain" == *"✓ Passed"* ]]
' 'merged PR with empty mergeable shows Checking fallback'

ztr test '
    local json="{\"number\":200,\"url\":\"https://github.com/test/repo/pull/200\",\"state\":\"OPEN\",\"mergeable\":\"CONFLICTING\",\"reviewDecision\":\"APPROVED\",\"ci\":\"FAILURE\"}"
    local out=$(_grove_tui_format_pr "$json")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == *"PR #200"* ]]
' 'PR number appears in output'

ztr test '
    local json="{\"number\":300,\"url\":\"https://github.com/test/repo/pull/300\",\"state\":\"OPEN\",\"mergeable\":\"MERGEABLE\",\"reviewDecision\":\"CHANGES_REQUESTED\",\"ci\":\"SUCCESS\"}"
    local out=$(_grove_tui_format_pr "$json")
    local plain=$(strip_ansi "$out")
    [[ "$plain" == *"✗ Changes Req."* ]]
' 'changes requested review shows Changes Req.'
