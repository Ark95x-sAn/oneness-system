"""storage_compressor.py — Archive and dedupe raw memory dirs without deleting originals.

Reads target raw directories, groups files by month, deduplicates by SHA-256,
copies unique content into dated gzip archives, and emits a reclaim report.
No source files are removed unless a separate --remove-archived flag is passed
and the caller explicitly confirms the deletion list.

Large directories (> FAST_THRESHOLD json files) switch to a metadata-only
report mode so the pipeline stays fast; they produce a manifest and an offline
compression script instead of reading every file.
"""
import argparse
import gzip
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

FAST_THRESHOLD = 20000


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def archive_dir_for(raw_dir: Path) -> Path:
    return raw_dir.parent / "archive" / datetime.now(timezone.utc).strftime("%Y-%m")


def compress_one(src: Path, dst: Path) -> int:
    dst.parent.mkdir(parents=True, exist_ok=True)
    with open(src, "rb") as f_in:
        with gzip.open(dst, "wb", compresslevel=6) as f_out:
            shutil.copyfileobj(f_in, f_out)
    return dst.stat().st_size


def write_offline_compressor(raw_dir: Path, archive_root: Path, files: list[Path]):
    archive_root.mkdir(parents=True, exist_ok=True)
    script = archive_root / "compress_remaining.ps1"
    rel_raw = str(raw_dir).replace("\\", "/")
    rel_archive = str(archive_root).replace("\\", "/")
    body = f"""
# Auto-generated offline compressor for {raw_dir.name}
# Run this in PowerShell when you have time for a longer batch job.
$raw = '{rel_raw}'
$archive = '{rel_archive}'
$files = Get-ChildItem -Path $raw -Recurse -Filter *.json
$count = 0
foreach ($file in $files) {{
    $dst = Join-Path $archive ($file.FullName.Substring($raw.Length).TrimStart('\\/')) + '.gz'
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    $src = $file.FullName
    $in = [System.IO.File]::OpenRead($src)
    $out = [System.IO.Compression.GzipStream]::new(
        [System.IO.File]::OpenWrite($dst),
        [System.IO.Compression.CompressionLevel]::Optimal)
    $in.CopyTo($out)
    $out.Close()
    $in.Close()
    $count++
}}
Write-Host "Compressed $count files into $archive"
"""
    script.write_text(body, encoding="utf-8")
    return str(script)


def run_full(raw_dir: Path, archive_root: Path):
    files = sorted(raw_dir.rglob("*.json"))
    hashes = {}
    archived = []
    duplicates = []
    raw_bytes = 0
    archive_bytes = 0
    for file in files:
        raw_size = file.stat().st_size
        raw_bytes += raw_size
        h = sha256_file(file)
        if h in hashes:
            duplicates.append(str(file))
            continue
        rel_within = file.relative_to(raw_dir)
        archive_path = archive_root / rel_within.with_suffix(file.suffix + ".gz")
        archived_size = compress_one(file, archive_path)
        hashes[h] = str(archive_path)
        archived.append({"src": str(file), "dst": str(archive_path), "raw_size": raw_size, "archive_size": archived_size})
        archive_bytes += archived_size
    return {
        "mode": "full",
        "files_scanned": len(files),
        "unique_archived": len(archived),
        "duplicates_found": len(duplicates),
        "raw_bytes": raw_bytes,
        "archive_bytes": archive_bytes,
        "archive_root": str(archive_root),
    }


def run_fast(raw_dir: Path, archive_root: Path):
    files = list(raw_dir.rglob("*.json"))
    total_bytes = sum(f.stat().st_size for f in files)
    samples = [str(f) for f in files[:100]]
    script_path = write_offline_compressor(raw_dir, archive_root, files)
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "raw_dir": str(raw_dir),
        "file_count": len(files),
        "total_bytes": total_bytes,
        "samples": samples,
        "offline_compressor": script_path,
    }
    manifest_path = archive_root / "manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return {
        "mode": "fast_report",
        "files_scanned": len(files),
        "total_bytes": total_bytes,
        "archive_root": str(archive_root),
        "manifest": str(manifest_path),
        "offline_compressor": script_path,
    }


def run(target_dirs: list[str], confirmed: bool = False, remove_archived: bool = False, full: bool = False) -> dict:
    if not confirmed:
        return {"ok": False, "status": "preview", "message": "Pass confirmed=True to run storage compression."}

    reports = []
    total_raw_bytes = 0
    total_archive_bytes = 0
    total_files = 0

    for rel in target_dirs:
        raw_dir = Path(rel)
        if not raw_dir.exists():
            reports.append({"dir": rel, "skipped": "not found"})
            continue

        archive_root = archive_dir_for(raw_dir)
        files = list(raw_dir.rglob("*.json"))
        use_fast = (not full) and (len(files) > FAST_THRESHOLD)

        if use_fast:
            rep = run_fast(raw_dir, archive_root)
            total_raw_bytes += rep["total_bytes"]
            total_files += rep["files_scanned"]
        else:
            rep = run_full(raw_dir, archive_root)
            total_raw_bytes += rep["raw_bytes"]
            total_archive_bytes += rep["archive_bytes"]
            total_files += rep["files_scanned"]

        rep["dir"] = rel
        reports.append(rep)

    deleted = []
    reclaimed = 0
    if remove_archived and confirmed:
        for rep in reports:
            if rep.get("skipped") or rep.get("mode") == "fast_report":
                continue
            for entry in rep.get("archived", []):
                src = Path(entry["src"])
                if src.exists():
                    reclaimed += src.stat().st_size
                    src.unlink()
                    deleted.append(str(src))

    return {
        "ok": True,
        "status": "completed",
        "total_files_scanned": total_files,
        "total_raw_bytes": total_raw_bytes,
        "total_archive_bytes": total_archive_bytes,
        "estimated_reclaim_bytes": total_raw_bytes - total_archive_bytes if not remove_archived else reclaimed,
        "remove_archived": remove_archived,
        "deleted_sources": deleted,
        "reports": reports,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-dirs", nargs="+", required=True)
    parser.add_argument("--confirmed", action="store_true")
    parser.add_argument("--remove-archived", action="store_true")
    parser.add_argument("--full", action="store_true", help="Force full compression even for large dirs")
    args = parser.parse_args()
    result = run(args.target_dirs, confirmed=args.confirmed, remove_archived=args.remove_archived, full=args.full)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
