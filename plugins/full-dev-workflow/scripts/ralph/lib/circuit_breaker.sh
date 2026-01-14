#!/usr/bin/env bash
# Circuit Breaker Library for Ralph Loop
# Implements two-stage error filtering based on frankbria/ralph-claude-code

set -euo pipefail

# Circuit breaker state file location
CIRCUIT_STATE_FILE="${CIRCUIT_STATE_FILE:-.claude/ralph-circuit.state}"

# Default threshold before circuit trips
DEFAULT_THRESHOLD=3

# Initialize circuit breaker state
init_circuit_breaker() {
    local threshold="${1:-$DEFAULT_THRESHOLD}"

    mkdir -p "$(dirname "$CIRCUIT_STATE_FILE")"
    cat > "$CIRCUIT_STATE_FILE" << EOF
consecutive_errors=0
threshold=$threshold
tripped=false
last_error=""
last_error_time=""
EOF
}

# Read current circuit state
read_circuit_state() {
    if [[ ! -f "$CIRCUIT_STATE_FILE" ]]; then
        init_circuit_breaker
    fi
    source "$CIRCUIT_STATE_FILE"
}

# Write circuit state
write_circuit_state() {
    local errors="$1"
    local threshold="$2"
    local tripped="$3"
    local last_error="$4"

    cat > "$CIRCUIT_STATE_FILE" << EOF
consecutive_errors=$errors
threshold=$threshold
tripped=$tripped
last_error="$last_error"
last_error_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
}

# Stage 1: Filter false positives
# JSON responses often contain "error": null or similar
is_false_positive() {
    local output="$1"

    # JSON null error fields are not real errors
    if echo "$output" | grep -qE '"error":\s*null' 2>/dev/null; then
        return 0  # Is false positive
    fi

    # Empty error strings
    if echo "$output" | grep -qE '"error":\s*""' 2>/dev/null; then
        return 0
    fi

    # Success responses that happen to mention "error"
    if echo "$output" | grep -qE '"success":\s*true' 2>/dev/null && \
       echo "$output" | grep -qE '"error"' 2>/dev/null; then
        return 0
    fi

    # Error in variable names or comments
    if echo "$output" | grep -qE 'error_handler|error_code|on_error|catch_error' 2>/dev/null; then
        return 0
    fi

    return 1  # Not a false positive
}

# Stage 2: Semantic error detection
# Look for actual error patterns
is_real_error() {
    local output="$1"

    # First filter false positives
    if is_false_positive "$output"; then
        return 1  # Not a real error
    fi

    # Check for actual error patterns
    local error_patterns=(
        '^Error:'
        '^ERROR:'
        'FATAL:'
        'Exception:'
        'Traceback \(most recent call last\)'
        'SyntaxError:'
        'TypeError:'
        'ReferenceError:'
        'RuntimeError:'
        'ENOENT:'
        'EACCES:'
        'command not found'
        'No such file or directory'
        'Permission denied'
        'failed with exit code'
        'npm ERR!'
        'error: '
    )

    for pattern in "${error_patterns[@]}"; do
        if echo "$output" | grep -qE "$pattern" 2>/dev/null; then
            return 0  # Is a real error
        fi
    done

    return 1  # Not a real error
}

# Check for stuck loop patterns
is_stuck_loop() {
    local output="$1"
    local previous_output="${2:-}"

    # If outputs are identical, might be stuck
    if [[ -n "$previous_output" ]] && [[ "$output" == "$previous_output" ]]; then
        return 0  # Stuck
    fi

    # Check for repetitive failure patterns
    if echo "$output" | grep -qE 'same error|trying again|retrying|attempt [0-9]+ failed' 2>/dev/null; then
        return 0
    fi

    return 1
}

# Record an error and check if circuit should trip
record_error() {
    local error_msg="$1"

    read_circuit_state

    ((consecutive_errors++))

    if [[ "$consecutive_errors" -ge "$threshold" ]]; then
        write_circuit_state "$consecutive_errors" "$threshold" "true" "$error_msg"
        return 0  # Circuit tripped
    fi

    write_circuit_state "$consecutive_errors" "$threshold" "false" "$error_msg"
    return 1  # Circuit not tripped
}

# Record success - resets error counter
record_success() {
    read_circuit_state
    write_circuit_state 0 "$threshold" "false" ""
}

# Check if circuit is tripped
is_circuit_tripped() {
    read_circuit_state
    [[ "$tripped" == "true" ]]
}

# Get current error count
get_error_count() {
    read_circuit_state
    echo "$consecutive_errors"
}

# Reset circuit breaker
reset_circuit() {
    local threshold="${1:-$DEFAULT_THRESHOLD}"
    init_circuit_breaker "$threshold"
}

# Main error check function
# Returns 0 if real error detected, 1 otherwise
check_for_error() {
    local output="$1"
    local previous_output="${2:-}"

    # Stage 1: Filter false positives
    if is_false_positive "$output"; then
        return 1
    fi

    # Stage 2: Check for real errors
    if is_real_error "$output"; then
        return 0
    fi

    # Check for stuck loops
    if is_stuck_loop "$output" "$previous_output"; then
        return 0
    fi

    return 1
}

# Process iteration output
# Returns: 0 = continue, 1 = error (may trip circuit), 2 = circuit tripped
process_iteration() {
    local output="$1"
    local previous_output="${2:-}"

    if check_for_error "$output" "$previous_output"; then
        # Extract error message for logging
        local error_msg
        error_msg=$(echo "$output" | grep -E '^Error:|^ERROR:|FATAL:|Exception:' | head -1)
        [[ -z "$error_msg" ]] && error_msg="Unknown error detected"

        if record_error "$error_msg"; then
            return 2  # Circuit tripped
        fi
        return 1  # Error but circuit not tripped
    fi

    # No error - record success
    record_success
    return 0
}
