#!/bin/bash
# Full-Dev Workflow Stop Hook
# Provides advisory warnings when exiting mid-workflow
# Always allows exit (advisory mode) but shows helpful messages

set -euo pipefail

# State file location
STATE_FILE=".claude/full-dev.local.md"

# Phase names for human-readable messages
declare -A PHASE_NAMES=(
  [0]="Plan Mode"
  [1]="Code Mapping"
  [2]="Test Creation"
  [3]="Ralph Loop Implementation"
  [4]="Multi-Agent Code Review"
  [5]="Automatic Fixes"
  [6]="Code Simplification"
  [7]="UI Verification"
  [8]="Push PR"
  [9]="PR Review Loop"
  [10]="PR Review Loop"
)

# Critical phases that warrant stronger warnings
CRITICAL_PHASES=(3 5 9 10)

# Read hook input from stdin
HOOK_INPUT=$(cat)

# If no state file exists, allow exit silently
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse YAML frontmatter
parse_frontmatter() {
  local key="$1"
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep "^${key}:" | sed "s/${key}: *//" | sed 's/^"\(.*\)"$/\1/'
}

# Get current state
ACTIVE=$(parse_frontmatter "active")
CURRENT_PHASE=$(parse_frontmatter "current_phase")
FEATURE=$(parse_frontmatter "feature")
COMPLETED_PHASES=$(parse_frontmatter "completed_phases")

# If workflow is not active, allow exit silently
if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Validate current_phase is numeric
if [[ ! "$CURRENT_PHASE" =~ ^[0-9]+$ ]]; then
  # Invalid state, allow exit
  exit 0
fi

# Get phase name
PHASE_NAME="${PHASE_NAMES[$CURRENT_PHASE]:-Phase $CURRENT_PHASE}"

# Update timestamp before exit
TEMP_FILE="${STATE_FILE}.tmp.$$"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sed "s/^updated_at: .*/updated_at: \"$TIMESTAMP\"/" "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" || true

# Check if current phase is critical
IS_CRITICAL=false
for phase in "${CRITICAL_PHASES[@]}"; do
  if [[ "$CURRENT_PHASE" -eq "$phase" ]]; then
    IS_CRITICAL=true
    break
  fi
done

# Build advisory message
if [[ "$IS_CRITICAL" == "true" ]]; then
  WARNING_LEVEL="CRITICAL"
else
  WARNING_LEVEL="INFO"
fi

# Create system message
SYSTEM_MSG="[$WARNING_LEVEL] Full-dev workflow '${FEATURE}' - Phase $CURRENT_PHASE ($PHASE_NAME) incomplete. Progress saved to $STATE_FILE. Use /full-dev-workflow:resume to continue."

# Output advisory message (always allow exit)
jq -n \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "allow",
    "systemMessage": $msg
  }'

exit 0
