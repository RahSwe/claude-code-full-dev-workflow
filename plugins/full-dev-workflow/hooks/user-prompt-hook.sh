#!/bin/bash
# Full-Dev Workflow User Prompt Hook
# Detects user approval for Phase 0 plan
# Advisory mode: always allows, updates state when approval detected

set -euo pipefail

# State file location
STATE_FILE=".claude/full-dev.local.md"

# Approval keywords (case-insensitive matching)
APPROVAL_KEYWORDS="yes|approved|go ahead|looks good|proceed|lgtm|ok|okay|approve|ship it|do it|continue|start"

# Read hook input from stdin
HOOK_INPUT=$(cat)

# If no state file exists, do nothing
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse user message from hook input
USER_MESSAGE=$(echo "$HOOK_INPUT" | jq -r '.message // empty' 2>/dev/null || echo "")

# Exit if no message
if [[ -z "$USER_MESSAGE" ]]; then
  exit 0
fi

# Parse YAML frontmatter helper
parse_frontmatter() {
  local key="$1"
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep "^${key}:" | sed "s/${key}: *//" | sed 's/^"\(.*\)"$/\1/'
}

# Get current state
ACTIVE=$(parse_frontmatter "active")
CURRENT_PHASE=$(parse_frontmatter "current_phase")
USER_APPROVED=$(parse_frontmatter "user_approved_plan")

# Only process if workflow is active
if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Only check for approval if we're in Phase 0 and not yet approved
if [[ "$CURRENT_PHASE" != "0" ]] || [[ "$USER_APPROVED" == "true" ]]; then
  exit 0
fi

# Convert message to lowercase for comparison
USER_MESSAGE_LOWER=$(echo "$USER_MESSAGE" | tr '[:upper:]' '[:lower:]')

# Check if message contains approval keyword
if echo "$USER_MESSAGE_LOWER" | grep -qiE "\\b($APPROVAL_KEYWORDS)\\b"; then
  # Update state file to mark plan as approved
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  sed -e "s/^user_approved_plan: .*/user_approved_plan: true/" \
      -e "s/^approval_timestamp: .*/approval_timestamp: \"$TIMESTAMP\"/" \
      -e "s/^updated_at: .*/updated_at: \"$TIMESTAMP\"/" \
      "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true

  # Output advisory confirmation
  jq -n \
    --arg msg "Plan approval detected. Workflow will proceed to Phase 1." \
    '{
      "decision": "allow",
      "systemMessage": $msg
    }'
  exit 0
fi

# Default: allow with no message
exit 0
