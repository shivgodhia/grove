#!/usr/bin/env zsh
# Tests for _grove_tmux_session_name

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

ztr test '[[ $(_grove_tmux_session_name myapp feature) == "grove/myapp/feature" ]]' \
    'basic session name'

ztr test '[[ $(_grove_tmux_session_name "my.app" feature) == "grove/my_app/feature" ]]' \
    'dots replaced with underscores'

ztr test '[[ $(_grove_tmux_session_name "my:app" feature) == "grove/my_app/feature" ]]' \
    'colons replaced with underscores'

ztr test '[[ $(_grove_tmux_session_name "my.app:v2" "fix.bug") == "grove/my_app_v2/fix_bug" ]]' \
    'dots and colons in both args replaced'

ztr test '[[ $(_grove_tmux_session_name myapp "feature-auth") == "grove/myapp/feature-auth" ]]' \
    'dashes preserved'

ztr test '[[ $(_grove_tmux_session_name myapp "shiv-fix") == "grove/myapp/shiv-fix" ]]' \
    'sanitized instance name (slash already converted to dash by caller)'
