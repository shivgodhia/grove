#!/usr/bin/env zsh
# Integration tests: gv --rm with uncommitted changes

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Returns error without --force when uncommitted changes exist
# Note: the directory is still cleaned up (rm -rf), but the return code is non-zero
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    # Create uncommitted change in the worktree
    echo "dirty" > "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp/uncommitted.txt"
    git -C "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" add uncommitted.txt
    gv --rm myapp my-feature &>/dev/null
    (( $? != 0 ))
' 'returns error without --force when uncommitted changes'

# Succeeds with --force and uncommitted changes
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    echo "dirty" > "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp/uncommitted.txt"
    git -C "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" add uncommitted.txt
    gv --rm --force myapp my-feature &>/dev/null
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/my-feature" ]]
' 'succeeds with --force and uncommitted changes'
