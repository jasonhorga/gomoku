#!/usr/bin/env bash
# Build the DiffTestCLI binary for the host platform (used by
# run_diff_tests.py to exercise the Swift port against Python ground
# truth). Not shipped — CI-only.

set -euo pipefail
cd "$(dirname "$0")"

OUT="${OUT:-./diff_test_cli}"

xcrun swiftc \
	-O \
	-parse-as-library \
	-o "$OUT" \
	../Sources/GameLogic.swift \
	../Sources/PatternEval.swift \
	../Sources/VcfSearch.swift \
	../Sources/VctSearch.swift \
	../Sources/MCTSEngine.swift \
	../Sources/CoreMLAdapter.swift \
	DiffTestCLI.swift

echo "Built $OUT"
"$OUT" --version 2>/dev/null || true
