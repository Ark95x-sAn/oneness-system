"""Fallback document indexer - lightweight TF-IDF memory layer.

Runs when Qdrant/Docker are unavailable. Uses numpy only.
"""
from __future__ import annotations

import json
import math
import os
import re
from collections import Counter
from pathlib import Path
from typing import List, Tuple

import numpy as np

ROOT = Path(os.environ.get("ONENESS_SYSTEM_ROOT", r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"))
INDEX_DIR = ROOT / "memory" / "qdrant_fallback"
INDEX_DIR.mkdir(parents=True, exist_ok=True)

DOC_DIRS = [
    ROOT / "memory" / "legal",
    ROOT / "memory" / "polymarket",
    ROOT / "memory" / "activation",
    ROOT / "memory" / "analysis",
]

class SimpleIndexer:
    def __init__(self):
        self.docs: List[dict] = []
        self.vocab: dict[str, int] = {}
        self.idf: dict[str, float] = {}
        self.vectors: List[np.ndarray] = []

    def tokenize(self, text: str) -> List[str]:
        return re.findall(r"[a-zA-Z0-9_]{2,}", text.lower())

    def collect_documents(self) -> List[dict]:
        docs = []
        for d in DOC_DIRS:
            if not d.exists():
                continue
            for p in d.rglob("*"):
                if not p.is_file() or p.stat().st_size > 2_000_000:
                    continue
                try:
                    text = p.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    continue
                docs.append({
                    "path": str(p),
                    "name": p.name,
                    "text": text[:20000],
                    "tokens": self.tokenize(text),
                })
        return docs

    def build(self):
        self.docs = self.collect_documents()
        token_counts = Counter()
        for d in self.docs:
            token_counts.update(set(d["tokens"]))
        self.vocab = {t: i for i, (t, _) in enumerate(token_counts.most_common(5000))}
        n = len(self.docs)
        df = Counter()
        for d in self.docs:
            df.update(set(d["tokens"]))
        self.idf = {t: math.log((n + 1) / (df.get(t, 1) + 1)) for t in self.vocab}
        self.vectors = []
        for d in self.docs:
            vec = np.zeros(len(self.vocab))
            counts = Counter(d["tokens"])
            for t, c in counts.items():
                if t in self.vocab:
                    vec[self.vocab[t]] = c * self.idf.get(t, 0)
            norm = np.linalg.norm(vec)
            if norm > 0:
                vec = vec / norm
            self.vectors.append(vec)
        self.save()

    def save(self):
        data = {
            "vocab": self.vocab,
            "idf": self.idf,
            "documents": [{"path": d["path"], "name": d["name"]} for d in self.docs],
            "vectors": [v.tolist() for v in self.vectors],
        }
        (INDEX_DIR / "index.json").write_text(json.dumps(data), encoding="utf-8")

    def search(self, query: str, top_k: int = 5) -> List[Tuple[str, float]]:
        q_tokens = self.tokenize(query)
        q_vec = np.zeros(len(self.vocab))
        counts = Counter(q_tokens)
        for t, c in counts.items():
            if t in self.vocab:
                q_vec[self.vocab[t]] = c * self.idf.get(t, 0)
        norm = np.linalg.norm(q_vec)
        if norm > 0:
            q_vec = q_vec / norm
        scores = []
        for i, v in enumerate(self.vectors):
            sim = float(np.dot(q_vec, v))
            scores.append((self.docs[i]["path"], sim))
        scores.sort(key=lambda x: x[1], reverse=True)
        return scores[:top_k]

if __name__ == "__main__":
    idx = SimpleIndexer()
    idx.build()
    print(f"Indexed {len(idx.docs)} documents. Query with idx.search('your question').")
    for path, score in idx.search("Polymarket bot Kelly EV", top_k=3):
        print(f"{score:.3f} {path}")
