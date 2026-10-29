# Changelog

All notable changes to the qlik-agents plugin will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-10-29

### Fixed
- Error-handling template: a critical error now fails the reload in Qlik Cloud instead of ending it as succeeded
- Age calculations use Age() instead of dividing days by 365.25, which runs a year short for many dates
- QVD guidance no longer states that a one-field Exists() keeps a QVD read optimized
- Row limits use the First N prefix instead of WHERE RowNo() <= N, which keeps one row too many after Order By
- Null-count pattern uses Count(1) instead of Count(*), which fails in a LOAD
- Set analysis: $1 is the previous selection, an empty set {} selects nothing, and Field= clears a selection
- Set analysis: $(=Max(Year)) follows the current selections, a field listed twice keeps only the last assignment, and exclusion uses -=
- Alt() is described as a numeric fallback, not a COALESCE()
- Section access: field names and values are converted to uppercase, so reduction fields must be uppercase in the data model
- TRACE messages no longer hold a semicolon or a lib:// path, which end the TRACE statement in the wrong place
- Security skill: a caution that its section access examples are incomplete, with what Qlik Cloud's Section Access page requires

## [0.1.0] - 2026-03-13

### Added
- 8 specialized agents: orchestrator, requirements-analyst, data-architect, script-developer, expression-developer, viz-architect, qa-reviewer, doc-writer
- 14 skills covering data modeling, load script, expressions, naming conventions, security, performance, visualization, deployment, QA review, source profiling, platform conventions, project scaffolding, data quality validation, and Qlik Cloud MCP integration
- PostToolUse hook for QVS syntax validation on Write/Edit operations
- 4 QVS script templates (master calendar, error handling, incremental load, null cleanup)
- Progressive disclosure pattern: SKILL.md entry points with supporting reference files

### Fixed
- plugin.json repository field format for manifest validation
- Skill name mismatch in qlik-review-checklist (kebab-case compliance)
- YAML block scalar descriptions normalized to quoted strings
