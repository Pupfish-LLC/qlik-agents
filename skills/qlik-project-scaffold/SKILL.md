---
name: qlik-project-scaffold
description: Initialize a new Qlik project with standard directory structure, input subdirectories, artifact phases, and dependency tracking template.
disable-model-invocation: true
---

# qlik-project-scaffold

## Overview

This skill scaffolds a new Qlik development project with the complete directory structure specified by the Qlik Development Framework. It creates the `inputs/` directory tree for source materials, the `artifacts/` directory tree for framework output organized by phase, and initializes `.pipeline-state.json` for dependency tracking throughout the pipeline.

The skill is procedural (no model invocation) and idempotent—safe to re-run on an existing project without destroying data.

## What this skill creates

### 1. Input Source Directories

- **`inputs/source-documentation/`** — Connection specifications, upstream data dictionaries, platform documentation
- **`inputs/existing-apps/`** — QVF files, load scripts, metadata from brownfield applications
- **`inputs/platform-libraries/`** — Shared Qlik libraries, naming conventions, reference implementations
- **`inputs/upstream-architecture/`** — ER diagrams, data lineage, ETL architecture from source systems

Each subdirectory includes a `README.md` explaining what materials belong there.

### 2. Artifact Directories by Phase

- **`artifacts/00-platform-context.md`** — Phase 0 output (framework context document)
- **`artifacts/01-project-specification.md`** — Phase 1 output
- **`artifacts/02-source-profile.md`** — Phase 2 output
- **`artifacts/03-data-model-specification.md`** — Phase 3 output
- **`artifacts/04-scripts/`** — Phase 4 outputs (load scripts, manifest, diagnostics/)
- **`artifacts/05-expression-catalog.md`** — Phase 5 output
- **`artifacts/05-expression-variables.qvs`** — Phase 5 expression variables
- **`artifacts/06-viz-specifications.md`** — Phase 6 outputs
- **`artifacts/07-qa-reports/`** — Phase 7 comprehensive QA review
- **`artifacts/08-documentation/`** — Phase 8 documentation outputs

### 3. Dependency Tracking

- **`.pipeline-state.json`** — JSON state file tracking current phase, artifact versions, blocked dependencies, and execution validation requests/results

## Usage

From your Qlik project root directory:

```
/qlik-project-scaffold
```

The skill creates all directories and the initial `.pipeline-state.json` template. Existing files are not overwritten.

## Directory Structure Created

```
project-root/
├── inputs/
│   ├── source-documentation/
│   │   └── README.md
│   ├── existing-apps/
│   │   └── README.md
│   ├── platform-libraries/
│   │   └── README.md
│   └── upstream-architecture/
│       └── README.md
├── artifacts/
│   ├── 04-scripts/
│   │   └── diagnostics/
│   ├── 07-qa-reports/
│   └── 08-documentation/
└── .pipeline-state.json
```

## Output

Upon completion:

```
✓ Qlik project structure initialized
✓ Input directories created (source-documentation, existing-apps,
  platform-libraries, upstream-architecture)
✓ Artifact directories created (04-scripts/diagnostics, 07-qa-reports,
  08-documentation)
✓ Pipeline state file created: .pipeline-state.json

Next steps:
1. Place source materials in inputs/ subdirectories
2. Review .pipeline-state.json
3. Start Phase 0 with requirements-analyst
```

## Procedure

### Step 1: Create input directories

```bash
mkdir -p inputs/source-documentation
mkdir -p inputs/existing-apps
mkdir -p inputs/platform-libraries
mkdir -p inputs/upstream-architecture
```

### Step 2: Create artifact directories

```bash
mkdir -p artifacts/04-scripts/diagnostics
mkdir -p artifacts/07-qa-reports
mkdir -p artifacts/08-documentation
```

### Step 3: Create input README templates

Each `inputs/` subdirectory receives a `README.md` describing what materials belong there.

### Step 4: Initialize .pipeline-state.json

Create the dependency tracking template:

```json
{
  "currentPhase": 0,
  "projectName": "qlik-project",
  "projectDescription": "",
  "mcpAvailable": {
    "qlikCloud": null
  },
  "artifacts": {},
  "blockedDependencies": [],
  "executionValidation": {
    "requests": [],
    "results": []
  },
  "notes": "Initialize with Phase 0 context analysis. Update currentPhase and artifacts after each phase completion. Set mcpAvailable.qlikCloud to true/false at session startup."
}
```

## Notes

- **Idempotent:** Safe to run multiple times. Existing files are preserved.
- **Plugin-supplied:** Agents and skills are provided by the qlik-dev plugin. This skill only creates the project-specific directory structure.
- **Read-only inputs:** All materials in `inputs/` are read-only for agents during pipeline execution.
- **Artifact evolution:** Agents write to `artifacts/` only. The orchestrator coordinates phase transitions and artifact updates.
- **Field naming:** All field examples in scaffolded documentation follow entity-prefix dot notation (e.g., `[Customer.Status]`, `[Order.Amount]`).
