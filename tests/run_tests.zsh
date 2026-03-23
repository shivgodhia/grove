#!/usr/bin/env zsh
# Grove test runner — runs unit and/or integration tests using zsh-test-runner
#
# Usage:
#   zsh tests/run_tests.zsh            # all tests
#   zsh tests/run_tests.zsh unit       # unit tests only
#   zsh tests/run_tests.zsh integration # integration tests only

TESTS_DIR="${0:A:h}"
GROVE_SCRIPT_PATH="${TESTS_DIR}/../grove.zsh"

# Source ztr
source "$TESTS_DIR/lib/ztr/ztr.zsh"

# Source helpers (defines tmux mock, helpers, etc.)
source "$TESTS_DIR/helpers.zsh"

# Source grove.zsh once (loads all functions into current shell)
grove_test_init

# Clear summary counters
ztr clear-summary

local filter="${1:-all}"
local test_file

if [[ "$filter" == "all" || "$filter" == "unit" ]]; then
    echo "\n━━━ Unit Tests ━━━"
    for test_file in "$TESTS_DIR"/unit/*.zsh(N); do
        echo "\n── $(basename $test_file .zsh) ──"
        source "$test_file"
    done
fi

if [[ "$filter" == "all" || "$filter" == "integration" ]]; then
    echo "\n━━━ Integration Tests ━━━"
    for test_file in "$TESTS_DIR"/integration/*.zsh(N); do
        echo "\n── $(basename $test_file .zsh) ──"
        source "$test_file"
    done
fi

echo "\n━━━ Summary ━━━"
ztr summary

# Clean up one-time init temp dir
[[ -n "$GROVE_TEST_BASE" ]] && rm -rf "$GROVE_TEST_BASE"

# Exit with failure if any tests failed
(( ZTR_RESULTS[failed] == 0 ))
