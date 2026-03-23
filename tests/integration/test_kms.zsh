#!/usr/bin/env zsh
# Integration tests: gv --kms

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Fails when not inside a workspace
ztr test '
    gv --kms &>/dev/null
    (( $? != 0 ))
' 'fails when not inside a workspace'

# Removes current workspace from inside it
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    # Simulate being inside the workspace
    local old_pwd="$PWD"
    cd "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    gv --kms &>/dev/null
    cd "$old_pwd"
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/my-feature" ]]
' 'removes current workspace from inside it'

# --kms with --force works with dirty worktree
ztr test '
    create_test_repo myapp
    gv myapp my-feature &>/dev/null
    echo "dirty" > "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp/file.txt"
    git -C "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp" add file.txt
    local old_pwd="$PWD"
    cd "$GROVE_WORKSPACES_DIR/myapp/my-feature/myapp"
    gv --kms --force &>/dev/null
    cd "$old_pwd"
    [[ ! -d "$GROVE_WORKSPACES_DIR/myapp/my-feature" ]]
' '--kms --force works with dirty worktree'
