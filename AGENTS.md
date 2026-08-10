# OnenessSystem Agent Guidance

## Project Overview
Self-operating GM700 / dual-PC / avatar-twin automation workspace.
Top Codex plugins/skills: GitHub, Computer Use, Codex Coordinator, Superpowers, Oneness Gaming Mode.

## Codex task-boundary board

- This repository uses the opt-in Codex task-boundary board in .codex/coordination/project.yaml.
- Before substantial writes, load the installed codex-coordinator skill, list active claims from the primary worktree, and publish only this task's bounded claim.
- Native Codex tasks remain the execution, messaging, and transcript authority; an explicitly requested goal Coordinator is on demand, with no heartbeat or mandatory pull-request workflow.
- Reject cross-project notices and never store transcripts, reasoning, prompts, or tool output in Coordinator state.

## Safety Rules
- All destructive actions (process kill, uninstall, compression, registry edit, BIOS change, driver update) require explicit user approval.
- Use the provided un-swarm.ps1 in report mode first; use -Execute only after reviewing the output.


## Operations Mind

The Operations Mind (src/ops_mind/) is the unified PC operations oversight brain.
It monitors CPU, RAM, disk, services, processes, network, reboot status, and app
inventory every 5 minutes via a Windows Scheduled Task (Oneness-OperationsMind).

- All monitors are read-only. No destructive actions run automatically.
- All remediation scripts are preview-only. The user must review and run them.
- Commands: scripts\run_ops_mind.bat --once|--health|--status|--loop
- Reports: memory/ops_mind/reports/latest-report.json
- State: memory/ops_mind/state.json
- Docs: OPS_MIND.md
- Install/remove: scripts\install_ops_mind_service.ps1 / -Remove
