# Changelog

All notable changes to the qlik-agents plugin will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
