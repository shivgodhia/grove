#!/usr/bin/env zsh
# Tests for _grove_merge_agent_configs

ZTR_SETUP_FN() { grove_test_setup; }
ZTR_TEARDOWN_FN() { grove_test_teardown; }

# Helper: create a fake workspace root with project subdirs
_setup_workspace_root() {
    WORKSPACE_ROOT="$TEST_TMPDIR/ws_root"
    mkdir -p "$WORKSPACE_ROOT"
}

# .claude/skills file is copied with prefix and rewritten name
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp/.claude/skills"
    printf "---\nname: deploy\n---\nDeploy skill" > "$WORKSPACE_ROOT/myapp/.claude/skills/deploy.md"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp

    [[ -f "$WORKSPACE_ROOT/.claude/skills/myapp--deploy.md" ]] &&
    grep -q "name: myapp--deploy.md" "$WORKSPACE_ROOT/.claude/skills/myapp--deploy.md" &&
    grep -q "Deploy skill" "$WORKSPACE_ROOT/.claude/skills/myapp--deploy.md"
' 'claude skill file copied with prefix and rewritten name'

# .claude/skills directory (with SKILL.md) is copied with prefix
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp/.claude/skills/review"
    printf "---\nname: review\n---\nReview skill" > "$WORKSPACE_ROOT/myapp/.claude/skills/review/SKILL.md"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp

    [[ -d "$WORKSPACE_ROOT/.claude/skills/myapp--review" ]] &&
    [[ -f "$WORKSPACE_ROOT/.claude/skills/myapp--review/SKILL.md" ]] &&
    grep -q "name: myapp--review" "$WORKSPACE_ROOT/.claude/skills/myapp--review/SKILL.md"
' 'claude skill directory copied with prefix and SKILL.md rewritten'

# .cursor/rules merged with prefix
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp/.cursor/rules"
    echo "rule content" > "$WORKSPACE_ROOT/myapp/.cursor/rules/lint.md"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp

    [[ -f "$WORKSPACE_ROOT/.cursor/rules/myapp--lint.md" ]] &&
    grep -q "rule content" "$WORKSPACE_ROOT/.cursor/rules/myapp--lint.md"
' 'cursor rules merged with prefix'

# .cursor/commands merged with prefix
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp/.cursor/commands"
    echo "cmd content" > "$WORKSPACE_ROOT/myapp/.cursor/commands/build.md"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp

    [[ -f "$WORKSPACE_ROOT/.cursor/commands/myapp--build.md" ]]
' 'cursor commands merged with prefix'

# Top-level .cursor items (non-canonical dirs) copied with prefix
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp/.cursor"
    echo "config" > "$WORKSPACE_ROOT/myapp/.cursor/settings.json"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp

    [[ -f "$WORKSPACE_ROOT/.cursor/myapp--settings.json" ]]
' 'cursor top-level items copied with prefix'

# Missing .claude dir does not error
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp"
    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp
    (( $? == 0 ))
' 'missing .claude dir does not error'

# Missing .cursor dir does not error
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp"
    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp
    (( $? == 0 ))
' 'missing .cursor dir does not error'

# Multiple projects: both prefixed
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/frontend/.claude/skills"
    printf "---\nname: lint\n---\nLint" > "$WORKSPACE_ROOT/frontend/.claude/skills/lint.md"
    mkdir -p "$WORKSPACE_ROOT/backend/.claude/skills"
    printf "---\nname: deploy\n---\nDeploy" > "$WORKSPACE_ROOT/backend/.claude/skills/deploy.md"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" frontend backend

    [[ -f "$WORKSPACE_ROOT/.claude/skills/frontend--lint.md" ]] &&
    [[ -f "$WORKSPACE_ROOT/.claude/skills/backend--deploy.md" ]] &&
    grep -q "name: frontend--lint.md" "$WORKSPACE_ROOT/.claude/skills/frontend--lint.md" &&
    grep -q "name: backend--deploy.md" "$WORKSPACE_ROOT/.claude/skills/backend--deploy.md"
' 'multiple projects both prefixed correctly'

# Does not overwrite existing prefixed file
ztr test '
    _setup_workspace_root
    mkdir -p "$WORKSPACE_ROOT/myapp/.claude/skills"
    printf "---\nname: deploy\n---\nNew content" > "$WORKSPACE_ROOT/myapp/.claude/skills/deploy.md"
    mkdir -p "$WORKSPACE_ROOT/.claude/skills"
    echo "Original content" > "$WORKSPACE_ROOT/.claude/skills/myapp--deploy.md"

    _grove_merge_agent_configs "$WORKSPACE_ROOT" myapp

    grep -q "Original content" "$WORKSPACE_ROOT/.claude/skills/myapp--deploy.md"
' 'does not overwrite existing prefixed file'
