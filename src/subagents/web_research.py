"""
web_research.py — OnenessSystem web-search subagent
Uses Playwright to search the public web for case keywords.
"""
import os
import sys
import json
import re
import argparse
import asyncio
from pathlib import Path
from datetime import datetime
from playwright.async_api import async_playwright

DEFAULT_QUERIES = [
    '"Reliance State Bank" Nordskog foreclosure',
    '"Alan Bush" Nordskog property',
    '"Lis Pendens" Nordskog "Reliance State Bank"',
    'Nordskog foreclosure case RSB',
    '"Reliance State Bank" foreclosure',
]

SEARCH_URL = "https://www.google.com/search?q={q}"


def slugify(q: str) -> str:
    return re.sub(r"[^\w]", "_", q.lower())[:60]


async def search_one(query: str, timeout: int = 30) -> dict:
    result = {
        "query": query,
        "timestamp": datetime.utcnow().isoformat(),
        "results": [],
        "error": None,
    }
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        try:
            context = await browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
            )
            page = await context.new_page()
            url = SEARCH_URL.format(q=query.replace(" ", "+"))
            await page.goto(url, wait_until="domcontentloaded", timeout=timeout * 1000)
            await asyncio.sleep(2)
            # Extract search result links and snippets
            items = await page.query_selector_all("div.g, div[data-hveid], .g, [data-ved]")
            for item in items[:10]:
                try:
                    a = await item.query_selector("a[href]")
                    title_el = await item.query_selector("h3")
                    snippet_els = await item.query_selector_all("span")
                    href = await a.get_attribute("href") if a else None
                    title = await title_el.inner_text() if title_el else ""
                    snippet = " ".join([await s.inner_text() for s in snippet_els if await s.is_visible()][:3])
                    if href and href.startswith("http"):
                        result["results"].append({
                            "url": href,
                            "title": title.strip(),
                            "snippet": snippet.strip(),
                        })
                except Exception:
                    continue
        except Exception as e:
            result["error"] = str(e)
        finally:
            await browser.close()
    return result


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--queries", nargs="+", default=DEFAULT_QUERIES)
    parser.add_argument("--out", "--output", default="memory/subagents/web_research_results.json")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    all_results = []
    for q in args.queries:
        print(f"[web search] {q}")
        res = await search_one(q, args.timeout)
        all_results.append(res)
        print(f"[found] {len(res['results'])} results")

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({
            "timestamp": datetime.utcnow().isoformat(),
            "queries": args.queries,
            "total_queries": len(all_results),
            "results": all_results,
        }, f, indent=2)
    print(f"[saved] {out_path}")
    print(json.dumps({
        "agent": "web_research",
        "status": "ok" if not any(r.get("error") for r in all_results) else "partial",
        "wrote": str(out_path),
        "count": sum(len(r["results"]) for r in all_results),
        "total_queries": len(all_results),
    }))


if __name__ == "__main__":
    asyncio.run(main())
