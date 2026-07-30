#!/usr/bin/env python3
"""
github_public_intel_extractor.py

Lawful public GitHub repository extractor for legal-tech / data-workflow research.

Use only with:
- Public repositories, or
- Private repositories you are authorized to access with your own token.

What it does:
- Reads repository metadata and default branch.
- Pulls the recursive file tree from the GitHub REST API.
- Downloads selected text files below a size limit.
- Produces a Markdown intelligence brief with repository map, license signal,
  candidate reusable files, and extracted text snippets.

What it does NOT do:
- It does not bypass access controls.
- It does not run repository code.
- It does not determine whether code is legally reusable. Review the license.
"""

from __future__ import annotations

import argparse
import base64
import dataclasses
import os
import re
import sys
import textwrap
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse

import requests


DEFAULT_EXTENSIONS = {
    ".md", ".txt", ".py", ".js", ".ts", ".tsx", ".jsx", ".json", ".yaml", ".yml",
    ".toml", ".ini", ".cfg", ".rst", ".html", ".css", ".sql", ".sh", ".ps1",
}
SKIP_DIR_MARKERS = {
    "/.git/", "/node_modules/", "/dist/", "/build/", "/.venv/", "/venv/",
    "/__pycache__/", "/.pytest_cache/", "/.next/", "/coverage/",
}
SKIP_FILE_NAMES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "poetry.lock",
}


@dataclasses.dataclass(frozen=True)
class RepoRef:
    owner: str
    repo: str


def parse_github_url(value: str) -> RepoRef:
    value = value.strip()
    if value.startswith("git@github.com:"):
        value = value.replace("git@github.com:", "https://github.com/", 1)
    parsed = urlparse(value)
    if parsed.netloc.lower() != "github.com":
        raise ValueError("Expected a github.com repository URL.")
    parts = [p for p in parsed.path.strip("/").split("/") if p]
    if len(parts) < 2:
        raise ValueError("Expected a repository URL like https://github.com/owner/repo")
    repo = parts[1].removesuffix(".git")
    return RepoRef(owner=parts[0], repo=repo)


def github_headers() -> dict[str, str]:
    headers = {"Accept": "application/vnd.github+json"}
    token = os.getenv("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def api_get(url: str, *, timeout: int = 30) -> dict:
    response = requests.get(url, headers=github_headers(), timeout=timeout)
    if response.status_code == 403 and "rate limit" in response.text.lower():
        raise RuntimeError("GitHub API rate limit reached. Set GITHUB_TOKEN and retry.")
    if response.status_code == 404:
        raise RuntimeError("Repository or file not found, or you are not authorized.")
    response.raise_for_status()
    return response.json()


def should_keep(path: str, extensions: set[str]) -> bool:
    normalized = "/" + path.replace("\\", "/")
    if any(marker in normalized for marker in SKIP_DIR_MARKERS):
        return False
    if Path(path).name in SKIP_FILE_NAMES:
        return False
    return Path(path).suffix.lower() in extensions


def truncate(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    return text[:max_chars] + "\n\n[TRUNCATED]"


def download_text_file(owner: str, repo: str, path: str, ref: str, max_bytes: int) -> str | None:
    safe_path = path.replace(" ", "%20")
    data = api_get(f"https://api.github.com/repos/{owner}/{repo}/contents/{safe_path}?ref={ref}")
    size = int(data.get("size") or 0)
    if size > max_bytes:
        return None
    content = data.get("content")
    encoding = data.get("encoding")
    if not content or encoding != "base64":
        return None
    raw = base64.b64decode(content, validate=False)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("utf-8", errors="replace")


def classify_file(path: str) -> str:
    lower = path.lower()
    if lower.endswith("readme.md") or "/readme" in lower:
        return "README / overview"
    if "license" in Path(path).name.lower():
        return "License signal"
    if "test" in lower or "spec" in lower:
        return "Test / behavior clues"
    if lower.endswith((".py", ".ts", ".tsx", ".js", ".jsx")):
        return "Source code"
    if lower.endswith((".json", ".yaml", ".yml", ".toml")):
        return "Config / dependency signal"
    return "Documentation / text"


def build_markdown(
    repo: RepoRef,
    repo_meta: dict,
    tree_items: list[dict],
    extracted: list[tuple[str, str]],
    max_chars_per_file: int,
) -> str:
    license_info = repo_meta.get("license") or {}
    license_name = license_info.get("spdx_id") or license_info.get("name") or "No license detected by API"

    lines: list[str] = []
    lines.append(f"# Public GitHub Intelligence Brief: {repo.owner}/{repo.repo}")
    lines.append("")
    lines.append("## Safety and Legal Boundary")
    lines.append("Use this brief for lawful research only. Do not copy, reuse, or commercialize code without license review. Do not run unknown code without security review.")
    lines.append("")
    lines.append("## Repository Metadata")
    lines.append(f"- Description: {repo_meta.get('description') or 'Not provided'}")
    lines.append(f"- Default branch: {repo_meta.get('default_branch')}")
    lines.append(f"- Visibility: {repo_meta.get('visibility', 'unknown')}")
    lines.append(f"- License signal: {license_name}")
    lines.append(f"- Stars: {repo_meta.get('stargazers_count', 'unknown')}")
    lines.append(f"- Forks: {repo_meta.get('forks_count', 'unknown')}")
    lines.append(f"- Open issues: {repo_meta.get('open_issues_count', 'unknown')}")
    lines.append("")
    lines.append("## Repository Map")
    for item in tree_items[:500]:
        if item.get("type") == "blob":
            lines.append(f"- {item.get('path')}")
    if len(tree_items) > 500:
        lines.append(f"- ... {len(tree_items) - 500} more tree entries omitted")
    lines.append("")
    lines.append("## Extracted Files")
    if not extracted:
        lines.append("No matching text files were extracted under the configured limits.")
    for path, text in extracted:
        lines.append("")
        lines.append(f"### {path}")
        lines.append(f"- Classification: {classify_file(path)}")
        lines.append("")
        lines.append("```")
        lines.append(truncate(text, max_chars_per_file))
        lines.append("```")
    lines.append("")
    lines.append("## Research Questions for Reuse")
    lines.extend([
        "- What license governs reuse?",
        "- Which files are documentation versus executable code?",
        "- What security risks exist before running or adapting this repository?",
        "- Which functions are useful as inspiration without copying protected material?",
        "- What parts need attorney review, privacy review, or security review before deployment?",
    ])
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Extract a lawful intelligence brief from a public or authorized GitHub repository."
    )
    parser.add_argument("repo_url", help="Repository URL, e.g. https://github.com/owner/repo")
    parser.add_argument("--out", default="repo_intel_brief.md", help="Output Markdown path")
    parser.add_argument("--max-files", type=int, default=40, help="Maximum matching files to download")
    parser.add_argument("--max-bytes", type=int, default=160_000, help="Skip files larger than this")
    parser.add_argument("--max-chars-per-file", type=int, default=20_000, help="Truncate each extracted file to this many characters")
    parser.add_argument(
        "--extensions",
        default=",".join(sorted(DEFAULT_EXTENSIONS)),
        help="Comma-separated file extensions to include",
    )
    args = parser.parse_args(argv)

    repo = parse_github_url(args.repo_url)
    extensions = {ext.strip().lower() for ext in args.extensions.split(",") if ext.strip()}
    extensions = {ext if ext.startswith(".") else "." + ext for ext in extensions}

    repo_meta = api_get(f"https://api.github.com/repos/{repo.owner}/{repo.repo}")
    default_branch = repo_meta["default_branch"]

    branch = api_get(f"https://api.github.com/repos/{repo.owner}/{repo.repo}/branches/{default_branch}")
    tree_sha = branch["commit"]["commit"]["tree"]["sha"]
    tree = api_get(f"https://api.github.com/repos/{repo.owner}/{repo.repo}/git/trees/{tree_sha}?recursive=1")
    tree_items = tree.get("tree", [])

    candidates = [
        item["path"] for item in tree_items
        if item.get("type") == "blob" and should_keep(item.get("path", ""), extensions)
    ]
    priority = sorted(
        candidates,
        key=lambda p: (
            0 if Path(p).name.lower().startswith("readme") else 1,
            0 if "license" in Path(p).name.lower() else 1,
            0 if Path(p).suffix.lower() in {".md", ".txt", ".rst"} else 1,
            p.lower(),
        ),
    )

    extracted: list[tuple[str, str]] = []
    for path in priority[: args.max_files]:
        text = download_text_file(repo.owner, repo.repo, path, default_branch, args.max_bytes)
        if text is not None:
            extracted.append((path, text))

    markdown = build_markdown(repo, repo_meta, tree_items, extracted, args.max_chars_per_file)
    out_path = Path(args.out)
    out_path.write_text(markdown, encoding="utf-8")
    print(f"Wrote {out_path.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
