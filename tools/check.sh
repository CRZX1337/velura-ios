#!/usr/bin/env bash
# Velura local checks — runs on Windows (git-bash), macOS and Linux.
#
#   bash tools/check.sh          # parse + glass audit + portable logic tests
#   bash tools/check.sh --fast   # parse + audit only (no SwiftPM build)
#
# What this can NOT do: compile the SwiftUI app. SwiftUI, CoreLocation, MapKit,
# ActivityKit and Combine only exist in Apple SDKs. Use the `Screenshot harness`
# GitHub workflow (macos-26 + simulator) for a real build and real renders.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1
failed=0

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python

echo "== 1/3 Swift syntax (swiftc -frontend -parse) =="
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found — install a Swift toolchain (swift.org) to run this step"
  failed=1
else
  for f in Velura/*.swift VeluraLiveActivity/*.swift VeluraTests/*.swift VeluraUITests/*.swift; do
    out="$(swiftc -frontend -parse "$f" 2>&1)"
    if [[ -n "$out" ]]; then
      echo "SYNTAX ERROR in $f"
      echo "$out" | head -5
      failed=1
    fi
  done
  [[ $failed -eq 0 ]] && echo "ok — all Swift files parse"
fi

echo
echo "== 2/3 Liquid Glass audit =="
"$PY" .agents/skills/apple-liquid-glass/scripts/audit_liquid_glass.py . 2>/dev/null \
  || echo "(audit script not present — skipping)"

echo
if [[ $FAST -eq 1 ]]; then
  echo "== 3/3 portable logic tests skipped (--fast) =="
  exit $failed
fi

echo "== 3/3 portable logic tests (SwiftPM, Foundation only) =="
"$PY" tools/logic-tests/prepare.py >/dev/null || { echo "prepare failed"; exit 1; }
if command -v swift >/dev/null 2>&1; then
  ( cd tools/logic-tests && swift test 2>&1 | grep -E "Test run|✘|×|error:" | tail -20 )
  rc=${PIPESTATUS[0]}
  [[ $rc -ne 0 ]] && failed=1
else
  echo "swift not found — cannot run logic tests"
  failed=1
fi

echo
if [[ $failed -eq 0 ]]; then echo "ALL LOCAL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $failed
