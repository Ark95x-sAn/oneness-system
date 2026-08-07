"""batch_compress.py — Group many small files into batches and gzip them.

Creates non-destructive batched archives under archive_dir/batches/.
Original files are kept; run with --delete-after-verify to remove them.
"""
import argparse
import gzip
import hashlib
import json
import os
import shutil
import tarfile
from datetime import datetime, timezone
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def compress_batch(files: list[Path], archive_path: Path) -> dict:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {}
    with tarfile.open(archive_path, "w:gz", compresslevel=6) as tar:
        for file in files:
            arcname = file.as_posix()
            tar.add(file, arcname=arcname)
            manifest[arcname] = sha256_file(file)
    return {
        "archive": str(archive_path),
        "files": len(files),
        "size": archive_path.stat().st_size,
        "manifest": manifest,
    }


def run(raw_dir: Path, archive_dir: Path, batch_size: int = 1000, delete_after_verify: bool = False) -> dict:
    files = sorted(raw_dir.rglob("*.json"))
    batches_dir = archive_dir / "batches"
    batches_dir.mkdir(parents=True, exist_ok=True)
    reports = []
    total_archived = 0
    total_bytes_archived = 0

    for i in range(0, len(files), batch_size):
        batch = files[i:i + batch_size]
        archive_path = batches_dir / f"batch_{i // batch_size:04d}.tar.gz"
        report = compress_batch(batch, archive_path)
        reports.append(report)
        total_archived += report["files"]
        total_bytes_archived += report["size"]

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "raw_dir": str(raw_dir),
        "archive_dir": str(archive_dir),
        "batch_size": batch_size,
        "total_files": len(files),
        "total_archived": total_archived,
        "total_bytes_archived": total_bytes_archived,
        "batches": reports,
    }
    summary_path = archive_dir / "batch_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    deleted = 0
    reclaimed = 0
    if delete_after_verify:
        for report in reports:
            archive_path = Path(report["archive"])
            if not archive_path.exists():
                continue
            with tarfile.open(archive_path, "r:gz") as tar:
                members = {m.name: m for m in tar.getmembers()}
                for arcname, expected_hash in report["manifest"].items():
                    if arcname not in members:
                        continue
                    member = members[arcname]
                    f = tar.extractfile(member)
                    if f is None:
                        continue
                    actual_hash = hashlib.sha256(f.read()).hexdigest()
                    if actual_hash == expected_hash:
                        src = Path(arcname)
                        if src.exists():
                            reclaimed += src.stat().st_size
                            src.unlink()
                            deleted += 1

        summary["deleted"] = deleted
        summary["reclaimed_bytes"] = reclaimed
        summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--archive-dir", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=1000)
    parser.add_argument("--delete-after-verify", action="store_true")
    args = parser.parse_args()
    result = run(args.raw_dir, args.archive_dir, args.batch_size, args.delete_after_verify)
    print(json.dumps({"ok": True, "summary": result}, indent=2))


if __name__ == "__main__":
    main()
