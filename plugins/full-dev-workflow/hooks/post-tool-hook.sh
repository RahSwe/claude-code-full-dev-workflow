#!/bin/bash
# Full-Dev Workflow Post-Tool Hook
# Tracks modified files and detects test regressions
# Advisory mode: always allows, provides warnings

set -euo pipefail

# State file location
STATE_FILE=".claude/full-dev.local.md"

# Read hook input from stdin
# Check if stdin is connected (fixes Windows process leak where cat hangs)
if [ -t 0 ]; then
  # stdin is a terminal (not piped), no input available
  exit 0
fi
HOOK_INPUT=$(cat)

# If no state file exists, do nothing
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse tool name and result from hook input
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // empty' 2>/dev/null || echo "")
TOOL_RESULT=$(echo "$HOOK_INPUT" | jq -r '.tool_result // empty' 2>/dev/null || echo "")

# Exit if we couldn't parse the tool info
if [[ -z "$TOOL_NAME" ]]; then
  exit 0
fi

# Parse YAML frontmatter helper
parse_frontmatter() {
  local key="$1"
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep "^${key}:" | sed "s/${key}: *//" | sed 's/^"\(.*\)"$/\1/'
}

# Get active state
ACTIVE=$(parse_frontmatter "active")
if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Update timestamp helper
update_timestamp() {
  local TEMP_FILE="${STATE_FILE}.tmp.$$"
  local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  sed "s/^updated_at: .*/updated_at: \"$TIMESTAMP\"/" "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true
}

# Add file to modified_files list (deduplicated)
add_modified_file() {
  local file_path="$1"

  # Skip if file_path is empty
  if [[ -z "$file_path" ]]; then
    return
  fi

  # Check if already in list
  if grep -q "  - $file_path$" "$STATE_FILE" 2>/dev/null; then
    return
  fi

  # Add to modified_files section
  local TEMP_FILE="${STATE_FILE}.tmp.$$"

  # Find the line with "modified_files:" and add the new file after it
  awk -v file="$file_path" '
    /^modified_files:/ {
      print
      print "  - " file
      next
    }
    { print }
  ' "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true
}

# Update test status in state file
update_test_status() {
  local status="$1"
  local pass_count="${2:-0}"
  local fail_count="${3:-0}"

  local TEMP_FILE="${STATE_FILE}.tmp.$$"
  local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  sed -e "s/^test_status: .*/test_status: $status/" \
      -e "s/^last_test_run: .*/last_test_run: \"$TIMESTAMP\"/" \
      -e "s/^test_pass_count: .*/test_pass_count: $pass_count/" \
      -e "s/^test_fail_count: .*/test_fail_count: $fail_count/" \
      "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true
}

# Handle Edit tool - track modified files
if [[ "$TOOL_NAME" == "Edit" ]]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null || echo "")
  if [[ -n "$FILE_PATH" ]]; then
    add_modified_file "$FILE_PATH"
    update_timestamp
  fi
  exit 0
fi

# Handle Write tool - track modified files
if [[ "$TOOL_NAME" == "Write" ]]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null || echo "")
  if [[ -n "$FILE_PATH" ]]; then
    add_modified_file "$FILE_PATH"
    update_timestamp
  fi
  exit 0
fi

# Handle Bash tool - check for test commands and git commit
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null || echo "")

  # Check for test commands
  if echo "$COMMAND" | grep -qE '(npm test|npx vitest|npx jest|yarn test|pnpm test|playwright test)'; then
    # Try to parse test results
    PREV_PASS=$(parse_frontmatter "test_pass_count")
    PREV_FAIL=$(parse_frontmatter "test_fail_count")

    # Initialize if empty
    PREV_PASS=${PREV_PASS:-0}
    PREV_FAIL=${PREV_FAIL:-0}

    # Try to extract test counts from result (various formats)
    # Vitest format: "Tests  45 passed"
    # Jest format: "Tests:       45 passed, 0 failed"
    PASS_COUNT=$(echo "$TOOL_RESULT" | grep -oE '[0-9]+ pass(ed)?' | head -1 | grep -oE '[0-9]+' || echo "0")
    FAIL_COUNT=$(echo "$TOOL_RESULT" | grep -oE '[0-9]+ fail(ed|ure)?' | head -1 | grep -oE '[0-9]+' || echo "0")

    # Default to 0 if extraction failed
    PASS_COUNT=${PASS_COUNT:-0}
    FAIL_COUNT=${FAIL_COUNT:-0}

    # Determine status
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
      STATUS="failing"
    else
      STATUS="passing"
    fi

    # Update state
    update_test_status "$STATUS" "$PASS_COUNT" "$FAIL_COUNT"

    # Check for regression (tests that were passing now failing)
    if [[ "$PREV_FAIL" =~ ^[0-9]+$ ]] && [[ "$FAIL_COUNT" -gt "$PREV_FAIL" ]]; then
      REGRESSION_COUNT=$((FAIL_COUNT - PREV_FAIL))
      # Output advisory warning
      jq -n \
        --arg msg "WARNING: Test regression detected! $REGRESSION_COUNT new failing test(s). Previously: $PREV_FAIL failing, Now: $FAIL_COUNT failing." \
        '{
          "decision": "allow",
          "systemMessage": $msg
        }'
      exit 0
    fi
  fi

  # Check for git commit command
  if echo "$COMMAND" | grep -qE 'git commit'; then
    CURRENT_STATUS=$(parse_frontmatter "test_status")
    FAIL_COUNT=$(parse_frontmatter "test_fail_count")

    if [[ "$CURRENT_STATUS" == "failing" ]] && [[ "$FAIL_COUNT" =~ ^[0-9]+$ ]] && [[ "$FAIL_COUNT" -gt 0 ]]; then
      # Output advisory warning (but allow)
      jq -n \
        --arg msg "WARNING: Attempting to commit with $FAIL_COUNT failing test(s). Consider fixing tests before committing." \
        '{
          "decision": "allow",
          "systemMessage": $msg
        }'
      exit 0
    fi
  fi
fi

# ============================================
# PHASE COMPLETION SIGNAL DETECTION
# ============================================

# Detect phase completion signals in tool result
# Pattern: PHASE_COMPLETE: N (where N is 0-10)
if echo "$TOOL_RESULT" | grep -qE "PHASE_COMPLETE: [0-9]+"; then
  COMPLETED_PHASE=$(echo "$TOOL_RESULT" | grep -oE "PHASE_COMPLETE: [0-9]+" | head -1 | grep -oE "[0-9]+")

  if [[ -n "$COMPLETED_PHASE" ]]; then
    # Add to completed_phases array (deduplicated)
    CURRENT_LIST=$(parse_frontmatter "completed_phases")
    if [[ "$CURRENT_LIST" == "[]" || -z "$CURRENT_LIST" ]]; then
      NEW_LIST="[$COMPLETED_PHASE]"
    elif ! echo "$CURRENT_LIST" | grep -qE "\\b$COMPLETED_PHASE\\b"; then
      # Only add if not already present
      NEW_LIST=$(echo "$CURRENT_LIST" | sed "s/]$/, $COMPLETED_PHASE]/")
    else
      NEW_LIST="$CURRENT_LIST"
    fi

    TEMP_FILE="${STATE_FILE}.tmp.$$"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    sed -e "s/^completed_phases: .*/completed_phases: $NEW_LIST/" \
        -e "s/^updated_at: .*/updated_at: \"$TIMESTAMP\"/" \
        "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true

    # Emit confirmation message
    jq -n --arg msg "Phase $COMPLETED_PHASE marked complete. State updated." \
      '{"decision": "allow", "systemMessage": $msg}'
    exit 0
  fi
fi

# Detect entering new phase signal
# Pattern: ENTERING_PHASE: N (where N is 0-10)
if echo "$TOOL_RESULT" | grep -qE "ENTERING_PHASE: [0-9]+"; then
  NEXT_PHASE=$(echo "$TOOL_RESULT" | grep -oE "ENTERING_PHASE: [0-9]+" | head -1 | grep -oE "[0-9]+")

  if [[ -n "$NEXT_PHASE" ]]; then
    TEMP_FILE="${STATE_FILE}.tmp.$$"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    sed -e "s/^current_phase: .*/current_phase: $NEXT_PHASE/" \
        -e "s/^updated_at: .*/updated_at: \"$TIMESTAMP\"/" \
        "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true

    # Emit confirmation message
    jq -n --arg msg "Now in Phase $NEXT_PHASE. State updated." \
      '{"decision": "allow", "systemMessage": $msg}'
    exit 0
  fi
fi

# Default: allow with no message
exit 0
