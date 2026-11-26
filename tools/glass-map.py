#!/usr/bin/env python3
"""Generate a Liquid Glass layer map for Velura from the Swift sources.

Every surface in the app is either chrome (floating, glass) or content (a plain
fill). This script counts both per file so drift is visible without reading 13k
lines: a screen whose content cards start turning into glass cards shows up here
before it shows up in a screenshot.

    python tools/glass-map.py            # writes .harness/glass-map.html
    python tools/glass-map.py --json     # prints the raw counts
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "Velura"
OUT = ROOT / ".harness" / "glass-map.html"

GLASS = {
    "glassCard": re.compile(r"\.veluraGlassCard\("),
    "glassCapsule": re.compile(r"\.veluraGlassCapsule\("),
    "glassCircle": re.compile(r"\.veluraGlassCircle\("),
}
CONTENT = {
    "contentCard": re.compile(r"\.veluraContentCard\("),
    "contentCapsule": re.compile(r"\.veluraContentCapsule\("),
}
SYSTEM_GLASS = re.compile(r"buttonStyle\(\.glass|glassProminent")
RISK = {
    "stroke on glass": re.compile(r"veluraGlass\w*\([^)]*stroke:"),
    "opacity on glass": re.compile(r"veluraGlass\w*\([^)]*\)\s*\.opacity\("),
    "material fallback": re.compile(r"ultraThinMaterial|thinMaterial|regularMaterial"),
    "legacy toolbar": re.compile(r"\.toolbar\(\.(visible|hidden), for:"),
    "legacy tabItem": re.compile(r"\.tabItem\s*\{"),
}

SCREENS = {
    "SpeedDashboardView.swift": "Speed dashboard",
    "DriveModeView.swift": "Drive Mode cockpit",
    "AccelerationTestView.swift": "Acceleration test",
    "DriveHistoryView.swift": "Drives · detail · route",
    "DrivingInsightsView.swift": "Driving insights",
    "ContentView.swift": "Shell · tabs · settings · gauge",
    "FirstLaunchSetupView.swift": "First launch",
    "ActiveDriveView.swift": "Live route (map)",
    "DashboardLayoutSettings.swift": "Layout settings",
    "VeluraGlass.swift": "Glass primitives",
}


def scan() -> list[dict]:
    rows = []
    for path in sorted(APP.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        glass = {k: len(p.findall(text)) for k, p in GLASS.items()}
        content = {k: len(p.findall(text)) for k, p in CONTENT.items()}
        risks = {k: len(p.findall(text)) for k, p in RISK.items()}
        rows.append(
            {
                "file": path.name,
                "title": SCREENS.get(path.name, path.stem),
                "lines": text.count("\n") + 1,
                "glass": glass,
                "glass_total": sum(glass.values()),
                "system_glass": len(SYSTEM_GLASS.findall(text)),
                "content": content,
                "content_total": sum(content.values()),
                "risks": risks,
                "risk_total": sum(risks.values()),
            }
        )
    return rows


def html(rows: list[dict]) -> str:
    total_glass = sum(r["glass_total"] for r in rows)
    total_content = sum(r["content_total"] for r in rows)
    total_risks = sum(r["risk_total"] for r in rows)
    total_system = sum(r["system_glass"] for r in rows)

    cards = []
    for r in rows:
        if r["glass_total"] == 0 and r["content_total"] == 0 and r["system_glass"] == 0:
            continue
        badges = []
        if r["glass_total"]:
            badges.append(f'<span class="b glass">{r["glass_total"]} glass</span>')
        if r["system_glass"]:
            badges.append(f'<span class="b sys">{r["system_glass"]} system</span>')
        if r["content_total"]:
            badges.append(f'<span class="b content">{r["content_total"]} content</span>')
        if r["risk_total"]:
            badges.append(f'<span class="b risk">{r["risk_total"]} risk</span>')
        risk_lines = ""
        for name, count in r["risks"].items():
            if count:
                risk_lines += f"<li>{name} × {count}</li>"
        cards.append(
            f"""<article class="card">
  <header><h3>{r['title']}</h3><code>{r['file']}</code></header>
  <div class="badges">{''.join(badges)}</div>
  <p class="lines">{r['lines']} lines</p>
  {f'<ul class="risks">{risk_lines}</ul>' if risk_lines else ''}
</article>"""
        )

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Velura — Liquid Glass layer map</title>
<style>
  :root {{ color-scheme: dark light; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; font: 14px/1.5 -apple-system, "SF Pro Text", system-ui, sans-serif;
         background: #0b0f14; color: #e8edf3; padding: 20px 22px 28px; }}
  h1 {{ font-size: 15px; letter-spacing: .18em; text-transform: uppercase; margin: 0 0 4px;
        color: #8aa4bd; font-weight: 600; }}
  .sub {{ margin: 0 0 18px; color: #7d8ea1; font-size: 12px; max-width: 62ch; }}
  .totals {{ display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 18px; }}
  .tot {{ border: 1px solid #1e2b38; border-radius: 12px; padding: 10px 14px; min-width: 104px;
          background: linear-gradient(180deg, #131b24, #0f151c); }}
  .tot b {{ display: block; font-size: 22px; line-height: 1.1; font-variant-numeric: tabular-nums; }}
  .tot span {{ font-size: 11px; color: #7d8ea1; letter-spacing: .04em; text-transform: uppercase; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 10px; }}
  .card {{ border: 1px solid #1e2b38; border-radius: 14px; padding: 12px 13px;
           background: linear-gradient(180deg, #121a23, #0d1319); }}
  .card header {{ display: flex; flex-direction: column; gap: 1px; margin-bottom: 8px; }}
  .card h3 {{ margin: 0; font-size: 13px; font-weight: 600; }}
  .card code {{ font-size: 11px; color: #64798d; }}
  .badges {{ display: flex; flex-wrap: wrap; gap: 5px; }}
  .b {{ font-size: 10.5px; padding: 2px 7px; border-radius: 999px; letter-spacing: .03em;
        border: 1px solid transparent; font-variant-numeric: tabular-nums; }}
  .b.glass {{ color: #7fd4ff; background: #0d2a3a; border-color: #16455f; }}
  .b.sys {{ color: #9d8cff; background: #1a1733; border-color: #2f2a55; }}
  .b.content {{ color: #94a3b3; background: #161d25; border-color: #232f3b; }}
  .b.risk {{ color: #ffb4a8; background: #331a17; border-color: #5a2a24; }}
  .lines {{ margin: 8px 0 0; font-size: 11px; color: #64798d; }}
  .risks {{ margin: 6px 0 0; padding-left: 16px; font-size: 11.5px; color: #ffb4a8; }}
  footer {{ margin-top: 18px; font-size: 11px; color: #64798d; }}
</style></head>
<body>
  <h1>Velura · Liquid Glass layer map</h1>
  <p class="sub">Chrome floats on glass, content stays flat. Counts are read straight from the
  Swift sources — a screen whose content starts wearing glass shows up here first.</p>
  <div class="totals">
    <div class="tot"><b>{total_system}</b><span>native glass buttons</span></div>
    <div class="tot"><b>{total_glass}</b><span>custom glass surfaces</span></div>
    <div class="tot"><b>{total_content}</b><span>content surfaces</span></div>
    <div class="tot"><b>{total_risks}</b><span>open risks</span></div>
  </div>
  <div class="grid">{''.join(cards)}</div>
  <footer>Generated by tools/glass-map.py · text-only evidence, not a render</footer>
</body></html>"""


def main() -> int:
    rows = scan()
    if "--json" in sys.argv:
        print(json.dumps(rows, indent=2))
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html(rows), encoding="utf-8")
    print(OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
