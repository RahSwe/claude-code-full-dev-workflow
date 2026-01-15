#!/usr/bin/env bash
# Ralph Loop - Autonomous AI Development Loop
# Based on frankbria/ralph-claude-code implementation
# Integrated as native component of full-dev-workflow plugin

set -euo pipefail

# Get script directory for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "$SCRIPT_DIR/lib/exit_detection.sh"
source "$SCRIPT_DIR/lib/circuit_breaker.sh"
source "$SCRIPT_DIR/lib/rate_limiter.sh"
source "$SCRIPT_DIR/lib/session.sh"

# Default configuration
DEFAULT_MAX_ITERATIONS=30
DEFAULT_TIMEOUT_MINUTES=60
DEFAULT_RATE_LIMIT=100
DEFAULT_CIRCUIT_THRESHOLD=3
DEFAULT_SESSION_EXPIRY=24

# Parse command line arguments
parse_args() {
    PROMPT=""
    COMPLETION_PROMISE=""
    MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"
    TIMEOUT_MINUTES="$DEFAULT_TIMEOUT_MINUTES"
    RATE_LIMIT="$DEFAULT_RATE_LIMIT"
    CIRCUIT_THRESHOLD="$DEFAULT_CIRCUIT_THRESHOLD"
    SESSION_EXPIRY="$DEFAULT_SESSION_EXPIRY"
    REQUIRE_EXIT_SIGNAL="true"
    JSON_OUTPUT="true"
    VERBOSE="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --completion-promise)
                COMPLETION_PROMISE="$2"
                shift 2
                ;;
            --max-iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_MINUTES="$2"
                shift 2
                ;;
            --rate-limit)
                RATE_LIMIT="$2"
                shift 2
                ;;
            --circuit-threshold)
                CIRCUIT_THRESHOLD="$2"
                shift 2
                ;;
            --session-expiry)
                SESSION_EXPIRY="$2"
                shift 2
                ;;
            --no-exit-signal)
                REQUIRE_EXIT_SIGNAL="false"
                shift
                ;;
            --text-output)
                JSON_OUTPUT="false"
                shift
                ;;
            --verbose|-v)
                VERBOSE="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                PROMPT="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$PROMPT" ]]; then
        echo "Error: Prompt is required" >&2
        show_help
        exit 1
    fi
}

show_help() {
    cat << 'EOF'
Ralph Loop - Autonomous AI Development Loop

Usage: ralph_loop.sh "<prompt>" [options]

Options:
    --completion-promise <signal>  Signal to detect completion (e.g., "ALL_TESTS_PASS")
    --max-iterations <n>           Maximum iterations before stopping (default: 30)
    --timeout <minutes>            Timeout per iteration in minutes (default: 60)
    --rate-limit <n>               API calls per hour limit (default: 100)
    --circuit-threshold <n>        Consecutive errors before circuit trips (default: 3)
    --session-expiry <hours>       Session context retention hours (default: 24)
    --no-exit-signal               Don't require EXIT_SIGNAL for completion
    --text-output                  Use text output instead of JSON
    --verbose, -v                  Enable verbose output
    --help, -h                     Show this help message

Exit Conditions:
    - Completion promise detected AND EXIT_SIGNAL: true (dual-gate)
    - Max iterations reached
    - Circuit breaker tripped (consecutive errors)
    - Rate limit exceeded
    - Timeout exceeded
    - Manual interrupt (Ctrl+C)

Examples:
    ralph_loop.sh "Implement feature X" --completion-promise "ALL_TESTS_PASS"
    ralph_loop.sh "Fix bug Y" --max-iterations 10 --timeout 30
EOF
}

log() {
    local level="$1"
    local message="$2"

    if [[ "$VERBOSE" == "true" ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "INFO" ]]; then
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [$level] $message" >&2
    fi
}

# Initialize all subsystems
initialize() {
    log "DEBUG" "Initializing Ralph Loop..."

    # Initialize session
    SESSION_ID=$(resume_or_start_session "$SESSION_EXPIRY" "$PROMPT" "$COMPLETION_PROMISE")
    log "INFO" "Session: $SESSION_ID"

    # Initialize rate limiter
    init_rate_limiter "$RATE_LIMIT"
    log "DEBUG" "Rate limiter initialized: $RATE_LIMIT calls/hour"

    # Initialize circuit breaker
    init_circuit_breaker "$CIRCUIT_THRESHOLD"
    log "DEBUG" "Circuit breaker initialized: threshold=$CIRCUIT_THRESHOLD"
}

# Run a single iteration
run_iteration() {
    local iteration="$1"
    local timeout_seconds=$((TIMEOUT_MINUTES * 60))

    log "INFO" "Starting iteration $iteration/$MAX_ITERATIONS"

    # Check rate limit
    if ! try_call; then
        local remaining
        remaining=$(get_reset_time_human)
        log "ERROR" "Rate limit reached. Reset in: $remaining"
        return 3  # Rate limited
    fi

    # Build Claude Code command
    local claude_args=()
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        claude_args+=(--output-format json)
    fi
    claude_args+=(--print)

    # Create iteration prompt
    local iteration_prompt="$PROMPT

Iteration: $iteration/$MAX_ITERATIONS

IMPORTANT: When the task is complete:
1. Include completion signal: $COMPLETION_PROMISE
2. Include EXIT_SIGNAL: true

If the task is NOT complete, continue working and do NOT include EXIT_SIGNAL."

    # Run Claude Code with timeout
    local output
    local exit_code=0

    if command -v timeout &> /dev/null; then
        output=$(timeout "$timeout_seconds" claude "${claude_args[@]}" "$iteration_prompt" 2>&1) || exit_code=$?
    else
        # macOS doesn't have timeout by default, use perl
        output=$(perl -e 'alarm shift; exec @ARGV' "$timeout_seconds" claude "${claude_args[@]}" "$iteration_prompt" 2>&1) || exit_code=$?
    fi

    # Handle timeout
    if [[ "$exit_code" -eq 124 ]] || [[ "$exit_code" -eq 142 ]]; then
        log "ERROR" "Iteration timed out after $TIMEOUT_MINUTES minutes"
        return 4  # Timeout
    fi

    # Store output for analysis
    LAST_OUTPUT="$output"

    # Process through circuit breaker
    local circuit_result
    circuit_result=$(process_iteration "$output" "${PREVIOUS_OUTPUT:-}")
    PREVIOUS_OUTPUT="$output"

    case "$circuit_result" in
        0)
            log "DEBUG" "Iteration completed successfully"
            ;;
        1)
            log "WARN" "Error detected in iteration"
            ;;
        2)
            log "ERROR" "Circuit breaker tripped"
            return 2  # Circuit tripped
            ;;
    esac

    # Check exit conditions
    if decide_exit "$output" "$COMPLETION_PROMISE" "$REQUIRE_EXIT_SIGNAL" > /dev/null; then
        log "INFO" "Exit conditions met"
        return 0  # Success - should exit
    fi

    return 1  # Continue - no exit conditions met
}

# Main loop
main() {
    parse_args "$@"
    initialize

    local iteration=0
    local start_time
    start_time=$(date +%s)

    # Trap for cleanup
    trap 'end_session "interrupted"; exit 130' INT TERM

    log "INFO" "Starting Ralph Loop"
    log "INFO" "Prompt: $PROMPT"
    log "INFO" "Completion Promise: ${COMPLETION_PROMISE:-<none>}"
    log "INFO" "Max Iterations: $MAX_ITERATIONS"

    while [[ "$iteration" -lt "$MAX_ITERATIONS" ]]; do
        ((iteration++))

        # Check session validity
        if ! is_session_active; then
            log "ERROR" "Session expired"
            end_session "session_expired"
            exit 5
        fi

        # Run iteration
        local result=0
        run_iteration "$iteration" || result=$?

        # Update session
        update_session "$iteration"

        case "$result" in
            0)
                # Success - exit conditions met
                log "INFO" "Loop completed successfully after $iteration iterations"
                end_session "completed"

                # Output final result
                if [[ -n "${LAST_OUTPUT:-}" ]]; then
                    echo "$LAST_OUTPUT"
                fi
                exit 0
                ;;
            1)
                # Continue - no exit conditions
                log "DEBUG" "Continuing to next iteration"
                ;;
            2)
                # Circuit breaker tripped
                log "ERROR" "Circuit breaker tripped after $iteration iterations"
                end_session "circuit_tripped"
                exit 2
                ;;
            3)
                # Rate limited
                log "WARN" "Rate limited, waiting for reset..."
                wait_for_rate_reset
                ((iteration--))  # Don't count this iteration
                ;;
            4)
                # Timeout
                log "WARN" "Iteration timed out, continuing..."
                ;;
            *)
                log "ERROR" "Unknown error in iteration"
                ;;
        esac
    done

    # Max iterations reached
    log "WARN" "Max iterations ($MAX_ITERATIONS) reached without completion"
    end_session "max_iterations"

    if [[ -n "${LAST_OUTPUT:-}" ]]; then
        echo "$LAST_OUTPUT"
    fi
    exit 1
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
