---
description: Resume an interrupted full-dev workflow from saved state
allowed-tools: Bash(gh:*), Bash(git:*), Bash(npm:*), Bash(npx:*), Bash(yarn:*), Bash(pnpm:*), Read, Write, Edit, Glob, Grep, Task, TodoWrite, EnterPlanMode, ExitPlanMode
---

# Resume Full-Dev Workflow

You are resuming an interrupted full-dev workflow. Follow these steps to restore context and continue.

## Step 1: Check for Existing State

Read the workflow state file at `.claude/full-dev.local.md`.

If the file does not exist:

- Inform the user: "No interrupted workflow found. Use `/full-dev-workflow:full-dev <feature>` to start a new workflow."
- Stop here.

## Step 2: Parse and Display State Summary

Extract from the state file:

- `feature`: The feature being implemented
- `branch`: The git branch
- `current_phase`: Where the workflow was interrupted
- `completed_phases`: Phases already finished
- `user_approved_plan`: Whether Phase 0 was approved
- `modified_files`: Files changed during the workflow
- `test_status`: Current test status
- `pr_url`: PR URL if created

Present a summary to the user:

```
## Workflow Resume Summary

**Feature**: [feature name]
**Branch**: [branch name]
**Started**: [started_at]
**Last Updated**: [updated_at]

### Progress
- Completed Phases: [list]
- Current Phase: [current_phase] ([phase_name])
- Plan Approved: [yes/no]

### Test Status
- Status: [passing/failing]
- Pass: [count] | Fail: [count]
- Last Run: [timestamp]

### Modified Files
[list of files]

### PR Status
[PR URL if exists, or "Not created yet"]
```

## Step 3: Validate State Integrity

Perform validation checks:

1. **Git branch matches**: `git branch --show-current` should match state branch
2. **Plan file exists**: If `plan_file` is set, verify it exists
3. **PR exists** (if in Phase 9-10): Verify PR URL is valid with `gh pr view`
4. **Phase completion signals worked**:
   - `completed_phases` should contain phases 0 through (`current_phase` - 1)
   - If gaps exist (e.g., `current_phase: 5` but `completed_phases: []`), warn user about potentially skipped phases
   - Suggest using `git diff --name-only` to verify actual work done vs. state tracking

**State Recovery** (if phase tracking is out of sync):

If you detect that phases were completed but not tracked (state shows phase 0 but files clearly show implementation):

1. Ask user to confirm which phases were actually completed
2. Manually update `completed_phases` to match reality:
   ```bash
   echo "PHASE_COMPLETE: 0"
   echo "PHASE_COMPLETE: 1"
   # ... for each completed phase
   ```

Report any inconsistencies to the user.

## Step 4: Restore TodoWrite

Create a todo list with remaining phases:

```
Phase 0: Plan Mode - [completed/current/pending]
Phase 1: Code Mapping - [completed/current/pending]
Phase 2: Test Creation - [completed/current/pending]
Phase 3: Ralph Loop Implementation - [completed/current/pending]
Phase 4: Multi-Agent Code Review - [completed/current/pending]
Phase 5: Automatic Fixes - [completed/current/pending]
Phase 6: Code Simplification - [completed/current/pending]
Phase 7: UI Verification - [completed/current/pending]
Phase 8: Push PR - [completed/current/pending]
Phase 9-10: PR Review Loop - [completed/current/pending]
```

Mark phases according to state:

- Phases in `completed_phases` -> `completed`
- Phase equal to `current_phase` -> `in_progress`
- Higher phases -> `pending`

## Step 5: Ask User How to Proceed

Present options:

1. **Continue from current phase**: Resume Phase [X] where it was interrupted
2. **Restart current phase**: Start Phase [X] fresh
3. **Go back one phase**: Return to Phase [X-1] and redo
4. **Start fresh**: Delete state and run `/full-dev-workflow:full-dev` again

Wait for user to choose before proceeding.

## Step 6: Resume Workflow

Based on user choice, continue with the appropriate phase from the full-dev workflow.

### Phase-Specific Resume Logic

**Phase 0 (Plan Mode)**:

- If plan file exists and approved, proceed to Phase 1
- If plan file exists but not approved, present plan and wait for approval
- If no plan file, re-enter Plan Mode

**Phase 1 (Code Mapping)**:

- Re-read the plan file to restore context
- Continue or restart code exploration

**Phase 2 (Test Creation)**:

- Check what test files exist
- Continue writing remaining tests

**Phase 3 (Ralph Loop)**:

- Check if `.claude/ralph-loop.local.md` exists
- If yes, Ralph loop can continue automatically
- If no, restart Ralph loop with appropriate prompt

**Phase 4 (Code Review)**:

- Check `review_agents_completed` count
- Launch remaining review agents if incomplete

**Phase 5 (Automatic Fixes)**:

- Review which issues were addressed
- Continue fixing remaining issues

**Phase 6 (Code Simplification)**:

- Use `modified_files` list from state
- Run simplifier on any files not yet simplified

**Phase 7 (UI Verification)**:

- Ask user if UI verification is needed
- Perform or skip as appropriate

**Phase 8 (Push PR)**:

- Check if PR exists with `gh pr view`
- If exists, proceed to Phase 9-10
- If not, create PR

**Phase 9-10 (PR Review Loop)**:

- Fetch current PR status
- Check `pr_review_iterations` count
- Continue review loop

## Important Notes

- **Emit phase signals** at phase boundaries to trigger automatic state updates:
  ```bash
  echo "PHASE_COMPLETE: N"
  echo "ENTERING_PHASE: N"
  ```
- These signals are detected by hooks and update the state file automatically
- Keep `modified_files` list current
- Update `test_status` after running tests
- Save state before any potentially failing operation

## Start Now

Read `.claude/full-dev.local.md` and present the workflow status summary.
