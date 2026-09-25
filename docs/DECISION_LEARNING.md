# ARKO-95 Decision Learning Fabric

The Decision Learning Fabric is a PC-local, mission-bound scaffold for compounding evidence without confusing a forecast with a fact or a recommendation with permission.

Its invariant is:

> mission authority stays in Mission Control; decision data stays in an append-only lineage ledger; the visual projection is disposable.

## What is native now

- A PowerShell module and CLI run locally on NETXHQ with no service, cloud database, browser automation, or new startup task.
- Every cycle binds to an existing Mission Control mission ID and immutable objective SHA-256.
- One hash-linked `ledger.jsonl` stores cycle and record events. `projection.json` is rebuilt from replay and is never an authority source.
- Records form a same-mission DAG through earlier record IDs and hashes. Forward, missing, duplicate, or cross-mission parents fail closed.
- The dashboard reads the fabric beside Mission Control and labels each adapter truthfully.

State remains beneath `state/decision-learning`:

```text
state/decision-learning/
  ledger.jsonl                 # append-only data authority
  projection.json              # derived, replaceable view
  adapter-observations/        # content-free point-in-time receipts
```

## Compound data pipeline

| Type | Meaning | Required lineage | Authority |
|---|---|---|---|
| `observation` | Source-linked fact or machine state | Source reference | None |
| `inference` | Interpretation | Earlier observation | None |
| `projection` | Forward possibility | Earlier observation or inference | None |
| `decision_proposal` | Recommended bounded option | Earlier inference or projection | None; may name only a compiled Operations VP capability |
| `outcome` | Measured result after separate authorization | Earlier decision plus receipt SHA-256 | None |
| `lesson_candidate` | Reusable learning proposal | Earlier outcome | `proposed_only` |

Content never becomes control data. A record has no command, script, tool arguments, stage field, approval field, or execution effect. A proposed Operations capability must still pass through the existing Mission Control and Operations VP gates.

## The 25% credit rule

Each cycle defaults to 100 normalized attention credits:

- at most 25 may be used by inference, projection, decision-proposal, and lesson-candidate records;
- 75 are protected for observations, receipt-linked outcomes, execution evidence, and verification;
- the 25 credits are a ceiling, not a quota;
- they are not money, API tokens, billing authority, or permission to operate another application;
- credits never replenish automatically and never expand execution authority.

An over-budget append is rejected before it reaches the ledger.

## OpenClaw, Copilot, ChatGPT, and Codex

The four native adapter slots are intentionally asymmetric:

| Adapter | Current boundary | Current authority |
|---|---|---|
| OpenClaw Companion | The local fabric can receipt signed-process presence and the loopback listener; selected model, response quality, and command authority remain separate claims | None |
| Microsoft Copilot | The local fabric can receipt package signature and process presence; sign-in, tenant, response capability, permissions, and ARKO interoperability remain unverified | None |
| ChatGPT | The local fabric can receipt package identity and process presence; account, connector scope, response delivery, and ARKO interoperability remain unverified | None |
| Codex | The local fabric can receipt package/process presence and ARKO pet validation; the only verified handoff remains manual and no ARKO-to-Codex execution bridge is claimed | None |

A valid adapter observation is content-free, expires within 15 minutes, retains no credential, and has a canonical receipt hash. Even a fresh receipt grants no mission, Operations, approval, policy, memory-promotion, or kill-latch authority.

Runtime receipts live under `state/` and are not source-controlled. A checkout therefore never claims that an application is currently present, authenticated, or usable merely because its adapter slot exists.

These four adapter definitions are canonical. Mission Control no longer maintains a duplicate OpenClaw definition or legacy receipt fallback. `Get-Arko95UnifiedToolIndex` may combine adapter and connector metadata for display, but it remains an in-memory, zero-authority projection and never collapses their policy lanes.

Select **Refresh AI fabric** in Mission Control, or run the command below, to create new 15-minute receipts from only the closed local metadata allowlist:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Update-ARKO95AdapterObservations.ps1
```

This refresh does not open an application, sign in, send a prompt, read conversation content, inspect credentials, or test cross-application control.

## CLI

Status and integrity checks:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95DecisionLearning.ps1 -Action Status
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95DecisionLearning.ps1 -Action VerifyChain
```

Start a cycle only after refreshing Mission Control and copying its exact mission ID and objective digest:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95DecisionLearning.ps1 `
  -Action NewCycle -MissionId <mission-id> -ObjectiveHash <sha256>
```

Record appends require the cycle's current version. Parent IDs must identify earlier records in that cycle. Lesson review can mark a candidate `owner_approved_reference` or `rejected`; it still cannot rewrite policy or memory.

## Tests

```powershell
pwsh -NoLogo -NoProfile -File .\tests\Test-DecisionLearning.ps1
```

The suite verifies mission binding, the six-type lineage graph, one-open-cycle concurrency, stale-version rejection, exact 25% enforcement, outcome receipts, proposed-only learning, canonical adapter receipts, derived-projection boundaries, and ledger tamper detection.

## Limits

- The data ledger is subordinate to Mission Control. It cannot advance a mission or invoke a duty.
- Adapter presence does not prove authentication, usable permissions, or interoperability.
- SHA-256 linking detects ordinary edits, deletion from the middle, and reordering, but has no external tail anchor against a complete same-user rewrite or clean tail truncation.
- No model is allowed to approve its own proposal, promote its own lesson, or hide contradictory evidence.
