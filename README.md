# qlik-dev

A Claude Code plugin that runs a multi-agent development pipeline for Qlik Sense. You provide source materials and requirements. The pipeline produces production-grade load scripts, expressions, visualization specifications, QA reports, and documentation through a structured 9-phase workflow.

## What You Get

The pipeline produces artifacts organized by phase, written to an `artifacts/` directory in your project:

- **Platform context document** capturing existing conventions, naming patterns, and reusable components from your environment
- **Project specification** with scope, source-to-target mappings, and acceptance criteria
- **Source profile report** documenting schema structures, data types, volumes, and quality observations
- **Data model specification** with star schema design, QVD layer strategy, and field mapping matrix
- **Production load scripts** (.qvs) with incremental load logic, null handling, error trapping, and diagnostics
- **Expression catalog** with set analysis expressions, aggregations, and a variables include file
- **Visualization specifications** with sheet layouts, chart definitions, master item definitions, and a manual build checklist
- **Comprehensive QA report** covering data model, scripts, expressions, and cross-artifact consistency
- **Documentation package** including data dictionary, technical spec, user guide, and runbook

## Prerequisites

- Claude Code with agent support
- A working directory for your Qlik project
- Source materials: connection specs, data dictionaries, existing QVF exports, or platform documentation
- (Optional) Qlik Cloud MCP server for live app interaction during expression validation and visualization scaffolding

## Installation

```bash
claude plugin install Pupfish-LLC/qlik-dev
```

## Getting Started

1. Create a project directory and open it in Claude Code.

2. Run the scaffold command to set up the directory structure:
   ```
   /qlik-dev:qlik-project-scaffold
   ```
   This creates `inputs/` subdirectories for your source materials and `artifacts/` directories where the pipeline writes its output.

3. Place your source materials in the appropriate `inputs/` subdirectories:
   - `inputs/source-documentation/` — connection specs, data dictionaries, platform docs
   - `inputs/existing-apps/` — QVF exports, load scripts from brownfield apps
   - `inputs/platform-libraries/` — shared includes, naming conventions, reference implementations
   - `inputs/upstream-architecture/` — ER diagrams, data lineage, ETL architecture

4. Start the pipeline. The orchestrator picks up from wherever you left off, or begins at Phase 0 for new projects.

## How the Pipeline Works

The pipeline runs nine phases sequentially. You don't need to manage agents or phases manually. The orchestrator handles routing, context passing, and handoffs. Your role is to provide input, approve key decisions, and run execution validation when prompted.

| Phase | What Happens |
|-------|-------------|
| 0 | Captures your existing platform conventions, naming patterns, and reusable components |
| 1 | Builds a project specification through conversation with you |
| 2 | Profiles source system schemas, data types, and volumes |
| 3 | Designs the star schema data model, QVD layers, and field mappings |
| 4 | Generates production load scripts with incremental logic and diagnostics |
| 5 | Authors set analysis expressions, aggregations, and variable definitions |
| 6 | Designs sheet layouts, chart specifications, and master item definitions |
| 7 | Runs comprehensive QA across all artifacts |
| 8 | Produces documentation (data dictionary, tech spec, user guide, runbook) |

## Where You'll Be Involved

The pipeline pauses at specific points and asks for your input. This is by design.

**Approval gates** require your sign-off before the pipeline advances:

- After Phase 1, you review and approve the project specification before architecture begins.
- After Phase 7, all critical QA findings must be resolved before documentation is generated.

**Execution validation gates** require you to load artifacts in Qlik Sense and report results:

- After Phase 4, load the generated scripts and run a full reload. The pipeline tells you exactly what to check: reload success, synthetic keys, TRACE output, row counts.
- After Phase 5, evaluate key expressions against loaded data and report any syntax errors or incorrect results.

Multiple reload-fix cycles at these gates are expected. The pipeline routes your findings to the right agent, generates fixes, and sends you back to validate again.

**Dependency blocks** don't halt the pipeline. If a source system or input isn't available yet, the pipeline continues with documented placeholders and tracks what needs regeneration when the dependency resolves.

## Qlik Cloud MCP Integration (Optional)

When the Qlik Cloud MCP server is configured in Claude Code, the pipeline uses it for:

- Live analysis of reference apps during platform context capture
- Expression validation against loaded data
- Sheet and master item scaffolding directly in your Qlik app
- Data quality validation during comprehensive QA

The pipeline works without MCP. Source profiling falls back to manual templates, and execution validation relies on you loading scripts and reporting results.

## What's Under the Hood

The plugin includes an orchestrator agent that coordinates seven specialized agents (requirements, data architecture, scripting, expressions, visualization, QA, documentation). Each agent carries practitioner-authored Qlik knowledge covering data modeling patterns, load script syntax, expression authoring, performance optimization, security, and naming conventions. A PostToolUse hook validates all generated .qvs files against common LLM failure patterns like SQL syntax in LOAD statements.

You don't interact with agents or skills directly. The orchestrator manages the full workflow.

## Author & License

**Author:** Pupfish, LLC — [pupfish.io](https://pupfish.io)
**Repository:** [github.com/Pupfish-LLC/qlik-dev](https://github.com/Pupfish-LLC/qlik-dev)
**License:** Proprietary — see [LICENSE](LICENSE)
