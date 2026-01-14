---
description: Autonomous AI development loop with intelligent exit detection, circuit breaker, and rate limiting
argument-hint: "<prompt>" [--completion-promise "<signal>"] [--max-iterations N] [--timeout M]
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep, Task, TodoWrite
---

# Ralph Loop - Autonomous Development

You are executing an autonomous development loop based on Geoffrey Huntley's technique, with advanced safety features from the frankbria/ralph-claude-code implementation.

## Configuration

Parse the following from $ARGUMENTS:
- **Prompt**: The main task/prompt (required)
- **--completion-promise**: Signal indicating completion (e.g., "ALL_TESTS_PASS")
- **--max-iterations**: Maximum loop iterations (default: 30)
- **--timeout**: Minutes per iteration (default: 60)

## Core Features

### 1. Dual-Condition Exit Gate
The loop only exits when BOTH conditions are met:
1. **Completion signals detected** (completion promise found in output)
2. **Explicit EXIT_SIGNAL: true** included in response

This prevents premature termination when heuristics might falsely indicate completion.

### 2. Circuit Breaker
Two-stage error filtering:
- Stage 1: Filter false positives (JSON `"error": null`, error in variable names)
- Stage 2: Detect real errors (stack traces, FATAL, Exception, command failures)

After 3 consecutive real errors, the circuit trips and the loop stops.

### 3. Rate Limiting
- Default: 100 API calls per hour
- Automatically waits and resets when limit reached
- Prevents runaway loops from exhausting API quotas

### 4. Session Continuity
- Sessions persist for 24 hours
- Context preserved across interruptions
- Auto-reset on circuit breaker trips or completion

---

## Execution Flow

### Initialize Session

1. Read configuration from `.claude/ralph.local.md` if it exists:
   ```yaml
   ---
   rate_limit: 100
   timeout_minutes: 60
   max_iterations: 30
   session_expiry_hours: 24
   circuit_breaker_threshold: 3
   ---
   ```

2. Create/resume session state in `.claude/ralph-session.state`

3. Initialize circuit breaker and rate limiter state files

### Main Loop

```
FOR iteration = 1 TO max_iterations:

    1. CHECK rate limit
       - If limited: wait for reset, then continue

    2. CHECK session validity
       - If expired: end with "session_expired"

    3. EXECUTE task iteration:
       - Include iteration count in context
       - Include completion promise requirements
       - Run with timeout protection

    4. ANALYZE output through circuit breaker:
       - Filter false positive errors
       - Detect real errors
       - If 3 consecutive errors: trip circuit, EXIT

    5. CHECK exit conditions (dual-gate):
       - Completion signal present? (count >= 1)
       - EXIT_SIGNAL: true present?
       - Both met? → SUCCESS EXIT

    6. UPDATE session state

    7. CONTINUE to next iteration
```

### Exit Conditions

The loop exits when ANY of these occur:
- **Success**: Completion promise AND EXIT_SIGNAL: true detected
- **Max iterations**: Reached limit without completion
- **Circuit tripped**: 3+ consecutive errors
- **Rate limited**: After waiting, if still limited
- **Session expired**: 24+ hours elapsed
- **Manual interrupt**: User cancelled

---

## Iteration Instructions

For each iteration, include this context in your work:

```
ITERATION CONTEXT:
- Current iteration: [N] of [MAX]
- Completion promise: [SIGNAL]
- Task: [PROMPT]

COMPLETION REQUIREMENTS:
When the task is FULLY complete:
1. Include the completion signal in your response: [SIGNAL]
2. Include: EXIT_SIGNAL: true

If work remains:
- Do NOT include EXIT_SIGNAL
- Continue making progress
- The loop will automatically continue
```

---

## State Files

### Session State (`.claude/ralph-session.state`)
```
session_id="<unique-id>"
started_at="<ISO-8601>"
iteration_count=<N>
status="active|ended"
exit_reason=""
```

### Circuit State (`.claude/ralph-circuit.state`)
```
consecutive_errors=<N>
threshold=3
tripped=false|true
last_error=""
```

### Rate State (`.claude/ralph-rate.state`)
```
calls_this_hour=<N>
hour_start=<unix-timestamp>
rate_limit=100
```

---

## Error Handling

### Real Errors (increment circuit counter)
- `Error:`, `ERROR:`, `FATAL:`
- `Exception:`, `Traceback`
- `SyntaxError:`, `TypeError:`, etc.
- `npm ERR!`, `command not found`
- Non-zero exit codes with error messages

### False Positives (ignored)
- `"error": null` in JSON
- `"error": ""` empty strings
- `error_handler`, `on_error` in code
- `"success": true` with error field present

---

## Usage Examples

### Basic TDD Loop
```
/full-dev-workflow:ralph "Implement user authentication following TDD" --completion-promise "ALL_TESTS_PASS" --max-iterations 20
```

### Bug Fix with Short Timeout
```
/full-dev-workflow:ralph "Fix the login redirect bug" --completion-promise "BUG_FIXED" --max-iterations 10 --timeout 30
```

### Feature Implementation
```
/full-dev-workflow:ralph "Add dark mode support to all components" --completion-promise "FEATURE_COMPLETE" --max-iterations 25
```

---

## Start Execution

Begin the autonomous loop now with the provided arguments: $ARGUMENTS

1. Parse configuration
2. Initialize session and safety systems
3. Start iterating toward completion
4. Exit when conditions met or limits reached
