# ARKO-95 Mission Control

Mission Control turns the pet, bounded specialist planner, five-handler Operations VP, and proof receipts into one visible workflow:

> one objective, one replayed state, one evidence chain.

It is the working interpretation of the Network-95 reference boards. The useful pattern is retained—capture, synchronize, fuse, decode, verify, act—but the decorative implication that every sensor or integration is online is rejected.

## Open it

Double-click `Launch-ARKO95-MissionControl.vbs`, or select **MISSION** in the compact ARKO-95 overlay.

The dashboard has four owner actions before independent verification:

1. **Stage objective** seals one objective, its SHA-256 digest, constraints, and success criteria at Intake.
2. **Prepare team plan** creates the existing three-specialist, read-only delegation receipt and advances through Decompose to Route & Delegate.
3. **Queue safe local duty** can select only one of the five compiled Operations VP capabilities. It cannot accept a command, script, connector ID, or parameters.
4. **Link completed duty** advances to Verify only after the exact linked duty is completed and has a review receipt.

Mission Control then requires an independent verifier before Persist & Learn and the parent integrator before Notify & Present. Those final APIs exist in `Arko95.MissionControl.psm1`; the dashboard intentionally does not make machine self-approval one click away.

The dashboard also reads the separate Decision Learning Fabric. That fabric may compound source-linked observations into inferences, projections, inert decision proposals, outcomes, and lesson candidates, but it cannot advance a mission or execute a duty. Its 25% exploration ceiling and four AI-adapter slots are documented in `DECISION_LEARNING.md`.

## Seven stages

| Stage | Lane | Gate |
|---|---|---|
| Intake | Signal Scout | One owner objective, constraints, criteria, and admitted sources |
| Decompose | Path Architect | Typed tasks and acceptance evidence |
| Route & Delegate | Tool Router | Three-specialist receipt; connectors remain routing hints |
| Execute | Operations VP | Exact compiled R0/R1 capability and Operations duty receipt |
| Verify | Proof Verifier | Completed duty, independent review, and criterion evidence |
| Persist & Learn | Receipt Archivist | Passed verification; lessons remain proposals |
| Notify & Present | Parent Integrator | Local outcome, unresolved gaps, and one next owner decision |

The active stage is never read from a button, OpenClaw message, connector response, or mutable snapshot. It is rebuilt by replaying `state/mission-control/events.jsonl` and checking sequence, policy digest, mission version, objective digest, previous hash, and event hash.

## Whole-team contract

- The parent integrator owns requirements, architecture, conflicts, writes, final validation, and final judgment.
- Specialists are narrow evidence lanes. They do not spawn, approve, change policy, execute, or decide the final result.
- Operations VP is the only automatic execution lane, and it retains its existing lease, kill, resource, circuit, fixed-handler, and three-review gates.
- Automated review proves mechanics; it is not human approval.
- The archivist preserves originals, derivatives, contradictions, and linked receipts. Learning candidates never auto-change memory or policy.
- The presenter writes locally. External notification defaults to false.

## OpenClaw boundary

The current read-only observation verified:

- OpenClaw Companion `2026.9.4` is signed and connected to a WSL gateway bound to loopback on NETXHQ;
- the selected model is `ollama-cloud / minimax-m2.7`;
- completed assistant-response delivery events exist in current logs;
- response content, quality, and human viewing were not inspected.

The observation is stored without a token or chat content under `state/mission-control/adapter-observations`. It is now expired and predates the canonical Decision Learning receipt hash, so the adapter fabric reports it as integrity-unverified rather than live capability. OpenClaw is a proposal/status adapter. It cannot write mission events, select a sensor, invoke Operations VP, approve work, promote learning, or clear the kill latch.

## Sensor honesty

A catalog label is not a live sensor. The 24 domains in the inspiration board are a future taxonomy, not present PC capability. Mission Control treats a sensor as unavailable unless a fresh receipt includes its adapter and version, host/account or tenant, observation time and expiry, source reference, and observation digest.

No biometric, camera, microphone, location, browser, screen, network, security, or environmental collection is enabled by this project.

## Integrity and recovery

- One open mission is enforced under a named cross-process mutex.
- Every mutation carries the expected mission version; stale windows fail closed.
- Only adjacent forward stage transitions are valid.
- Holding or aborting a mission never erases prior events.
- Closing the dashboard does not stop Operations VP; use **STOP OPS**.
- SHA-256 linking detects ordinary edits, deletion from the middle, and reordering during replay. It has no external tail checkpoint, so clean tail truncation or a malicious same-user rewrite of the complete journal and projection remains outside its guarantee.

## CLI

Read status or verify the chain:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95MissionControl.ps1 -Action Status
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95MissionControl.ps1 -Action VerifyChain
```

State-changing CLI actions require a fresh mission ID and expected version. This optimistic-concurrency check prevents stale control surfaces from advancing a newer state.

## Tests

```powershell
pwsh -NoLogo -NoProfile -File .\tests\Test-MissionControl.ps1
```

The suite uses isolated state roots under this project's `state` folder and never invokes a connector, sends a message, changes Windows settings, or expands the five-handler broker.
