#!/usr/bin/env zsh
# Tests for _grove_tui_parse_selection
# Verifies that full workspace/instance names are extracted from the hidden
# metadata column, even when display columns are truncated with ".."

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Basic case — no truncation
ztr test '
    local REPLY_WS REPLY_INST
    local line="myapp|my-feature"$'\''\t'\''[myapp]"$'\''\t'\''  ● "$'\''\t'\''my-feature"$'\''\t'\''main"
    _grove_tui_parse_selection "$line"
    [[ "$REPLY_WS" == "myapp" ]] && [[ "$REPLY_INST" == "my-feature" ]]
' 'parses workspace and instance from metadata column'

# Truncated workspace display — metadata still has full name
ztr test '
    local REPLY_WS REPLY_INST
    local line="website-migrations|sauna-inspired"$'\''\t'\''[website-migra..]"$'\''\t'\''  ● "$'\''\t'\''sauna-inspired"$'\''\t'\''main"
    _grove_tui_parse_selection "$line"
    [[ "$REPLY_WS" == "website-migrations" ]] && [[ "$REPLY_INST" == "sauna-inspired" ]]
' 'full workspace name from metadata when display is truncated'

# Truncated instance display — metadata still has full name
ztr test '
    local REPLY_WS REPLY_INST
    local line="ops-console|attribute-scout-v0-hack"$'\''\t'\''[ops-console]"$'\''\t'\''  ● "$'\''\t'\''attribute-scout-.."$'\''\t'\''main"
    _grove_tui_parse_selection "$line"
    [[ "$REPLY_WS" == "ops-console" ]] && [[ "$REPLY_INST" == "attribute-scout-v0-hack" ]]
' 'full instance name from metadata when display is truncated'

# Both truncated
ztr test '
    local REPLY_WS REPLY_INST
    local line="traba-server-infra|automate-db-migrations-nit"$'\''\t'\''[traba-server-..]"$'\''\t'\''  ● "$'\''\t'\''automate-db-migra.."$'\''\t'\''main"
    _grove_tui_parse_selection "$line"
    [[ "$REPLY_WS" == "traba-server-infra" ]] && [[ "$REPLY_INST" == "automate-db-migrations-nit" ]]
' 'both workspace and instance extracted from metadata when both truncated'

# Workspace with pipe-like characters should not exist, but instance with hyphens works
ztr test '
    local REPLY_WS REPLY_INST
    local line="grove|tui"$'\''\t'\''[grove]"$'\''\t'\''  ● "$'\''\t'\''tui"$'\''\t'\''shivgodhia/tui"
    _grove_tui_parse_selection "$line"
    [[ "$REPLY_WS" == "grove" ]] && [[ "$REPLY_INST" == "tui" ]]
' 'simple short names parsed correctly'
