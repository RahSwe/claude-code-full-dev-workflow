# Full-Dev Workflow Plugin

Complete feature development workflow with code mapping, TDD, multi-agent review, UI verification, PR management, and state persistence.

## Overview

This plugin provides:

1. **Complete development workflow** with 10 phases from planning to PR merge
2. **Bundled agents** for code exploration and multi-perspective code review
3. **Advisory warnings** when phase prerequisites aren't met
4. **State persistence** to track workflow progress across sessions
5. **Resume capability** to continue workflows from where they left off
6. **Modified files tracking** for code simplifier in Phase 6
7. **Test regression detection** to alert when previously passing tests fail
8. **Pre-commit verification** to warn before commits with failing tests

## Commands

### `/full-dev-workflow:full-dev <feature>`

Start the full development workflow for a new feature.

```bash
/full-dev-workflow:full-dev Add user authentication with OAuth
```

### `/full-dev-workflow:resume`

Resume an interrupted full-dev workflow from saved state.

```bash
/full-dev-workflow:resume
```

### `/full-dev-workflow:help`

Show plugin help and available commands.

```bash
/full-dev-workflow:help
```

The resume command:

- Reads `.claude/full-dev.local.md` state file
- Displays workflow summary
- Offers options to continue, restart phase, or start fresh
- Restores TodoWrite with remaining phases

## Bundled Agents

This plugin includes specialized agents for each workflow phase:

| Agent                                    | Phase | Purpose                                     |
| ---------------------------------------- | ----- | ------------------------------------------- |
| `full-dev-workflow:code-explorer`        | 1     | Maps codebase and identifies affected files |
| `full-dev-workflow:test-architect`       | 2     | Designs test strategy and test structure    |
| `full-dev-workflow:reviewer-conventions` | 4     | Reviews for CLAUDE.md compliance            |
| `full-dev-workflow:reviewer-bugs`        | 4     | Detects bugs and edge cases                 |
| `full-dev-workflow:reviewer-quality`     | 4     | Checks DRY, readability, maintainability    |
| `full-dev-workflow:reviewer-security`    | 4     | OWASP Top 10 security review                |
| `full-dev-workflow:reviewer-performance` | 4     | Performance and scalability analysis        |

## Hooks

### Stop Hook (`stop-hook.sh`)

**Type**: Stop (fires when session exits)

**Behavior**:

- Checks for active workflow state
- Shows advisory warning if exiting mid-phase
- Saves current timestamp to state file
- Always allows exit (advisory mode)

**Example warning**:

```text
[CRITICAL] Full-dev workflow 'Add auth feature' - Phase 3 (Ralph Loop Implementation) incomplete.
Progress saved to .claude/full-dev.local.md. Use /full-dev-workflow:resume to continue.
```

### User Prompt Hook (`user-prompt-hook.sh`)

**Type**: UserPromptSubmit (fires when user sends message)

**Behavior**:

- Detects approval keywords in user message during Phase 0
- Updates `user_approved_plan: true` when approval detected
- Approval keywords: yes, approved, go ahead, looks good, proceed, lgtm, ok, okay, approve, ship it, do it, continue, start

**Example output**:

```text
Plan approval detected. Workflow will proceed to Phase 1.
```

### Post Tool Hook (`post-tool-hook.sh`)

**Type**: PostToolUse (fires after tool execution)

**Behavior**:

1. **After Edit/Write tools**: Adds file to `modified_files` list
2. **After test commands**: Updates `test_status`, detects regressions
3. **Before git commit**: Warns if tests are failing

**Test regression warning**:

```text
WARNING: Test regression detected! 3 new failing test(s).
Previously: 0 failing, Now: 3 failing.
```

**Pre-commit warning**:

```text
WARNING: Attempting to commit with 3 failing test(s).
Consider fixing tests before committing.
```

## State File

**Location**: `.claude/full-dev.local.md`

**Format**: Markdown with YAML frontmatter

```yaml
---
active: true
feature: "Add user authentication"
branch: "feature/user-auth"
started_at: "2026-01-10T10:00:00Z"
updated_at: "2026-01-10T10:30:00Z"

# Phase tracking
current_phase: 3
completed_phases: [0, 1, 2]
user_approved_plan: true
approval_timestamp: "2026-01-10T10:05:00Z"

# Plan info
plan_file: ".claude/plans/user-auth.md"

# Modified files (for Phase 6 code simplifier)
modified_files:
  - frontend/src/components/Auth.tsx
  - server/endpoints/api/auth.ts

# Test status
test_status: passing
last_test_run: "2026-01-10T10:28:00Z"
test_pass_count: 45
test_fail_count: 0

# Review status
review_agents_completed: 0
review_issues_found: 0

# PR Review Loop (Phase 9-10)
pr_url: ""
pr_review_iterations: 0
max_pr_iterations: 10
---
```

## Advisory Mode

All hooks operate in **advisory mode**, meaning they:

- Always allow actions to proceed
- Provide warnings via `systemMessage`
- Never block the user

This ensures the workflow remains flexible while providing helpful guidance.

## Phase Names

| Phase | Name                      |
| ----- | ------------------------- |
| 0     | Plan Mode                 |
| 1     | Code Mapping              |
| 2     | Test Creation             |
| 3     | Ralph Loop Implementation |
| 4     | Multi-Agent Code Review   |
| 5     | Automatic Fixes           |
| 6     | Code Simplification       |
| 7     | UI Verification           |
| 8     | Push PR                   |
| 9-10  | PR Review Loop            |

## Critical Phases

Phases 3, 5, 9, and 10 show stronger warnings when exiting:

- Phase 3: Implementation in progress
- Phase 5: Automatic fixes in progress
- Phase 9-10: PR review loop active

## Files

```text
.claude/plugins/full-dev-workflow/
├── .claude-plugin/
│   └── plugin.json               # Plugin metadata
├── agents/
│   ├── code-explorer.md          # Phase 1 code mapping
│   ├── test-architect.md         # Phase 2 test design
│   ├── reviewer-bugs.md          # Phase 4 bug detection
│   ├── reviewer-conventions.md   # Phase 4 convention compliance
│   ├── reviewer-quality.md       # Phase 4 code quality
│   ├── reviewer-security.md      # Phase 4 security review
│   └── reviewer-performance.md   # Phase 4 performance review
├── commands/
│   ├── full-dev.md               # Main workflow command
│   ├── resume.md                 # Resume interrupted workflow
│   └── help.md                   # Plugin help
├── hooks/
│   ├── hooks.json                # Hook registration
│   ├── stop-hook.sh              # Advisory exit warnings
│   ├── user-prompt-hook.sh       # Approval detection
│   └── post-tool-hook.sh         # File/test tracking
└── README.md                     # This file
```

## Troubleshooting

### State file not updating

- Ensure the plugin is listed in `.claude/settings.json` under `plugins.local`
- Check hook scripts have execute permissions: `chmod +x hooks/*.sh`

### Approval not detected

- Use one of the approval keywords: yes, approved, go ahead, looks good, proceed, lgtm
- Ensure you're in Phase 0 with `user_approved_plan: false`

### Test regression not detected

- Hook parses test output for patterns like "N passed" and "N failed"
- Different test frameworks may need pattern adjustments

### Want to start fresh

- Delete `.claude/full-dev.local.md` manually
- Or when `/full-dev` detects existing state, choose "start fresh"

## Development

To test hooks locally:

```bash
# Test stop hook
echo '{"transcript_path": "/tmp/test.jsonl"}' | .claude/plugins/full-dev-workflow/hooks/stop-hook.sh

# Test user prompt hook
echo '{"message": "yes, looks good"}' | .claude/plugins/full-dev-workflow/hooks/user-prompt-hook.sh

# Test post tool hook
echo '{"tool_name": "Edit", "tool_input": {"file_path": "test.ts"}}' | .claude/plugins/full-dev-workflow/hooks/post-tool-hook.sh
```
