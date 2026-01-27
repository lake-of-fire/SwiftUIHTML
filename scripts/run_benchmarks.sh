#!/usr/bin/env bash
set -euo pipefail

workdir="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d /tmp/swiftuihtml-bench.XXXXXX)"
log="$tmpdir/bench.log"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cd "$workdir"

swift test --filter PerformanceTests >"$log" 2>&1

echo "Benchmark summary:"
rg -n "baseline|optimized|enabled|median" "$log" | sed -E 's/^[0-9]+://'
