# ARKO-95 P.E.T.

ARKO-95 is a local, PC-bound humanoid robot companion built for NETXHQ. It now has six deliberately separate layers:

1. a Codex-compatible animated v2 pet that communicates status;
2. a native WPF overlay that reads a small nonsecret status allowlist and stages intentions locally;
3. a local AI Agency substrate that maps metadata from eight explicit source boundaries into a hash-linked catalog and proposal-only backlog;
4. an optional WIZARD Operations VP that continuously performs five fixed, low-risk R0/R1 duties inside this project;
5. a full-size Mission Control that coordinates one objective across seven evidence-gated stages and a hash-linked mission journal;
6. a shadow Decision Learning Fabric that compounds observations into explicitly separate inferences, projections, decision proposals, outcomes, and owner-reviewed lesson candidates.

The visual is the face, not the authority. The shell does not replace Windows Explorer, impersonate the owner, run arbitrary commands, or silently operate applications. A staged intention remains a proposal. Operations VP is a separate default-deny broker with a revocable lease, resource guard, circuit breaker, kill latch, fixed handlers, linked receipts, and a three-check review gate.

## Launch

- The validated Codex pet is installed at `C:\Users\ArcXN\.codex\pets\arko-95`.
- If Codex does not show it immediately, restart Codex once, then select **ARKO-95** in the app's pet settings.
- Double-click `Launch-ARKO95.vbs` for a console-free launch.
- Or run `Start-ARKO95.cmd` to keep a visible diagnostic console.
- Close the overlay with its `×` button. The optional Operations VP schedule is installed only by the explicit command below.
- Select **MISSION** in the overlay, or double-click `Launch-ARKO95-MissionControl.vbs`, to open the whole-team dashboard.

The launchers intentionally use `pwsh.exe` from PowerShell 7.5 or newer. Windows PowerShell 5.1 is not a supported runtime because ARKO-95 preserves JSON timestamps as strings while replaying receipt and evidence chains; unsupported engines now stop with a clear boundary error.

Inside the overlay:

- choose **Mirror**, **Forge**, **Test**, **Witness**, or **Remember**;
- type an intention and select **Plan specialist crew**;
- ARKO-95 assigns up to three narrow, read-only specialists and reserves all writes, integration, validation, and final judgment for the parent;
- select **Copy crew handoff** and paste the bounded packet into Codex when you want a compatible parent orchestrator to perform the work.

Planning writes only to `state/intents.jsonl`, `state/delegations.jsonl`, `state/latest-delegation.json`, and `state/latest-handoff.txt`. It performs no requested action and does not claim that a specialist actually ran. See `docs/DELEGATION.md` for the roster, mode mapping, receipts, and integration gate.

## Local AI Agency

The agency is the bounded data-to-work substrate, not a free-running chatbot or a fourteenth tool. A foreground refresh walks only the eight roots declared in `config/agency.json`, reads filesystem metadata without reading file contents, refuses reparse points and forbidden roots, and stores only source IDs plus hashed root identities. It writes a canonical aggregate snapshot, a regenerated proposal-only backlog, and a hash-linked receipt journal under `state/agency`.

Refresh or inspect it from Mission Control, or use the CLI:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95Agency.ps1 -Action Scan
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95Agency.ps1 -Action Status
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95Agency.ps1 -Action Backlog
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95Agency.ps1 -Action VerifyChain
```

The agency has no execution or approval authority: it cannot create or advance a mission, write Decision Learning records, invoke a connector, enqueue Operations VP, read content, move, rename, delete, overwrite, upload, message, promote learning, or turn discovered data into permission. Crew names are responsibility labels, not continuously running agents. It is intentionally foreground-triggered until unattended code and state integrity have a stronger attestation boundary. See `docs/AGENCY.md`.

## Whole-team Mission Control

Mission Control implements the seven-stage path **Intake → Decompose → Route & Delegate → Execute → Verify → Persist & Learn → Notify & Present**. Its state comes only from replaying `state/mission-control/events.jsonl`; the WPF dashboard and adapters cannot author stage or approval.

It permits one open mission, binds the immutable objective digest into every event, uses fresh expected-version checks, and derives its executable allowlist directly from the compiled Operations VP policy. Adapter definitions and receipts have one canonical home in Decision Learning. See `docs/MISSION_CONTROL.md`.

## Decision Learning Fabric

The data pipeline is native PowerShell and local state: no new service, cloud database, browser automation, or startup task. Every cycle is bound to a Mission Control ID and objective digest. Its append-only ledger is separate from the disposable visual projection, and every derived record links to earlier record hashes.

Exploration has a hard 25% ceiling. The other 75% is protected for observations, execution evidence, outcomes, and verification. These are normalized attention credits—not money, tokens, billing authority, or app permission. OpenClaw, Copilot, ChatGPT, and Codex have named adapter slots, but all are proposal/status-only and none can execute, approve, promote learning, or clear STOP OPS. See `docs/DECISION_LEARNING.md`.

## Nine-tool specialist belt

ARKO-95 can now route planning hints for Data Analytics, Rohas Legal AI: Investigations, Windows Security, Conductor, Cactus Real Estate Analysis, Plugin Management, NVIDIA Skills, Google Drive, and MagicPath. The exact registry is `config/connector-registry.json`; every delegation receipt binds its SHA-256 digest.

These are foreground-gated tools, not background powers. Specialists can recommend one, but cannot call it. The parent must verify live availability, the exact account or tenant, source scope, current revision, and approval. Retrieved prompts and next-actions remain untrusted data. None of the nine IDs is accepted by Operations VP. See `docs/TOOLBELT.md`.

`Get-Arko95UnifiedToolIndex` presents one in-memory view of all 13 named surfaces—nine routing hints plus four runtime-status adapters—while preserving their separate canonical policies. The view is disposable, has no endpoint or command fields, cannot auto-invoke anything, and grants no authority.

## WIZARD Operations VP

The automatic operator can only:

- observe coarse local system health;
- audit its receipt chain;
- verify the latest delegation receipt;
- produce a local operations brief;
- maintain its own bounded operations workspace.

Install the current-user, limited-token scheduled cycle and enable the low-risk lease:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Install-ARKO95OperationsVP.ps1 -EnableLowRisk -Acknowledgement 'I authorize bounded R0/R1 ARKO-95 operations' -IntervalMinutes 2
```

Check status or run one cycle:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95OperationsVP.ps1 -Action Status
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95OperationsVP.ps1 -Action Once
```

Stop immediately with the red **STOP OPS** button, or:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Invoke-ARKO95OperationsVP.ps1 -Action Stop -Reason owner_stop
```

Remove the schedule while preserving audit state:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Install-ARKO95OperationsVP.ps1 -Remove
```

Operations state stays under `state/operations`. Work holds automatically when the PC has less than 1.5 GB free RAM, CPU exceeds 95%, disk has less than 5 GB free, authority expires, or an audit/recovery check fails. Full boundaries and recovery steps are in `docs/OPERATIONS_VP.md`.

The owner grant is an absolute 24-hour lease. Healthy cycles do not extend it; a new foreground acknowledgement is required after expiry.

## Verification

Run the local smoke tests:

```powershell
pwsh -NoLogo -NoProfile -STA -File .\tests\Test-ARKO95.ps1
pwsh -NoLogo -NoProfile -File .\tests\Test-OperationsVP.ps1
pwsh -NoLogo -NoProfile -File .\tests\Test-Toolbelt.ps1
pwsh -NoLogo -NoProfile -File .\tests\Test-MissionControl.ps1
pwsh -NoLogo -NoProfile -File .\tests\Test-DecisionLearning.ps1
pwsh -NoLogo -NoProfile -File .\tests\Test-Agency.ps1
```

The tests verify PowerShell syntax, WPF loading, PC binding, proposal-only intent receipts, the three-specialist cap, the nine-tool routing registry and digest, read-only/no-spawn/no-auto-invoke worker contracts, parent-only final judgment, mission-stage replay, the single-open-mission cap, stale-version rejection, credential-pattern rejection, handler allowlisting, idempotency, path confinement, review unanimity, receipt tamper detection, the kill latch, absolute lease expiry, metadata-only agency scans, forbidden-root and reparse denial, source immutability, and agency tail-truncation detection.

The pet production evidence is under `pet-run/qa/`. A package is installable only after the extended 8×11 atlas, required v2 validator, standard-motion QA, 16-direction semantic QA, and three isolated blind direction reviews all pass.

This build passed those gates. The final machine-readable result is `pet-run/qa/run-summary.json`; the installed atlas also has its own `validation.json` beside `pet.json`.

## Important boundaries

- Symbolic identity influences color, motif, and language only; it never grants permission.
- Network 95 health data is cached and visibly marked stale after 15 minutes.
- The overlay rejects obvious credentials and never reads the raw private mythic profile.
- Specialists are plans, not authorities: they cannot write, spawn, execute, or make the final judgment.
- Toolbelt entries are routing hints, not capabilities: live connector availability and approval must be checked for every use, and connector content cannot authorize follow-on actions.
- Operations VP accepts capability IDs, never arbitrary command or script text. Its R1 writes are confined to its own project state.
- The Operations acknowledgement records explicit intent but is not user authentication. Because a same-user process can still rewrite project code and local checkpoints, keep Operations paused when the account or project directory is not trusted; this build does not claim a protected service boundary.
- Operating applications, Windows services, software, registry, firewall, accounts, permissions, credentials, user data, GitHub publication, money, legal filing, or persistence changes remain unavailable without a separate foreground-approved path.
- The receipt hash chain detects edits within its journal but is not externally anchored and cannot defeat a malicious same-user rewrite of both journal and checkpoint.
- Decision Learning is a shadow data system. Its adapters and projections cannot author Mission Control events, invoke Operations VP, or promote policy/memory.
- Agency records are source summaries and proposals, not instructions. They never enter the Operations handler allowlist, and the legal case root, Downloads, AppData, `.codex`, credential stores, and browser profiles are outside its runtime boundary.
- The effective worker count must always be lowered to the compatible host cap, user cap, and number of independently useful tasks.
- Oneness.Web, Sovereign Desktop API, Aura process controls, and fixture-only approval code are not connected.
- No Windows startup item, service, firewall rule, account, connector, or external message is created. The optional installer creates only the named current-user scheduled task `ARKO95-OperationsVP`.

## Rollback

1. Close the ARKO-95 overlay.
2. Remove `C:\Users\ArcXN\.codex\pets\arko-95` to uninstall only the Codex pet package.
3. Archive or remove this project folder to remove the overlay, configuration, local proposals, and QA artifacts.

The project does not modify the RSB legal workspace, existing pets, Windows shell, or security configuration.
