#!/usr/bin/env zsh
# Integration tests: branch name conflict / prefix resolution
#
# NOTE: git ls-remote --heads uses glob suffix matching, so
# `ls-remote origin "name"` spuriously matches `refs/heads/prefix/name`.
# grove anchors its remote-branch checks with the full "refs/heads/$branch"
# ref (see _grove_remote_branch_exists) so it resolves the EXACT branch that
# exists on origin instead of assuming it equals the bare name. These tests
# lock in that behavior.

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Regression: when the user passes a bare name whose only match on origin is the
# PREFIXED branch (testuser/taken), grove must resolve and track the prefixed
# remote branch — not attempt to track the nonexistent origin/taken.
# Previously this failed with "fatal: invalid reference: origin/taken".
ztr test '
    create_test_repo myapp
    create_remote_branch myapp "testuser/taken"
    gv myapp taken &>/dev/null
    local rc=$?
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/taken/myapp" rev-parse --abbrev-ref HEAD)
    local upstream=$(git -C "$GROVE_WORKSPACES_DIR/myapp/taken/myapp" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    (( rc == 0 )) \
        && [[ "$branch" == "testuser/taken" ]] \
        && [[ "$upstream" == "origin/testuser/taken" ]]
' 'bare name resolves to and tracks the prefixed remote branch'

# Same scenario, but the user passes the fully-qualified name including the
# prefix. grove strips the prefix off $name up front, then must re-resolve back
# to the prefixed remote branch and track it correctly.
ztr test '
    create_test_repo myapp
    create_remote_branch myapp "testuser/taken"
    gv myapp "testuser/taken" &>/dev/null
    local rc=$?
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/taken/myapp" rev-parse --abbrev-ref HEAD)
    local upstream=$(git -C "$GROVE_WORKSPACES_DIR/myapp/taken/myapp" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    (( rc == 0 )) \
        && [[ "$branch" == "testuser/taken" ]] \
        && [[ "$upstream" == "origin/testuser/taken" ]]
' 'full prefixed name resolves to and tracks the prefixed remote branch'

# Non-conflicting name uses plain prefix
ztr test '
    create_test_repo myapp
    gv myapp fresh-name &>/dev/null
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/fresh-name/myapp" rev-parse --abbrev-ref HEAD)
    [[ "$branch" == "testuser/fresh-name" ]]
' 'non-conflicting name uses plain prefix'
