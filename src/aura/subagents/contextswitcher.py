"""ContextSwitcher: infers user context from active window and suggests the next best action."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "contextswitcher.log"

CONTEXT_MAP = {
    "visual studio": {"context": "dotnet_build", "suggestion": "Run build + test cycle", "agent": "SIGNALFORGE"},
    "vs code": {"context": "code_edit", "suggestion": "Lint, test, or scaffold", "agent": "SIGNALFORGE"},
    "codex": {"context": "ai_ops", "suggestion": "Delegate heavy ops to agents", "agent": "SYNAPSE"},
    "claude": {"context": "ai_ops", "suggestion": "Deep reasoning task", "agent": "CASEBLADE"},
    "perplexity": {"context": "research", "suggestion": "Capture findings to memory/intel", "agent": "PROX"},
    "chrome": {"context": "research", "suggestion": "Summarize tab content", "agent": "PROX"},
    "notion": {"context": "planning", "suggestion": "Sync plan with Oneness tasks", "agent": "SYNAPSE"},
    "call of duty": {"context": "gaming", "suggestion": "Pause all background ops", "agent": "GAMEGUARD"},
    "polymarket": {"context": "trading", "suggestion": "Run paper-bot evaluation", "agent": "TRADEWEAVER"},
}


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | CONTEXTSWITCHER | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def infer_context(active_window: str) -> dict:
    lower = active_window.lower()
    for key, ctx in CONTEXT_MAP.items():
        if key in lower:
            return {**ctx, "matched_on": key}
    return {"context": "general", "suggestion": "Run daily brief and priority queue", "agent": "SYNAPSE", "matched_on": ""}


def main():
    while True:
        try:
            latest = json.loads((MEMORY_DIR / "latest.json").read_text(encoding="utf-8"))
            active = latest.get("active_window", "")
            ctx = infer_context(active)
            log(f"context={ctx['context']} agent={ctx['agent']} suggestion='{ctx['suggestion']}' window='{active[:60]}'")
            state_path = MEMORY_DIR / "contextswitcher_state.json"
            state_path.write_text(json.dumps(ctx), encoding="utf-8")
            time.sleep(60)
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(60)


if __name__ == "__main__":
    main()
