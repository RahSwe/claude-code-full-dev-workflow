---
description: Explain Full Dev Workflow plugin and available commands
---

# Full Dev Workflow Plugin

A comprehensive feature development workflow with code mapping, TDD, multi-agent review, and PR management.

## Commands

| Command                                 | Description                                      |
| --------------------------------------- | ------------------------------------------------ |
| `/full-dev-workflow:full-dev <feature>` | Start the full development workflow              |
| `/full-dev-workflow:ralph <prompt>`     | Run autonomous development loop (used in Phase 3)|
| `/full-dev-workflow:resume`             | Resume an interrupted workflow                   |
| `/full-dev-workflow:help`               | Show this help message                           |

### Ralph Command Options

The native Ralph implementation includes advanced safety features:

```
/full-dev-workflow:ralph "<prompt>" [options]

Options:
  --completion-promise <signal>  Signal to detect completion (e.g., "ALL_TESTS_PASS")
  --max-iterations <n>           Maximum iterations (default: 30)
  --timeout <minutes>            Timeout per iteration (default: 60)
```

**Safety Features:**
- **Dual-condition exit**: Requires BOTH completion signal AND `EXIT_SIGNAL: true`
- **Circuit breaker**: Stops after 3 consecutive real errors
- **Rate limiting**: 100 API calls/hour (prevents runaway loops)
- **Session continuity**: Preserves context for 24 hours

## Workflow Phases

| Phase | Name                | Description                                        |
| ----- | ------------------- | -------------------------------------------------- |
| 0     | Plan Mode           | Create feature specification and get user approval |
| 1     | Code Mapping        | Explore codebase and identify affected files       |
| 2     | Test Creation       | Write E2E, integration, and unit tests (TDD)       |
| 3     | Ralph Loop          | Iterative implementation until tests pass          |
| 4     | Code Review         | Multi-agent review (5 perspectives)                |
| 5     | Auto Fixes          | Automatically fix high-confidence issues           |
| 6     | Code Simplification | Refactor for clarity and maintainability           |
| 7     | UI Verification     | Browser testing for UI features                    |
| 8     | Push PR             | Create well-documented pull request                |
| 9-10  | PR Review Loop      | Address feedback until approval                    |

## Bundled Agents

This plugin includes specialized agents for each phase:

- `full-dev-workflow:code-explorer` - Phase 1 code mapping
- `full-dev-workflow:test-architect` - Phase 2 test design
- `full-dev-workflow:reviewer-conventions` - Phase 4 convention compliance
- `full-dev-workflow:reviewer-bugs` - Phase 4 bug detection
- `full-dev-workflow:reviewer-quality` - Phase 4 code quality
- `full-dev-workflow:reviewer-security` - Phase 4 security review
- `full-dev-workflow:reviewer-performance` - Phase 4 performance review
- `full-dev-workflow:code-simplifier` - Phase 6 code simplification (uses Opus model)

## State Persistence

Workflow progress is saved to `.claude/full-dev.local.md`. If interrupted, use `/full-dev-workflow:resume` to continue.

## Dependencies

This plugin is fully self-contained with no external dependencies.

All components are built-in:
- **Ralph loop** (Phase 3) - Native implementation with dual-exit gate, circuit breaker, rate limiting
- **Code simplifier** (Phase 6) - Native agent using Opus model for intelligent refactoring

## Hooks

The plugin includes advisory hooks for:

- **Stop**: Warns when exiting mid-workflow
- **UserPromptSubmit**: Detects plan approval in Phase 0
- **PostToolUse**: Tracks modified files and test regressions

All hooks are advisory (never blocking).

## Quick Start

```
/full-dev-workflow:full-dev Add user authentication with OAuth support
```

This will:

1. Enter Plan Mode and explore the codebase
2. Create a feature specification
3. Wait for your approval
4. Execute phases 1-10 autonomously
