#!/usr/bin/env bash
# Session Management Library for Ralph Loop
# Implements session continuity with configurable expiration

set -euo pipefail

# Session state file location
SESSION_STATE_FILE="${SESSION_STATE_FILE:-.claude/ralph-session.state}"

# Default session expiry (hours)
DEFAULT_SESSION_EXPIRY=24

# Initialize a new session
init_session() {
    local expiry_hours="${1:-$DEFAULT_SESSION_EXPIRY}"
    local prompt="${2:-}"
    local completion_promise="${3:-}"

    mkdir -p "$(dirname "$SESSION_STATE_FILE")"

    local session_id
    session_id=$(date +%s)-$$-$RANDOM

    local start_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local expiry_seconds=$((expiry_hours * 3600))
    local expiry_timestamp=$(($(date +%s) + expiry_seconds))

    cat > "$SESSION_STATE_FILE" << EOF
session_id="$session_id"
started_at="$start_time"
expiry_timestamp=$expiry_timestamp
expiry_hours=$expiry_hours
iteration_count=0
last_iteration=""
prompt="$prompt"
completion_promise="$completion_promise"
status="active"
exit_reason=""
EOF

    echo "$session_id"
}

# Read session state
read_session() {
    if [[ ! -f "$SESSION_STATE_FILE" ]]; then
        return 1
    fi
    source "$SESSION_STATE_FILE"
    return 0
}

# Check if session exists and is valid
session_exists() {
    [[ -f "$SESSION_STATE_FILE" ]]
}

# Check if session has expired
is_session_expired() {
    if ! read_session; then
        return 0  # No session = expired
    fi

    local current_time
    current_time=$(date +%s)

    [[ "$current_time" -ge "$expiry_timestamp" ]]
}

# Check if session is active
is_session_active() {
    if ! read_session; then
        return 1
    fi

    # Check expiration
    if is_session_expired; then
        return 1
    fi

    # Check status
    [[ "$status" == "active" ]]
}

# Update session after iteration
update_session() {
    local new_iteration_count="$1"
    local last_output="${2:-}"

    if ! read_session; then
        return 1
    fi

    local update_time
    update_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$SESSION_STATE_FILE" << EOF
session_id="$session_id"
started_at="$started_at"
expiry_timestamp=$expiry_timestamp
expiry_hours=$expiry_hours
iteration_count=$new_iteration_count
last_iteration="$update_time"
prompt="$prompt"
completion_promise="$completion_promise"
status="active"
exit_reason=""
EOF
}

# End session with reason
end_session() {
    local reason="$1"

    if ! read_session; then
        return 1
    fi

    local end_time
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$SESSION_STATE_FILE" << EOF
session_id="$session_id"
started_at="$started_at"
ended_at="$end_time"
expiry_timestamp=$expiry_timestamp
expiry_hours=$expiry_hours
iteration_count=$iteration_count
last_iteration="$last_iteration"
prompt="$prompt"
completion_promise="$completion_promise"
status="ended"
exit_reason="$reason"
EOF
}

# Get session ID
get_session_id() {
    if ! read_session; then
        echo ""
        return 1
    fi
    echo "$session_id"
}

# Get iteration count
get_iteration_count() {
    if ! read_session; then
        echo "0"
        return 1
    fi
    echo "$iteration_count"
}

# Increment iteration count
increment_iteration() {
    if ! read_session; then
        return 1
    fi

    local new_count=$((iteration_count + 1))
    update_session "$new_count"
    echo "$new_count"
}

# Get time remaining in session (seconds)
get_session_remaining() {
    if ! read_session; then
        echo "0"
        return 1
    fi

    local current_time
    current_time=$(date +%s)
    local remaining=$((expiry_timestamp - current_time))

    [[ "$remaining" -lt 0 ]] && remaining=0
    echo "$remaining"
}

# Get human-readable time remaining
get_session_remaining_human() {
    local seconds
    seconds=$(get_session_remaining)

    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))

    if [[ "$hours" -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Reset session (for circuit breaker trips, manual interrupts)
reset_session() {
    local reason="${1:-manual_reset}"

    if session_exists; then
        end_session "$reason"
    fi

    rm -f "$SESSION_STATE_FILE"
}

# Get session status as JSON
get_session_status() {
    if ! read_session; then
        echo '{"exists": false}'
        return
    fi

    local remaining
    remaining=$(get_session_remaining)

    local is_expired="false"
    is_session_expired && is_expired="true"

    local is_active="false"
    is_session_active && is_active="true"

    cat << EOF
{
    "session_id": "$session_id",
    "started_at": "$started_at",
    "iteration_count": $iteration_count,
    "status": "$status",
    "is_active": $is_active,
    "is_expired": $is_expired,
    "remaining_seconds": $remaining,
    "exit_reason": "$exit_reason"
}
EOF
}

# Resume existing session or start new one
resume_or_start_session() {
    local expiry_hours="${1:-$DEFAULT_SESSION_EXPIRY}"
    local prompt="${2:-}"
    local completion_promise="${3:-}"

    if is_session_active; then
        # Resume existing session
        get_session_id
    else
        # Start new session
        if session_exists; then
            reset_session "expired"
        fi
        init_session "$expiry_hours" "$prompt" "$completion_promise"
    fi
}
