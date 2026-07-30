"""Avatar Generator - chart the user's operational signature as a vector avatar."""
from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("ONENESS_SYSTEM_ROOT", r"C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem"))
SIG_DIR = ROOT / "memory" / "signatures"
AVATAR_DIR = SIG_DIR / "avatars"


def _load_latest() -> dict:
    path = SIG_DIR / "latest_signature.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def _color_from_hash(h: str) -> tuple[str, str]:
    def hex2(i):
        return f"#{h[i:i+6]}"
    return hex2(0), hex2(6)


def generate_avatar(signature: dict | None = None) -> Path:
    sig = signature or _load_latest()
    h = sig.get("hash", "0" * 32)
    freq = sig.get("frequency", {}).get("band", 852)
    gate = sig.get("gates", {}).get("current_gate", 1)
    glyph_rows = sig.get("glyph", "").splitlines()

    c1, c2 = _color_from_hash(h)

    rings = []
    cx, cy = 128, 128
    for y, row in enumerate(glyph_rows[:4]):
        for x, ch in enumerate(row.strip()[:4]):
            r = 20 + (x + y) * 14
            fill = c1 if ch == "◉" else c2
            rings.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" opacity="0.6" />')

    rings_block = '\n  '.join(rings)
    freq_ring = f'<circle cx="{cx}" cy="{cy}" r="{90 + gate * 4}" fill="none" stroke="{c1}" stroke-width="{gate}" />'
    center_text = f'<text x="{cx}" y="{cy+5}" text-anchor="middle" font-size="14" fill="#ffffff" font-family="monospace">{freq}</text>'

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#050505" />
  {freq_ring}
  {rings_block}
  {center_text}
  <text x="128" y="240" text-anchor="middle" font-size="10" fill="#888888" font-family="monospace">{h[:16]}</text>
</svg>"""

    AVATAR_DIR.mkdir(parents=True, exist_ok=True)
    out = AVATAR_DIR / f"avatar_{h[:16]}.svg"
    out.write_text(svg, encoding="utf-8")
    return out


if __name__ == "__main__":
    out = generate_avatar()
    print(out)
