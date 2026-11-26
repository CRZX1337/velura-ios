#!/usr/bin/env python3
"""Copy the platform-independent slice of Velura into the SwiftPM harness.

The app target needs SwiftUI/CoreLocation/Combine, none of which exist on
Windows or Linux. These files are pure Foundation, so they can be compiled and
executed anywhere a Swift toolchain is installed.

Run from the repository root:  python tools/logic-tests/prepare.py
"""
from __future__ import annotations

import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "Velura"
DEST = pathlib.Path(__file__).resolve().parent / "Sources" / "VeluraCore"

PORTABLE_FILES = [
    "DriveModels.swift",
    "DriveFileStorage.swift",
    "DrivingInsightsCalculator.swift",
    "GPXExporter.swift",
]


def main() -> int:
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)

    missing = []
    for name in PORTABLE_FILES:
        src = APP / name
        if not src.exists():
            missing.append(name)
            continue
        shutil.copy2(src, DEST / name)
        print(f"copied {name}")

    if missing:
        print("missing source files: " + ", ".join(missing))
        return 1
    print(f"VeluraCore sources ready in {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
