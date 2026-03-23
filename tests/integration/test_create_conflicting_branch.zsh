#!/usr/bin/env zsh
# Integration tests: branch name conflict resolution
#
# NOTE: git ls-remote --heads uses suffix matching, so `ls-remote origin "name"`
# matches `refs/heads/prefix/name`. This means gv's raw branch check (line 586)
# catches cases where prefix/name exists on remote, before _grove_resolve_branch_name
# gets called. The date-prefix fallback is only reachable when the prefixed name
# exists but the raw name does NOT suffix-match it (an unusual edge case).
# We test _grove_resolve_branch_name directly in unit tests instead.

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# When prefix/name exists on remote, gv treats raw name as existing remote branch
# (due to git ls-remote suffix matching) and tracks it
ztr test '
    create_test_repo myapp
    create_remote_branch myapp "testuser/taken"
    gv myapp taken &>/dev/null
    # gv will try to track "origin/taken" which fails because only testuser/taken exists
    # This is a known quirk of grove + git ls-remote suffix matching
    (( $? != 0 ))
' 'prefix/name on remote causes raw name tracking attempt (known limitation)'

# Non-conflicting name uses plain prefix
ztr test '
    create_test_repo myapp
    gv myapp fresh-name &>/dev/null
    local branch=$(git -C "$GROVE_WORKSPACES_DIR/myapp/fresh-name/myapp" rev-parse --abbrev-ref HEAD)
    [[ "$branch" == "testuser/fresh-name" ]]
' 'non-conflicting name uses plain prefix'
