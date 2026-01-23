---
description: Complete feature development workflow with code mapping, TDD, Ralph loop, multi-agent review, UI verification, and PR management
argument-hint: "<feature description>"
allowed-tools: Bash(gh:*), Bash(git:*), Bash(npm:*), Bash(npx:*), Bash(yarn:*), Bash(pnpm:*), Read, Write, Edit, Glob, Grep, Task, TodoWrite, EnterPlanMode, ExitPlanMode
---

# Full Development Workflow

You are executing a comprehensive feature development workflow. Follow each phase systematically, using the TodoWrite tool to track progress throughout.

**Feature to implement**: $ARGUMENTS

---

## Workflow State Management

**State File**: `.claude/full-dev.local.md`

### Initialization (BEFORE Phase 0)

1. Check if `.claude/full-dev.local.md` exists:
   - If exists and `active: true`: Ask user if they want to `/full-dev-workflow:resume` or start fresh
   - If user wants fresh start: Delete existing state file
2. Get current git branch: `git branch --show-current`
3. Create new state file with this structure:

```yaml
---
active: true
feature: "$ARGUMENTS"
branch: "<current-branch>"
started_at: "<ISO-8601 timestamp>"
updated_at: "<ISO-8601 timestamp>"

# Phase tracking
current_phase: 0
completed_phases: []
user_approved_plan: false
approval_timestamp: ""

# Plan info
plan_file: ""

# Modified files (for Phase 6 code simplifier)
modified_files:

# Test status
test_status: unknown
last_test_run: ""
test_pass_count: 0
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

### After Each Phase Completion

Update the state file:

1. Add current phase number to `completed_phases` array
2. Increment `current_phase` to next phase
3. Update `updated_at` timestamp
4. Update phase-specific fields (e.g., `plan_file`, `test_status`, `pr_url`)

### Phase-Specific State Updates

- **Phase 0**: Set `plan_file`, wait for `user_approved_plan: true` (detected by hook)
- **Phase 2**: Update `test_status: failing` after running initial tests
- **Phase 3**: Update `test_status: passing` when Ralph completes
- **Phase 4**: Update `review_agents_completed` and `review_issues_found`
- **Phase 6**: Read `modified_files` for code simplifier input
- **Phase 8**: Set `pr_url` after PR creation
- **Phase 9-10**: Increment `pr_review_iterations` each cycle

---

## Phase Transition Protocol (CRITICAL)

**Every phase transition MUST emit signals** to trigger automatic state file updates via hooks.

### At the END of each phase, run

```bash
echo "PHASE_COMPLETE: N"
```

Where N is the phase number just completed (0-10).

### At the START of the next phase, run

```bash
echo "ENTERING_PHASE: N"
```

Where N is the phase number being started.

### Example - After Phase 0 approval

```bash
echo "PHASE_COMPLETE: 0"
echo "ENTERING_PHASE: 1"
```

### Why this matters

These signals are detected by the `post-tool-hook.sh` and automatically update:

- `current_phase` in state file
- `completed_phases` array
- `updated_at` timestamp

**This ensures state file updates survive context compaction**, allowing `/full-dev-workflow:resume` to work correctly even if the conversation is interrupted.

---

## Phase 0: Plan Mode - Feature Specification (REQUIRED)

**Goal**: Get user approval on feature specification before any implementation

**IMPORTANT**: This phase is MANDATORY. Do not skip to Phase 1 without explicit user approval.

**Actions**:

1. **Enter Plan Mode** using the `EnterPlanMode` tool
2. **Explore the codebase** using Glob, Grep, and Read tools to understand:
   - Existing patterns and architecture relevant to this feature
   - Files that will need modification
   - Integration points and dependencies
   - Similar existing implementations to learn from
3. **Create Feature Specification** including:
   - Clear description of what will be built
   - List of files to create/modify
   - Database schema changes (if any)
   - API endpoints (if any)
   - UI components (if any)
4. **Define E2E Test Requirements**:
   - User flows to test
   - Expected behaviors
   - Edge cases to cover
   - Acceptance criteria
5. **Write the plan** to a file in `.claude/plans/` directory
6. **Exit Plan Mode** using `ExitPlanMode` tool
7. **Wait for explicit user approval** before proceeding to Phase 1

**Quality Gate**: Do NOT proceed until user explicitly approves the plan.

**Output**: Approved feature specification with clear E2E test requirements

**Phase 0 Exit** (after user approval):

```bash
echo "PHASE_COMPLETE: 0"
echo "ENTERING_PHASE: 1"
```

---

## Phase 1: Code Mapping & Discovery

**Goal**: Understand all code affected by this feature

**Actions**:

1. Create initial todo list with all 10 phases
2. Launch 2-3 `full-dev-workflow:code-explorer` agents in parallel to:
   - Map existing code patterns related to this feature
   - Identify all files that will need modification
   - Trace dependencies and integration points
   - Find similar existing implementations to learn from
3. Each agent must return a list of 5-10 key files to read
4. Read all identified files to build deep understanding
5. Present summary: affected files, patterns found, integration points

**Output**: Comprehensive map of affected code and architecture

**Phase 1 Exit**:

```bash
echo "PHASE_COMPLETE: 1"
echo "ENTERING_PHASE: 2"
```

---

## Phase 2: Test Creation (E2E + Integration)

**Goal**: Create comprehensive test suite BEFORE implementation (TDD)

**Actions**:

1. Based on Phase 1 findings, identify:
   - What E2E tests are needed (user flows)
   - What integration tests are needed (component interactions)
   - What unit tests are needed (isolated logic)
2. Launch `full-dev-workflow:test-architect` agent to design test strategy
3. Create test files following project conventions:
   - E2E tests in appropriate directory (e.g., `e2e/`, `cypress/`, `playwright/`)
   - Integration tests alongside feature code
   - Unit tests for core logic
4. Run tests to confirm they fail (red phase of TDD)
5. Commit test files: "test: add tests for [feature]"

**Output**: Failing test suite ready for implementation

**Phase 2 Exit**:

```bash
echo "PHASE_COMPLETE: 2"
echo "ENTERING_PHASE: 3"
```

---

## Phase 3: Ralph Loop Implementation

**Goal**: Implement feature iteratively until all tests pass

**Actions**:

1. Prepare Ralph loop prompt with clear completion criteria:

   ```text
   Implement [feature] following TDD:
   - Read existing code patterns from Phase 1
   - Implement minimum code to make ONE test pass
   - Run tests after each change
   - Iterate until ALL tests pass
   - Follow project conventions strictly
   - Include ALL_TESTS_PASS and EXIT_SIGNAL: true when complete
   ```

2. Start Ralph loop: `/full-dev-workflow:ralph "<prompt>" --completion-promise "ALL_TESTS_PASS" --max-iterations 30 --timeout 60`
3. Ralph will iterate with:
   - **Dual-condition exit gate**: Requires both completion signal AND EXIT_SIGNAL: true
   - **Circuit breaker**: Stops on 3 consecutive real errors
   - **Rate limiting**: 100 API calls/hour (prevents runaway loops)
   - **Session continuity**: Preserves context across interruptions
4. If max iterations reached without success:
   - Document what's blocking progress
   - Ask user for guidance

**Output**: Working implementation with passing tests

**Phase 3 Exit**:

```bash
echo "PHASE_COMPLETE: 3"
echo "ENTERING_PHASE: 4"
```

---

## Phase 4: Multi-Agent Code Review

**Goal**: Get comprehensive feedback from 5 independent review perspectives

**Actions**:

1. Launch 5 parallel reviewer agents with different focuses:
   - **Agent 1**: `full-dev-workflow:reviewer-conventions` - CLAUDE.md/project conventions compliance
   - **Agent 2**: `full-dev-workflow:reviewer-bugs` - Bug detection and edge cases
   - **Agent 3**: `full-dev-workflow:reviewer-quality` - Code quality (DRY, simplicity, readability)
   - **Agent 4**: `full-dev-workflow:reviewer-security` - Security vulnerabilities (OWASP top 10)
   - **Agent 5**: `full-dev-workflow:reviewer-performance` - Performance and scalability concerns
2. Each agent scores issues 0-100 confidence
3. Collect all findings and filter to confidence >= 75
4. Present consolidated review with categories:
   - Critical (must fix)
   - Important (should fix)
   - Minor (nice to fix)

**Output**: Prioritized list of issues to address

**Phase 4 Exit**:

```bash
echo "PHASE_COMPLETE: 4"
echo "ENTERING_PHASE: 5"
```

---

## Phase 5: Automatic Fixes (No User Input)

**Goal**: Automatically address all review findings above confidence threshold

**IMPORTANT**: This phase runs fully autonomously - no user input required.

**Actions**:

1. Filter issues by confidence score:
   - **Fix automatically**: All issues with confidence >= 75
   - **Skip**: Issues with confidence < 75 (likely false positives)
2. Sort issues by severity: Critical -> Important -> Minor
3. For each issue to fix (in order):
   - Read the affected file
   - Apply the suggested fix
   - Run tests immediately to confirm no regression
   - If tests fail, revert and try alternative fix
   - Mark issue as resolved in todo list
4. After all fixes applied:
   - Run full test suite
   - If any tests fail, debug and fix
5. If significant changes made (>5 files or >100 lines):
   - Re-run the 5 review agents on changed code
   - Repeat fix cycle for any new issues >= 75 confidence
6. Commit all fixes: "fix: address code review feedback"

**Decision Logic**:

- Confidence >= 90: Fix immediately, high priority
- Confidence 75-89: Fix after critical issues
- Confidence < 75: Skip (document as "reviewed, no action")

**Output**: Clean code with all high-confidence issues automatically resolved

**Phase 5 Exit**:

```bash
echo "PHASE_COMPLETE: 5"
echo "ENTERING_PHASE: 6"
```

---

## Phase 6: Code Simplification

**Goal**: Simplify and refine all code for clarity, consistency, and maintainability

**IMPORTANT**: This phase runs fully autonomously using the native code-simplifier agent.

**Actions**:

1. Identify all files modified during this workflow (from `modified_files` in state)
2. Run the `full-dev-workflow:code-simplifier` agent on each modified file:
   - Simplify complex logic
   - Improve variable and function naming
   - Remove redundant code
   - Ensure consistent formatting
   - Improve readability without changing functionality
3. After each simplification:
   - Run tests to confirm no regression
   - If tests fail, revert the simplification
4. Review the cumulative changes:
   - Ensure code still follows project conventions
   - Verify no functionality was accidentally changed
5. Commit simplifications: "refactor: simplify and clean up code"

**Focus Areas**:

- Reduce cyclomatic complexity
- Extract repeated code into functions
- Improve naming clarity
- Remove dead code
- Simplify conditional logic
- Improve code organization

**Output**: Clean, simplified code ready for PR

**Phase 6 Exit**:

```bash
echo "PHASE_COMPLETE: 6"
echo "ENTERING_PHASE: 7"
```

---

## Phase 7: UI Verification (Browser)

**Goal**: Verify feature works correctly in actual UI

**Actions**:

1. Check if this is a UI-affecting feature
2. If yes, use the `browser-use` skill for automated UI testing:
   - Invoke the skill: `/full-dev-workflow:browser-use`
   - Use `browser-use open <url>` to navigate to relevant pages
   - Use `browser-use state` to inspect page elements
   - Use `browser-use click <index>` to test user interactions
   - Use `browser-use screenshot <path>` to capture visual evidence
   - Use `browser-use eval "console.log(...)"` to check for console errors
   - Document findings with screenshots
3. If issues found:
   - Document with screenshots
   - Fix issues
   - Re-verify using browser-use
4. If no UI changes, skip this phase
5. Always clean up: `browser-use close` when done

**Browser-use Quick Reference**:

```bash
browser-use open https://localhost:3000        # Navigate to app
browser-use state                              # Get clickable elements
browser-use click <index>                      # Click element by index
browser-use input <index> "text"               # Type into element
browser-use screenshot ui-verification.png     # Save screenshot
browser-use close                              # Clean up
```

**Output**: Verified UI functionality with evidence (screenshots)

**Phase 7 Exit**:

```bash
echo "PHASE_COMPLETE: 7"
echo "ENTERING_PHASE: 8"
```

---

## Phase 8: Push PR

**Goal**: Create and push a well-documented pull request

**Actions**:

1. Ensure all changes are committed with meaningful messages
2. Run final test suite to confirm all pass
3. Run linting/formatting if project has it
4. Create feature branch if not already on one
5. Push to remote: `git push -u origin <branch>`
6. Create PR using gh CLI:

   ```bash
   gh pr create --title "<descriptive title>" --body "$(cat <<'EOF'
   ## Summary
   <what this PR does>

   ## Changes
   <list of key changes>

   ## Test Plan
   - [ ] All tests pass
   - [ ] E2E tests cover main flows
   - [ ] UI verified in browser

   ## Screenshots
   <if applicable>

   Generated with Claude Code Full Dev Workflow
   EOF
   )"
   ```

7. Return PR URL

**Output**: Open pull request ready for human review

**Phase 8 Exit**:

```bash
echo "PHASE_COMPLETE: 8"
echo "ENTERING_PHASE: 9"
```

---

## Phase 9-10: PR Review Loop (Autonomous)

**Goal**: Continuously monitor PR, address feedback, and iterate until approval

**IMPORTANT**: This phase runs as an autonomous loop - no user input required. The loop continues until no medium or higher severity suggestions remain.

**CRITICAL**: Fetch ALL review comments SHORTLY after pushing. Automated bots (Codex, Greptile, etc.) post comments within 10-30 seconds of a push - do NOT wait for CI checks to complete before fetching reviews.

**Loop Structure**:

```text
WHILE (has_medium_or_higher_suggestions):
    1. Fetch ALL PR reviews and comments (don't wait for CI)
    2. Categorize by severity (prioritize bot reviews with file/line refs)
    3. If suggestions exist: review if the suggestions are valid, fix valid suggestions and push
    4. Wait approxmately two minutes for follow-up reviews (NOT for CI checks)
    5. Repeat
```

**Actions per iteration**:

### Step 1: Fetch PR Feedback (IMMEDIATELY after push)

```bash
# Get human and bot reviews (approval status, review bodies)
gh pr view --json reviews,reviewDecision

# CRITICAL: Get inline code comments - this is where Codex/Greptile post findings
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments

# Get general discussion comments
gh pr view --comments
```

**Bot Review Priority Indicators**:

- **P1 (Critical)**: Bot comments with specific file:line references and security/bug keywords
- **P2 (High)**: Bot comments suggesting code changes with diff snippets
- **P3 (Medium)**: Bot comments with general suggestions
- **P4 (Low)**: Bot comments that are informational only

### Step 2: Categorize Feedback by Severity

- **Critical (must fix)**:
  - "Changes requested" review status
  - Security vulnerabilities
  - Permission/authorization bypass issues
  - Breaking bugs
  - Blocking issues explicitly marked
  - Bot reviews with specific file/line references flagging security or logic errors
- **Medium (should fix)**:
  - Code quality suggestions
  - Performance concerns
  - Missing error handling
  - Suggestions from senior reviewers
  - Bot reviews suggesting code changes with diff snippets
- **Low (optional)**:
  - Style preferences
  - Minor nitpicks
  - "Nice to have" suggestions
  - Questions (respond but no code change)

### Step 3: Process Feedback (If Medium+ Exists)

1. For each Critical issue:
   - Read the specific file and line referenced
   - Implement the requested change if it is valid
   - Run tests to verify no regression
   - Mark as addressed
2. For each Medium issue:
   - Evaluate if change improves code
   - Implement fix
   - Run tests
   - Mark as addressed
3. For Low issues:
   - Reply explaining decision (fix or skip)
   - No code changes required but implement if valuable

### Step 4: Push Updates

```bash
git add -A
git commit -m "fix: address PR review feedback

- [List of changes made]

Co-Authored-By: Claude Code <noreply@anthropic.com>"
git push
```

### Step 5: Notify Reviewers

```bash
gh pr comment --body "Addressed review feedback:
- [Summary of changes]

Ready for re-review."
```

### Step 6: Poll for New Reviews (Active Polling)

**Polling Strategy**:

- **First iteration**: Fetch reviews IMMEDIATELY after push (bots respond in 10-30 seconds)
- **After fix push**: Wait approximately two minutes, then fetch again
- **Do NOT wait for CI checks** - bot reviews are independent of CI status

```bash
# Wait briefly for bot reviews (NOT for CI)
sleep 15

# Fetch all review types again
gh pr view --json reviews,reviewDecision
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments
gh pr view --comments
```

- If new medium+ suggestions: continue loop
- If only low/no suggestions: exit loop

**WARNING**: Do NOT use "all CI checks passing" as an exit condition. Exit when there are no unresolved medium+ severity suggestions, regardless of CI status.

**Exit Conditions** (loop stops when ANY is true):

- No unresolved medium or higher severity suggestions
- PR is approved by all required reviewers
- PR is merged
- Max iterations reached (default: 10 review cycles)

**Final Actions (after loop exits)**:

1. Run full E2E test suite
2. Post final summary:

   ```bash
   gh pr comment --body "All feedback addressed. Tests passing. Ready for merge."
   ```

3. Report completion status

**Output**: PR with all medium+ feedback addressed, tests passing, ready for merge

**Phase 9-10 Exit** (when PR is approved or merged):

```bash
echo "PHASE_COMPLETE: 9"
echo "PHASE_COMPLETE: 10"
```

---

## Workflow Control

- After each phase, update todos and present status to user
- User can skip phases if not applicable
- User can re-run specific phases if needed
- If blocked at any phase, document and ask for guidance

---

## Start Now

Begin with Phase 0: Plan Mode - Feature Specification for the feature: $ARGUMENTS

**First action**: Call `EnterPlanMode` tool, then explore the codebase to create a comprehensive feature specification.
