import shutil
import tempfile
from pathlib import Path
from datetime import datetime

def clean_folder(path: Path, days: int = 7):
    if not path.exists():
        return 0
    freed = 0
    for item in path.rglob("*"):
        try:
            if item.is_file() and (datetime.now() - item.stat().st_ctime).days > days:
                freed += item.stat().st_size
                item.unlink()
        except Exception:
            pass
    return freed

total = 0
total += clean_folder(Path(tempfile.gettempdir()), days=7)
total += clean_folder(Path.home() / "Downloads" / "Temp", days=30)
total += clean_folder(Path.home() / ".codex" / ".tmp" / "marketplaces" / "sage" / "packages" / "claude-code" / "node_modules" / ".cache", days=30)

print(f"Daily cleanup freed {total / (1024*1024):.1f} MB")
