# Full Dev Workflow Plugin Marketplace

A Claude Code plugin marketplace providing comprehensive feature development workflows.

## Installation

### Add the Marketplace

```bash
/plugin marketplace add RahSwe/claude-code-full-dev-workflow
```

### Install the Plugin

```bash
/plugin install full-dev-workflow@full-dev-workflow-marketplace
```

## Available Plugins

### full-dev-workflow

Complete feature development workflow with 10 phases from planning to PR merge.

**Features:**

- Phase 0: Plan Mode - Feature specification with user approval
- Phase 1: Code Mapping - Explore codebase and identify affected files
- Phase 2: Test Creation - TDD with E2E, integration, and unit tests
- Phase 3: Ralph Loop - Iterative implementation until tests pass
- Phase 4: Multi-Agent Code Review - 5 specialized review perspectives
- Phase 5: Automatic Fixes - Fix high-confidence issues automatically
- Phase 6: Code Simplification - Refactor for clarity and maintainability
- Phase 7: UI Verification - Browser testing for UI features
- Phase 8: Push PR - Create well-documented pull request
- Phase 9-10: PR Review Loop - Address feedback until approval

**Bundled Agents:**

- `full-dev-workflow:code-explorer` - Phase 1 code mapping
- `full-dev-workflow:test-architect` - Phase 2 test design
- `full-dev-workflow:reviewer-conventions` - Phase 4 convention compliance
- `full-dev-workflow:reviewer-bugs` - Phase 4 bug detection
- `full-dev-workflow:reviewer-quality` - Phase 4 code quality
- `full-dev-workflow:reviewer-security` - Phase 4 security review
- `full-dev-workflow:reviewer-performance` - Phase 4 performance review

**Advisory Hooks:**

- Stop hook - Warns when exiting mid-workflow
- User prompt hook - Detects plan approval in Phase 0
- Post tool hook - Tracks modified files and test regressions

**Commands:**

- `/full-dev-workflow:full-dev <feature>` - Start the workflow
- `/full-dev-workflow:resume` - Resume interrupted workflow
- `/full-dev-workflow:help` - Show help

## Dependencies

This plugin works best with:

- [ralph-loop](https://github.com/RahSwe/claude-code-ralph-loop) - For Phase 3 iterative development
- [code-simplifier](https://github.com/RahSwe/claude-code-code-simplifier) - For Phase 6 code cleanup

And automatic code review in GitHub on published PR's and changes (Claude Code Review, CodeRabbit, Greptile etc)

## Quick Start

```bash
/full-dev-workflow:full-dev Add user authentication with OAuth support
```

## License

MIT
