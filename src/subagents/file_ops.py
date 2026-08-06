"""
file_ops.py — OnenessSystem file-search subagent
Searches local drives for filenames and contents matching case keywords.
"""
import os
import sys
import json
import re
import argparse
from pathlib import Path
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

DEFAULT_KEYWORDS = [
    "rsb", "nordskog", "reliance state bank", "alan bush",
    "foreclosure", "lis pendens", "property", "properties"
]

DEFAULT_ROOTS = [
    str(Path(__file__).resolve().parent.parent.parent / "cases"),
    str(Path(__file__).resolve().parent.parent.parent),
    os.path.expandvars(r"%USERPROFILE%\Downloads"),
]
FAST_CONTENT_EXTS = {".txt", ".md", ".json", ".csv", ".log", ".xml", ".html"}

CONTENT_EXTS = {
    ".txt", ".md", ".json", ".csv", ".log", ".xml", ".html", ".pdf",
    ".docx", ".xlsx", ".eml", ".msg"
}

MAX_BYTES = 50 * 1024 * 1024  # 50 MB per file content read


def normalize(text: str) -> str:
    return re.sub(r"[^\w\s]", " ", text.lower())


def matches(text: str, keywords: list) -> list:
    found = []
    nt = normalize(text)
    for kw in keywords:
        if normalize(kw) in nt:
            found.append(kw)
    return found


def safe_read(path: Path, max_bytes=MAX_BYTES) -> str:
    try:
        size = path.stat().st_size
        if size > max_bytes:
            return "[file too large]"
        if path.suffix.lower() == ".pdf":
            try:
                from pypdf import PdfReader
                reader = PdfReader(str(path))
                return "\n".join(p.extract_text() or "" for p in reader.pages[:10])
            except Exception as e:
                return f"[pdf read error: {e}]"
        # Plain text-ish files
        with open(path, "rb") as f:
            raw = f.read(max_bytes)
        try:
            return raw.decode("utf-8", errors="ignore")
        except Exception:
            return "[binary]"
    except Exception as e:
        return f"[read error: {e}]"


def scan_file(path: Path, keywords: list, content_scan: bool = False) -> dict | None:
    name_hits = list(dict.fromkeys(matches(path.name, keywords) + matches(str(path), keywords)))
    content_hits = []
    snippet = ""
    if content_scan and not name_hits and path.suffix.lower() in FAST_CONTENT_EXTS:
        content = safe_read(path)
        content_hits = matches(content, keywords)
        if content_hits:
            snippet = content[:1000].replace("\n", " ")
    if not name_hits and not content_hits:
        return None
    return {
        "path": str(path),
        "size": path.stat().st_size,
        "modified": datetime.fromtimestamp(path.stat().st_mtime).isoformat(),
        "name_hits": name_hits,
        "content_hits": content_hits,
        "snippet": snippet,
    }


def scan_root(root: str, keywords: list, max_files=50000, content_scan: bool = False) -> list:
    results = []
    root_path = Path(root)
    if not root_path.exists():
        return results
    files = []
    skip_dirs = {"node_modules", ".git", ".venv", "venv", "__pycache__", "publish", "bin", "obj", "logs", "memory", "raw", "archive", "compressed"}
    try:
        for p in root_path.rglob("*"):
            if any(part in skip_dirs for part in p.parts):
                continue
            if p.is_file():
                files.append(p)
            if len(files) >= max_files:
                break
    except Exception as e:
        print(f"[scan error in {root}] {e}")
    with ThreadPoolExecutor(max_workers=8) as ex:
        futures = {ex.submit(scan_file, p, keywords, content_scan): p for p in files}
        for future in as_completed(futures):
            try:
                result = future.result()
                if result:
                    results.append(result)
            except Exception as e:
                pass
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--roots", nargs="+", default=DEFAULT_ROOTS)
    parser.add_argument("--keywords", nargs="+", default=DEFAULT_KEYWORDS)
    parser.add_argument("--out", "--output", default="memory/subagents/file_ops_results.json")
    parser.add_argument("--max-files", type=int, default=12000)
    parser.add_argument("--content", action="store_true", help="Enable slower content scanning")
    args = parser.parse_args()

    all_results = []
    for root in args.roots:
        print(f"[scanning] {root}")
        hits = scan_root(root, args.keywords, args.max_files, content_scan=args.content)
        all_results.extend(hits)
        print(f"[found] {len(hits)} hits in {root}")

    all_results.sort(key=lambda x: x["modified"], reverse=True)

    findings = []
    high_value = {"rsb", "nordskog", "reliance state bank", "alan bush", "foreclosure", "lis pendens"}
    for hit in all_results[:20]:
        all_hits = set([h.lower() for h in (hit["name_hits"] + hit["content_hits"])])
        score = 0.5
        if all_hits & high_value:
            score = 0.9
        title = hit["path"].replace("\\", "/").split("/")[-1]
        findings.append({
            "type": "file_keyword_hit",
            "source": "file_ops",
            "title": f"{title}: {', '.join(hit['name_hits'] + hit['content_hits'])}",
            "description": hit.get("snippet", "")[:200],
            "risk_score": score,
            "roi_score": 3.0,
            "path": hit["path"],
            "hits": hit["name_hits"] + hit["content_hits"],
        })

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "agent": "file_ops",
            "status": "ok",
            "count": len(findings),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "telemetry": {
                "total_hits": len(all_results),
                "keywords": args.keywords,
                "roots": args.roots,
            },
            "findings": findings,
            "hits": all_results,
        }, f, indent=2)
    print(f"[saved] {out_path}")
    print(json.dumps({
        "agent": "file_ops",
        "status": "ok",
        "wrote": str(out_path),
        "count": len(findings),
        "total_hits": len(all_results),
    }))


if __name__ == "__main__":
    main()
