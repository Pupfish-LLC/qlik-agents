# qlik-dev

AI-powered multi-agent development pipeline for Qlik Sense. Produces production-grade load scripts, expressions, visualization specifications, and documentation through a coordinated 9-phase pipeline of specialized Claude agents.

## What It Does

- **End-to-end Qlik Sense development** from requirements through documentation
- **Brownfield-first** — captures existing platform conventions before writing anything new
- **Quality gates** at each phase with static QA review and execution validation
- **MCP-optional** — works with or without the Qlik Cloud MCP server
- **Syntax validation** via PostToolUse hook that catches SQL-in-LOAD errors before execution

## Prerequisites

- Claude Code with agent support
- A Qlik development project directory
- (Optional) Qlik Cloud MCP server for live app interaction

## Installation

Install via Claude Code:

```bash
claude plugin install pupfish/qlik-dev
```

## Quick Start

1. Create a project directory and navigate to it
2. Run the scaffold skill to initialize the project structure:
   ```
   /qlik-dev:qlik-project-scaffold
   ```
3. Place source materials in `inputs/` subdirectories
4. The orchestrator agent starts automatically. Begin at Phase 0.

## 9-Phase Pipeline

| Phase | Description | Agent | Key Gate |
|-------|-------------|-------|----------|
| 0 | Platform Context | requirements-analyst | User confirms context |
| 1 | Requirements | requirements-analyst | **User approval required** |
| 2 | Source Profiling | requirements-analyst | Profile completeness |
| 3 | Data Architecture | data-architect | Lightweight QA review |
| 4 | Script Development | script-developer | QA + **execution validation** |
| 5 | Expression Authoring | expression-developer | QA + **execution validation** |
| 6 | Visualization Design | viz-architect | QA review of viz specs |
| 7 | Comprehensive QA | qa-reviewer | **All Critical findings resolved** |
| 8 | Documentation | doc-writer | Completeness check |

Pipeline state is tracked in `.pipeline-state.json`. Blocked dependencies do not halt the pipeline — placeholders are documented and tracked for resolution.

## Agent Inventory

| Agent | Role | Permission Mode |
|-------|------|----------------|
| orchestrator | Pipeline coordinator — manages all phases, gates, and rework loops | default |
| requirements-analyst | Platform context capture + requirements + source profiling | acceptEdits |
| data-architect | Star schema design, ETL layers, QVD strategy, field mapping matrix | acceptEdits |
| script-developer | Production .qvs load scripts with incremental load, diagnostics | acceptEdits |
| expression-developer | Set analysis expressions, aggregations, master item definitions | acceptEdits |
| viz-architect | Sheet layouts, chart selection, filter design, build checklists | acceptEdits |
| qa-reviewer | Four-pass QA review (data model, script, expression, comprehensive) | plan |
| doc-writer | Data dictionary, technical spec, user guide, runbook | acceptEdits |

## Skill Inventory

| Skill | Purpose |
|-------|---------|
| platform-conventions | Brownfield platform pattern capture (naming, connections, subroutines) |
| source-profiler | Source schema profiling with architecture classification |
| qlik-naming-conventions | Entity-prefix dot notation, key fields, cross-layer mapping rules |
| qlik-data-modeling | Star schema patterns, synthetic key prevention, QVD layer design |
| qlik-load-script | Script syntax, incremental patterns, null handling, diagnostics |
| qlik-expressions | Set analysis, aggregations, TOTAL qualifier, expression performance |
| qlik-performance | Memory optimization, QVD load optimization, calculation conditions |
| qlik-visualization | Chart selection framework, layout patterns, responsive design |
| qlik-security | Section access, row-level security, OMIT fields, Cloud vs. managed |
| qlik-review-checklist | Comprehensive QA checklist for all artifact types |
| data-quality-validator | Post-load null rate, duplicate, referential integrity checks |
| qlik-cloud-mcp | MCP tool mapping, workflow patterns, behavioral gotchas |
| qlik-deploy | Deployment procedures for Cloud and client-managed environments |
| qlik-project-scaffold | Project directory initialization (run once per project) |

## MCP Integration (Optional)

When the Qlik Cloud MCP server is available, agents use it for:
- **Phase 0:** Live reference app analysis
- **Phase 5:** Expression validation against loaded data
- **Phase 6:** Sheet and master item scaffolding
- **Phase 7:** Live data quality validation

Set `mcpAvailable.qlikCloud` in `.pipeline-state.json` at session start. The framework falls back to manual workflows when MCP is unavailable.

## Quality Gates Model

The pipeline enforces two types of gates:

**Approval gates** (human decision required):
- Phase 1: User must approve the Project Specification before architecture begins
- Phase 7: All Critical QA findings must be resolved before documentation

**Execution validation gates** (reload + inspect required):
- Phase 4: Successful Qlik reload + no synthetic keys confirmed
- Phase 5: Key expressions evaluated correctly against loaded data

## Author & License

**Author:** Pupfish, LLC — [pupfish.com](https://pupfish.com)
**Repository:** [github.com/pupfish/qlik-dev](https://github.com/pupfish/qlik-dev)
**License:** Proprietary — see [LICENSE](LICENSE)
