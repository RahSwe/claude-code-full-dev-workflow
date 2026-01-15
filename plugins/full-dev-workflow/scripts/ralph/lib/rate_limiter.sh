#!/usr/bin/env bash
# Rate Limiter Library for Ralph Loop
# Implements configurable API rate limiting

set -euo pipefail

# Rate limiter state file location
RATE_STATE_FILE="${RATE_STATE_FILE:-.claude/ralph-rate.state}"

# Default rate limit (calls per hour)
DEFAULT_RATE_LIMIT=100

# Initialize rate limiter state
init_rate_limiter() {
    local limit="${1:-$DEFAULT_RATE_LIMIT}"

    mkdir -p "$(dirname "$RATE_STATE_FILE")"
    cat > "$RATE_STATE_FILE" << EOF
calls_this_hour=0
hour_start=$(date +%s)
rate_limit=$limit
EOF
}

# Read current rate state
read_rate_state() {
    if [[ ! -f "$RATE_STATE_FILE" ]]; then
        init_rate_limiter
    fi
    source "$RATE_STATE_FILE"
}

# Write rate state
write_rate_state() {
    local calls="$1"
    local start="$2"
    local limit="$3"

    cat > "$RATE_STATE_FILE" << EOF
calls_this_hour=$calls
hour_start=$start
rate_limit=$limit
EOF
}

# Check if we're in a new hour and reset if needed
check_hour_reset() {
    read_rate_state

    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - hour_start))

    # If more than an hour has passed, reset
    if [[ "$elapsed" -ge 3600 ]]; then
        write_rate_state 0 "$current_time" "$rate_limit"
        return 0  # Reset occurred
    fi

    return 1  # No reset
}

# Record an API call
record_call() {
    check_hour_reset
    read_rate_state

    ((calls_this_hour++))
    write_rate_state "$calls_this_hour" "$hour_start" "$rate_limit"
}

# Check if rate limit reached
is_rate_limited() {
    check_hour_reset
    read_rate_state

    [[ "$calls_this_hour" -ge "$rate_limit" ]]
}

# Get remaining calls this hour
get_remaining_calls() {
    check_hour_reset
    read_rate_state

    local remaining=$((rate_limit - calls_this_hour))
    [[ "$remaining" -lt 0 ]] && remaining=0
    echo "$remaining"
}

# Get time until rate limit reset (in seconds)
get_reset_time() {
    read_rate_state

    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - hour_start))
    local remaining=$((3600 - elapsed))

    [[ "$remaining" -lt 0 ]] && remaining=0
    echo "$remaining"
}

# Get human-readable reset time
get_reset_time_human() {
    local seconds
    seconds=$(get_reset_time)

    local minutes=$((seconds / 60))
    local secs=$((seconds % 60))

    if [[ "$minutes" -gt 0 ]]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Wait for rate limit reset if needed
wait_for_rate_reset() {
    if ! is_rate_limited; then
        return 0  # Not rate limited
    fi

    local wait_time
    wait_time=$(get_reset_time)

    if [[ "$wait_time" -gt 0 ]]; then
        echo "Rate limit reached. Waiting $(get_reset_time_human) for reset..."
        sleep "$wait_time"
    fi

    # Reset after waiting
    init_rate_limiter "$rate_limit"
}

# Check rate limit and record call if allowed
# Returns 0 if call allowed, 1 if rate limited
try_call() {
    if is_rate_limited; then
        return 1  # Rate limited
    fi

    record_call
    return 0
}

# Set new rate limit
set_rate_limit() {
    local new_limit="$1"
    read_rate_state
    write_rate_state "$calls_this_hour" "$hour_start" "$new_limit"
}

# Get current rate limit
get_rate_limit() {
    read_rate_state
    echo "$rate_limit"
}

# Get current call count
get_call_count() {
    check_hour_reset
    read_rate_state
    echo "$calls_this_hour"
}

# Get rate limit status as JSON
get_rate_status() {
    check_hour_reset
    read_rate_state

    local remaining=$((rate_limit - calls_this_hour))
    [[ "$remaining" -lt 0 ]] && remaining=0

    local reset_time
    reset_time=$(get_reset_time)

    cat << EOF
{
    "calls_this_hour": $calls_this_hour,
    "rate_limit": $rate_limit,
    "remaining": $remaining,
    "reset_in_seconds": $reset_time,
    "is_limited": $(is_rate_limited && echo "true" || echo "false")
}
EOF
}
