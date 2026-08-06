"""Run the Sovereign Desktop local API server."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent / "src"))
from sovereign_desktop.api_server import serve

if __name__ == "__main__":
    serve()
