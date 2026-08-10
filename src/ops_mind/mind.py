"""mind.py — The Operations Mind: unified PC oversight orchestration brain.

Runs a continuous loop that monitors PC health, generates unified status
reports, and produces safe (preview-only) remediation scripts. All
destructive actions require explicit user approval.

Usage:
    python -m src.ops_mind.mind --once        # single cycle + report
    python -m src.ops_mind.mind --cycle       # single cycle only
    python -m src.ops_mind.mind --report      # generate report from last cycle
    python -m src.ops_mind.mind --loop         # continuous 24/7 loop
    python -m src.ops_mind.mind --health       # quick health check
    python -m src.ops_mind.mind --status       # print current state
"""
import argparse
import json
import logging
import sys
import time
import os
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR.parent))

from ops_mind import (
    ROOT, SRC, MEMORY, OPS_MIND_ROOT, RAW_DIR, REPORTS_DIR,
    REMEDIATIONS_DIR, LOG_DIR, STATE_PATH,
    ensure_dirs, now_iso, write_json, load_json,
    DEFAULT_CYCLE_INTERVAL, DEFAULT_REPORT_INTERVAL,
    DEFAULT_REMEDIATE_INTERVAL,
    CPU_CRITICAL, CPU_HIGH, RAM_CRITICAL, RAM_HIGH,
)
from ops_mind.monitors import run_all_monitors
from ops_mind.reporter import generate_report
from ops_mind.remediator import generate_remediations

ensure_dirs()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | OPS-MIND | %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(str(LOG_DIR / "ops_mind.log"), encoding="utf-8", mode="a"),
    ],
)
log = logging.getLogger("ops_mind")


class OperationsMind:
    """The central brain that oversees all PC operations."""

    def __init__(self):
        self.state = load_json(STATE_PATH, default={
            "created": now_iso(),
            "last_cycle": None,
            "last_report": None,
            "last_remediate": None,
            "cycles_run": 0,
            "reports_generated": 0,
            "remediations_generated": 0,
            "health_score": None,
            "current_findings": [],
            "snapshots": {},
        })
        self.timers = {}
        log.info("Operations Mind initialized. Cycles run: %d", self.state.get("cycles_run", 0))

    # ------------------------------------------------------------------
    # Core cycle: run all monitors
    # ------------------------------------------------------------------
    def cycle(self):
        """Run all monitors and collect findings."""
        log.info("=== OPS MIND CYCLE START ===")
        ts = now_iso()

        results, findings = run_all_monitors()

        # Extract snapshots
        snapshots = {}
        for name, result in results.items():
            if result.get("status") == "ok":
                snapshots[name] = result.get("snapshot", {})

        # Calculate health score (0-100, higher = healthier)
        health_score = self._calculate_health(findings, snapshots)

        # Save raw cycle data
        raw_path = RAW_DIR / f"cycle-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
        write_json(raw_path, {
            "timestamp": ts,
            "monitors": results,
            "findings": findings,
            "health_score": health_score,
        })

        # Update state
        self.state["last_cycle"] = ts
        self.state["cycles_run"] = self.state.get("cycles_run", 0) + 1
        self.state["current_findings"] = findings
        self.state["snapshots"] = snapshots
        self.state["health_score"] = health_score
        write_json(STATE_PATH, self.state)

        # Summary
        critical = [f for f in findings if f.get("severity") == "critical"]
        warnings = [f for f in findings if f.get("severity") == "warning"]
        info = [f for f in findings if f.get("severity") == "info"]
        log.info("Cycle complete: %d findings (%d critical, %d warning, %d info). Health: %s/100",
                 len(findings), len(critical), len(warnings), len(info), health_score)

        for f in critical:
            log.warning("CRITICAL: %s", f.get("title"))
        for f in warnings:
            log.info("WARNING: %s", f.get("title"))

        return {
            "timestamp": ts,
            "health_score": health_score,
            "findings": findings,
            "snapshots": snapshots,
            "raw_path": str(raw_path),
        }

    # ------------------------------------------------------------------
    # Health score calculation
    # ------------------------------------------------------------------
    def _calculate_health(self, findings, snapshots):
        """Compute a 0-100 health score (100 = perfectly healthy)."""
        score = 100

        for f in findings:
            sev = f.get("severity", "info")
            if sev == "critical":
                score -= 20
            elif sev == "warning":
                score -= 8
            elif sev == "info":
                score -= 2

        # Adjust based on actual metrics
        tel = snapshots.get("telemetry", {})
        cpu = tel.get("cpu_percent", 0)
        ram = tel.get("ram_percent", 0)
        disk = tel.get("disk_pct_free", 100)

        if cpu >= CPU_CRITICAL:
            score -= 10
        elif cpu >= CPU_HIGH:
            score -= 5

        if ram >= RAM_CRITICAL:
            score -= 10
        elif ram >= RAM_HIGH:
            score -= 5

        if disk <= 5:
            score -= 15
        elif disk <= 15:
            score -= 5

        reboot = snapshots.get("reboot", {})
        if reboot.get("reboot_pending"):
            score -= 5

        return max(0, min(100, round(score, 1)))

    # ------------------------------------------------------------------
    # Report generation
    # ------------------------------------------------------------------
    def report(self):
        """Generate a unified status report from the latest cycle."""
        result = generate_report(self.state, REPORTS_DIR)
        self.state["last_report"] = now_iso()
        self.state["reports_generated"] = self.state.get("reports_generated", 0) + 1
        write_json(STATE_PATH, self.state)
        log.info("Report generated: %s", result.get("report_path"))
        return result

    # ------------------------------------------------------------------
    # Remediation generation (preview-only, safe)
    # ------------------------------------------------------------------
    def remediate(self):
        """Generate safe, preview-only remediation scripts from findings."""
        findings = self.state.get("current_findings", [])
        result = generate_remediations(findings, REMEDIATIONS_DIR)
        self.state["last_remediate"] = now_iso()
        self.state["remediations_generated"] = self.state.get("remediations_generated", 0) + len(result.get("generated", []))
        write_json(STATE_PATH, self.state)
        log.info("Remediations generated: %d scripts", len(result.get("generated", [])))
        return result

    # ------------------------------------------------------------------
    # Quick health check
    # ------------------------------------------------------------------
    def health(self):
        """Run a quick single-cycle health check and return summary."""
        cycle_result = self.cycle()
        return {
            "health_score": cycle_result["health_score"],
            "critical_count": len([f for f in cycle_result["findings"] if f.get("severity") == "critical"]),
            "warning_count": len([f for f in cycle_result["findings"] if f.get("severity") == "warning"]),
            "info_count": len([f for f in cycle_result["findings"] if f.get("severity") == "info"]),
            "snapshots": cycle_result["snapshots"],
            "timestamp": cycle_result["timestamp"],
        }

    # ------------------------------------------------------------------
    # Status (from saved state, no new cycle)
    # ------------------------------------------------------------------
    def status(self):
        """Return current state without running a new cycle."""
        state = load_json(STATE_PATH, default={})
        return {
            "state": state,
            "ops_mind_root": str(OPS_MIND_ROOT),
            "raw_files": len(list(RAW_DIR.glob("*.json"))) if RAW_DIR.exists() else 0,
            "reports": len(list(REPORTS_DIR.glob("*.json"))) if REPORTS_DIR.exists() else 0,
            "remediations": len(list(REMEDIATIONS_DIR.glob("*.ps1"))) if REMEDIATIONS_DIR.exists() else 0,
        }

    # ------------------------------------------------------------------
    # Continuous loop
    # ------------------------------------------------------------------
    def run_loop(self, cycle_interval=DEFAULT_CYCLE_INTERVAL,
                 report_interval=DEFAULT_REPORT_INTERVAL,
                 remEDIATE_interval=DEFAULT_REMEDIATE_INTERVAL):
        """Run the continuous 24/7 oversight loop."""
        log.info("=== OPERATIONS MIND LOOP STARTED ===")
        log.info("Cycle every %ds, Report every %ds, Remediate every %ds",
                 cycle_interval, report_interval, remEDIATE_interval)
        try:
            while True:
                now = time.time()

                if self._due("cycle", cycle_interval):
                    self.cycle()

                if self._due("report", report_interval):
                    self.report()

                if self._due("remediate", remEDIATE_interval):
                    self.remediate()

                time.sleep(5)
        except KeyboardInterrupt:
            log.info("Shutdown requested. Saving state...")
            write_json(STATE_PATH, self.state)
            log.info("State saved. Operations Mind offline.")

    def _due(self, key, interval):
        now = time.time()
        if key not in self.timers or now - self.timers[key] >= interval:
            self.timers[key] = now
            return True
        return False


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Operations Mind — Unified PC Operations Oversight",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Commands:
  --once       Run a single cycle, generate report + remediations, then exit
  --cycle      Run a single monitoring cycle
  --report     Generate a status report from the last cycle
  --remediate  Generate remediation scripts from current findings
  --health     Quick health check (single cycle, summary only)
  --status     Show current saved state (no new cycle)
  --loop       Run continuous 24/7 oversight loop

Options:
  --cycle-interval    Seconds between cycles in loop mode (default: 60)
  --report-interval   Seconds between reports in loop mode (default: 300)
  --remediate-interval Seconds between remediation generation (default: 600)
        """,
    )
    parser.add_argument("--once", action="store_true", help="Single cycle + report + remediate, then exit")
    parser.add_argument("--cycle", action="store_true", help="Single monitoring cycle")
    parser.add_argument("--report", action="store_true", help="Generate status report")
    parser.add_argument("--remediate", action="store_true", help="Generate remediation scripts")
    parser.add_argument("--health", action="store_true", help="Quick health check")
    parser.add_argument("--status", action="store_true", help="Show current state")
    parser.add_argument("--loop", action="store_true", help="Continuous 24/7 loop")
    parser.add_argument("--cycle-interval", type=int, default=DEFAULT_CYCLE_INTERVAL)
    parser.add_argument("--report-interval", type=int, default=DEFAULT_REPORT_INTERVAL)
    parser.add_argument("--remediate-interval", type=int, default=DEFAULT_REMEDIATE_INTERVAL)
    parser.add_argument("--json", action="store_true", help="Output JSON only")
    args = parser.parse_args()

    mind = OperationsMind()

    if args.once:
        cycle_result = mind.cycle()
        report_result = mind.report()
        remediate_result = mind.remediate()
        if args.json:
            print(json.dumps({
                "cycle": cycle_result,
                "report": report_result,
                "remediate": remediate_result,
            }, indent=2, default=str))
        else:
            print(f"\n{'='*60}")
            print(f"  OPERATIONS MIND — CYCLE COMPLETE")
            print(f"{'='*60}")
            print(f"  Health Score: {cycle_result['health_score']}/100")
            findings = cycle_result["findings"]
            crit = [f for f in findings if f.get("severity") == "critical"]
            warn = [f for f in findings if f.get("severity") == "warning"]
            info = [f for f in findings if f.get("severity") == "info"]
            print(f"  Findings: {len(crit)} critical, {len(warn)} warning, {len(info)} info")
            print(f"  Report: {report_result.get('report_path', 'N/A')}")
            print(f"  Remediations: {len(remediate_result.get('generated', []))} scripts")
            snap = cycle_result["snapshots"]
            tel = snap.get("telemetry", {})
            print(f"\n  CPU: {tel.get('cpu_percent', '?')}%")
            print(f"  RAM: {tel.get('ram_percent', '?')}% ({tel.get('ram_used_gb', '?')} GB / {tel.get('ram_total_gb', '?')} GB)")
            print(f"  Disk: {tel.get('disk_free_gb', '?')} GB free ({tel.get('disk_pct_free', '?')}%)")
            svc = snap.get("services", {})
            print(f"  Services: {svc.get('running', '?')}/{svc.get('total_checked', '?')} running")
            if svc.get("stopped_names"):
                print(f"  Stopped: {', '.join(svc['stopped_names'])}")
            rb = snap.get("reboot", {})
            print(f"  Reboot pending: {rb.get('reboot_pending', False)}")
            print(f"  Uptime: {rb.get('uptime_days', 0)}d {rb.get('uptime_hours', 0)}h")
            print(f"\n  State: {STATE_PATH}")
            print(f"  Reports: {REPORTS_DIR}")
            print(f"  Remediations: {REMEDIATIONS_DIR}")
            print(f"{'='*60}")

    elif args.cycle:
        result = mind.cycle()
        print(json.dumps(result, indent=2, default=str) if args.json else f"Cycle complete. Health: {result['health_score']}/100, {len(result['findings'])} findings")

    elif args.report:
        result = mind.report()
        print(json.dumps(result, indent=2, default=str) if args.json else f"Report: {result.get('report_path')}")

    elif args.remediate:
        result = mind.remediate()
        print(json.dumps(result, indent=2, default=str) if args.json else f"Remediations: {len(result.get('generated', []))} scripts generated")

    elif args.health:
        result = mind.health()
        print(json.dumps(result, indent=2, default=str) if args.json else f"Health: {result['health_score']}/100 | {result['critical_count']} critical, {result['warning_count']} warning")

    elif args.status:
        result = mind.status()
        print(json.dumps(result, indent=2, default=str))

    elif args.loop:
        mind.run_loop(args.cycle_interval, args.report_interval, args.remediate_interval)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()