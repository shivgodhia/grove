---
name: grove
description: Manage workspaces (multi-repo worktrees) - create, delete, list, or cd into workspaces. Usage: /grove <action> [description]. Actions: create, delete, list, cd.
---

# Grove Management Skill

You are helping the user manage workspaces. This skill integrates with the user's `gv` command (workspace manager).

## Workspace Manager Reference

The user has a workspace manager at `~/.zsh/grove/grove.zsh` with local config at `~/.zsh/grove/grove.local.zsh`. **Before running any commands**, read the local config file to determine the actual configured values of:

- `GROVE_PROJECTS_DIR` — where git repos live (default: `~/groveyard`)
- `GROVE_WORKSPACES_DIR` — where workspaces are created (default: `$GROVE_PROJECTS_DIR/workspaces`)
- `GROVE_BRANCH_PREFIX` — prefix for new branch names (default: `$USER`)
- `grove_workspaces` — multi-project workspace definitions

Use those concrete paths (not the variable names) in all Bash commands.

### Available Commands

```bash
gv                                     # Open interactive TUI dashboard
gv <workspace> <name>                  # Create (if needed) and attach to workspace
gv <workspace> <name> <command>        # Run command in workspace (no tmux)
gv --list                              # List all workspaces and instances
gv --ls                                # Show branch tree for current workspace
gv --rm <workspace> <name>             # Remove workspace
gv --rm --force <workspace> <name>     # Force remove (uncommitted changes)
gv --kms [--force]                     # Remove current workspace (from inside it)
gv --home                              # cd to projects directory
gv --update                            # Pull latest grove updates (must be on main)
gv --help                              # Show usage guide
```

### Key Concepts

- **Single-project workspace**: Any project directory is automatically a workspace (e.g. `gv my-api fix-auth`)
- **Multi-project workspace**: Defined in config (e.g. `grove_workspaces[fullstack]="frontend backend"`)
- All projects in a workspace get worktrees with the same branch name
- **Agent config merging**: For multi-project workspaces, `.claude/skills/` and `.cursor/` from each project are copied into the workspace root (skill names are prefixed to avoid collisions)
- **Post-create hooks**: Per-project setup commands that run when a worktree is first created
- **Post-startup hooks**: Per-workspace commands that run every time a new tmux session is created

## Parsing User Intent

The user invokes this skill with `/grove <args>`. Parse the args to determine the action:

| User Input | Action |
|------------|--------|
| `/grove create ...` or `/grove new ...` | CREATE |
| `/grove delete ...` or `/grove rm ...` or `/grove remove ...` | DELETE |
| `/grove list` or `/grove ls` | LIST |
| `/grove cd ...` or `/grove go ...` or `/grove switch ...` | CD |
| `/grove` (no args) | LIST (default) |

---

## Action: CREATE

### Step 1: Determine the Workspace

1. **Check if user specified a workspace**: If they mentioned a specific workspace name, use that.
2. **Check if currently in a git repo**: Run `git rev-parse --show-toplevel 2>/dev/null` — extract the project name to use as implicit single-project workspace.
3. **If unclear**: Ask the user which workspace to use.

### Step 2: Understand the Task

If the user didn't provide a task description in their command, use AskUserQuestion:
- "What feature, bug fix, or task will you be working on in this workspace?"

### Step 3: Generate Instance Name

From the user's description, generate a short, kebab-case instance name:

**Guidelines:**
- Use 2-4 words maximum
- Use kebab-case (lowercase with hyphens)
- Be descriptive but concise
- **Do NOT auto-generate names with numbers** - no ticket numbers, PR numbers, issue numbers, dates, or digits
- Common prefixes: `fix-`, `feat-`, `refactor-`, `test-`, `chore-`

**Examples:**
- "fix the authentication bug in login" → `fix-auth-login`
- "adding dark mode support" → `feat-dark-mode`
- "refactoring the payment service" → `refactor-payments`

### Step 4: Confirm with User

Before creating, confirm:
- Workspace: `<workspace-name>` (list projects if multi-project)
- Instance name: `<generated-name>`
- Full path: `$GROVE_WORKSPACES_DIR/<workspace>/<instance-name>/`
- Branch: `<username>/<instance-name>` (or existing remote branch)

Ask if they want to proceed or modify the name.

### Step 5: Create the Workspace

```bash
gv <workspace> <instance-name>
```

The `gv` command handles fetching, branch resolution, direnv, post-create hooks, and agent config merging automatically.

### Step 6: Report Success

After creation, provide:
- The full path to the workspace
- The branch name created in each project
- Whether it's a single or multi-project workspace

---

## Action: DELETE

### Step 1: Determine Target

**If user specified an instance name:**
- Parse it from the command (e.g., `/grove delete fix-auth-login`)

**If user said "this workspace" or similar:**
- Check if currently in a workspace by checking if path matches `$GROVE_WORKSPACES_DIR/<workspace>/<instance>/...`
- Extract workspace and instance from the path
- Can use `gv --kms` to remove the current workspace from inside it

**If unclear:**
- Run `gv --list` to show available workspaces
- Ask user which one to delete

### Step 2: Check for Uncommitted Changes

For each project in the workspace:
```bash
cd <workspace-root>/<project> && git status --porcelain
```

If there are uncommitted changes:
- Warn the user
- List the changed files per project
- Ask if they still want to proceed

### Step 3: Confirm Deletion

ALWAYS confirm before deleting:
- Show: `<workspace>/<instance-name>`
- Show full path
- Show the branches that will be deleted
- Warn this is destructive

Use AskUserQuestion with "Yes, delete it" / "No, cancel" options.

### Step 4: CRITICAL - Change Directory First

**Working directory trap**: If your current working directory is inside the workspace you're about to delete, ALL subsequent Bash commands will fail.

**Before deleting, you MUST cd out in a SEPARATE command:**

```bash
cd $GROVE_PROJECTS_DIR
```

### Step 5: Delete

Only after successfully changing directory:

```bash
gv --rm <workspace> <instance-name>
# Or with --force if there are uncommitted changes:
gv --rm --force <workspace> <instance-name>
```

### Step 6: Report Result

- Confirm deletion
- The user is now in the projects directory

---

## Action: LIST

Simply run:

```bash
gv --list
```

Display the results to the user in a readable format.

---

## Action: CD

### Step 1: Determine Target

If user specified an instance (e.g., `/grove cd fix-auth-login`):
- Use that name

If not specified:
- Run `gv --list` and ask which one

### Step 2: Determine Workspace

- Check current path for workspace context
- Or ask if ambiguous

### Step 3: Switch to Workspace

```bash
gv <workspace> <instance-name>
```

This will switch to the tmux session (creating the workspace if it doesn't exist).

---

## Error Handling

- If `gv` command is not found: inform user to source their workspace manager (`source ~/.zsh/grove/grove.zsh`)
- If workspace doesn't exist: list available workspaces and ask
- If instance doesn't exist (for cd/delete): list available instances
- If instance already exists (for create): ask if they want to cd to it instead

---

## Known Gotchas

### Squash-Merge Detection

When checking if a branch has been merged, `git merge-base --is-ancestor` will NOT detect **squash-merged** branches. Check PR status via `gh pr view <branch> --json state,mergedAt` or `gt branch info <branch>`.

### Working Directory Persistence

The Bash tool's working directory persists across calls. Always cd out of a workspace in a **separate** Bash call before deleting it.
