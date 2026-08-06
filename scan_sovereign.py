"""Quick scan runner for Sovereign Desktop Ops HQ."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent / "src"))
from sovereign_desktop.orchestrator import scan
import json

if __name__ == "__main__":
    print(json.dumps({"apps": scan()}, indent=2))
