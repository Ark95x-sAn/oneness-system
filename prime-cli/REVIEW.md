# Oneness System + Prime CLI Review
Date: 2026-07-29
Reviewer: Prime Fire Council automated review
Scope: Recent changes (prime-cli, meta_agent.py, Program.cs route fix, config.toml fix, .env, scheduled tasks, service installer)

## Findings

[P1] `prime start` previously used `shell=True` with the batch file and a 3-second hardcoded sleep, causing false-negative `web_ready` reports and potential command-injection risk if paths were user-controlled.
- File: prime-cli/src/prime/commands.py
- Status: FIXED — now launches orchestrator and web as separate Popen processes with `CREATE_NO_WINDOW`, no shell, and polls up to 45 seconds for API readiness.

[P1] `prime stop` originally matched any process with "dotnet" in the name, risking killing unrelated .NET workloads.
- File: prime-cli/src/prime/commands.py
- Status: FIXED — now only kills processes whose command line or name contains "oneness" or "oneness_orchestrator".

[P2] `psutil` was not declared as a dependency, so `prime stop` silently returned 0 kills before.
- File: prime-cli/pyproject.toml
- Status: FIXED — added `psutil>=5.9.0`.

[P2] Duplicate admin installer scripts existed (`admin_install_combined.ps1`, `install_service_only.ps1`, `RUN_AS_ADMIN_INSTALL.ps1`), creating confusion about which to run.
- Directory: scripts/integrations
- Status: FIXED — removed duplicates; single canonical script is `RUN_AS_ADMIN_INSTALL.ps1` with desktop shortcut `Oneness Admin Install.lnk`.

[P2] `prime review` uses naive keyword scanning and flags its own source code containing the words "password"/"secret"/"token".
- File: prime-cli/src/prime/commands.py
- Status: ACCEPTED RISK — documented as lightweight heuristic in README and skill. Replace with AST/token-aware scanner if used for security gates.

[P3] `prime projects list` currently calls `cmd_status`, which returns full health/tool/project data rather than just projects.
- File: prime-cli/src/prime/main.py
- Status: ACCEPTED — no dedicated `/api/projects` list-only endpoint exists; current behavior is functional.

[P3] `.env` file contains placeholder keys. If copied verbatim to production without editing, API calls will fail or use invalid credentials.
- File: .env
- Status: DOCUMENTED — README and skill instruct user to replace placeholders with real keys.

## Overall Assessment

The Prime CLI and meta-agent provide a durable, scriptable control surface for the Oneness System. The most significant risks (unscoped process termination, shell=True, missing dependency) have been addressed. Remaining risks are low-impact or documented acceptance.

Recommended next steps:
1. Add unit tests for API client and `_find_oneness_processes`.
2. Replace naive `prime review` heuristic with AST-based or semgrep-style scanning.
3. Add a `prime logs` command to tail orchestrator/web logs.
