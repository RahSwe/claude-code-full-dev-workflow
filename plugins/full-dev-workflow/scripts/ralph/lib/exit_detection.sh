#!/usr/bin/env bash
# Exit Detection Library for Ralph Loop
# Implements dual-condition exit gate based on frankbria/ralph-claude-code

set -euo pipefail

# Default completion signals that indicate work might be done
DEFAULT_COMPLETION_SIGNALS=(
    "ALL_TESTS_PASS"
    "TASK_COMPLETE"
    "DONE"
    "FINISHED"
    "COMPLETED"
    "SUCCESS"
)

# Check if output contains completion signals
# Returns count of signals found
count_completion_signals() {
    local output="$1"
    local custom_signal="${2:-}"
    local count=0

    # Check custom completion promise first (highest priority)
    if [[ -n "$custom_signal" ]] && grep -qF "$custom_signal" <<< "$output"; then
        ((count++))
    fi

    # Check default signals
    for signal in "${DEFAULT_COMPLETION_SIGNALS[@]}"; do
        if grep -qiF "$signal" <<< "$output"; then
            ((count++))
        fi
    done

    echo "$count"
}

# Check for explicit EXIT_SIGNAL in output
# This is the second condition for the dual-gate
check_exit_signal() {
    local output="$1"

    # Look for explicit exit signals in various formats
    if grep -qE 'EXIT_SIGNAL:\s*(true|yes|1)' <<< "$output"; then
        return 0
    fi

    if grep -qE '<exit[_-]?signal>\s*(true|yes|1)\s*</exit[_-]?signal>' <<< "$output"; then
        return 0
    fi

    if grep -qE '"exit_signal":\s*(true|"true")' <<< "$output"; then
        return 0
    fi

    return 1
}

# Main dual-condition exit check
# Returns 0 if should exit, 1 if should continue
should_exit() {
    local output="$1"
    local completion_promise="${2:-}"
    local require_exit_signal="${3:-true}"
    local min_signals="${4:-1}"

    local signal_count
    signal_count=$(count_completion_signals "$output" "$completion_promise")

    # Check if we have enough completion signals
    if [[ "$signal_count" -lt "$min_signals" ]]; then
        return 1  # Not enough signals, continue
    fi

    # If exit signal required, check for it
    if [[ "$require_exit_signal" == "true" ]]; then
        if check_exit_signal "$output"; then
            return 0  # Both conditions met, exit
        else
            return 1  # Missing exit signal, continue
        fi
    fi

    # Exit signal not required, completion signals are enough
    return 0
}

# Check for explicit continuation signals
# These override exit conditions
check_continuation_signals() {
    local output="$1"

    # Look for explicit "keep going" signals
    if grep -qiE 'CONTINUE_LOOP|KEEP_GOING|NOT_DONE|MORE_WORK' <<< "$output"; then
        return 0  # Should continue
    fi

    # Check for work-in-progress indicators
    if grep -qiE 'IN_PROGRESS|WORKING_ON|IMPLEMENTING' <<< "$output"; then
        return 0  # Should continue
    fi

    return 1  # No continuation signals
}

# Comprehensive exit decision
# Considers both exit and continuation signals
decide_exit() {
    local output="$1"
    local completion_promise="${2:-}"
    local require_exit_signal="${3:-true}"

    # First check for explicit continuation - this overrides everything
    if check_continuation_signals "$output"; then
        echo "continue"
        return 1
    fi

    # Then check exit conditions
    if should_exit "$output" "$completion_promise" "$require_exit_signal"; then
        echo "exit"
        return 0
    fi

    echo "continue"
    return 1
}
