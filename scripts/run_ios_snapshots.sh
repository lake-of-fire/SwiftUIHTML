#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'USAGE'
Usage: $0 <mode>
Modes:
  all          - run all snapshot tests
  htmlbasic    - run only HTMLBasicTests snapshots
  single       - run exactly one snapshot test (requires TEST_ONLY or second arg)
USAGE
  exit 1
}
if [ $# -lt 1 ]; then usage; fi
mode=$1
target_test=""
if [ "$mode" = "single" ]; then
  if [ $# -ge 2 ]; then
    target_test=$2
  elif [ -n "${TEST_ONLY:-}" ]; then
    target_test=${TEST_ONLY}
  else
    echo "single mode requires TEST_ONLY env or argument" >&2
    exit 1
  fi
fi
find_simulator_uudid() {
  python3 - <<'PY'
import json, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted", "-j"], text=True)
data = json.loads(raw)
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("state") == "Booted" and device.get("isAvailable", True):
            print(device.get("udid"))
            sys.exit(0)
sys.exit(1)
PY
}
if ! sim_udid=$(find_simulator_uudid); then
  echo "No booted simulator found. Set SIM_ID or boot one." >&2
  exit 1
fi
cmd_args=("-project" "SwiftUIHTMLExample.xcodeproj" "-scheme" "SwiftUIHTMLExample" "-testPlan" "SwiftUIHTMLExample" "-destination" "platform=iOS Simulator,id=$sim_udid" "-configuration" "Debug" "-parallel-testing-enabled" "NO" "-maximum-concurrent-test-simulator-destinations" "1" "-maximum-parallel-testing-workers" "1" "-resultBundlePath" "/tmp/swiftuihtml-ios-latest.xcresult")
case "$mode" in
  all)
    report_prefix="/tmp/swiftuihtml-ios-snapshot-report"
    snapshot_root="/tmp/swiftuihtml-ios-artifacts"
    log_path="/tmp/swiftuihtml-ios-xcodebuild.log"
    ;;
  htmlbasic)
    report_prefix="/tmp/swiftuihtml-ios-snapshot-report"
    snapshot_root="/tmp/swiftuihtml-ios-artifacts"
    log_path="/tmp/swiftuihtml-ios-htmlbasic.log"
    cmd_args+=("-only-testing:SwiftUIHTMLExampleTests/HTMLBasicTests")
    ;;
  single)
    report_prefix="/tmp/swiftuihtml-ios-single-report"
    snapshot_root="/tmp/swiftuihtml-ios-artifacts-single"
    log_path="/tmp/swiftuihtml-ios-single.log"
    cmd_args+=("-only-testing:${target_test}")
    ;;
  *)
    usage
    ;;
esac
echo "Launching tests on simulator $sim_udid"
rm -rf "$snapshot_root" "$log_path"
rm -rf /tmp/swiftuihtml-ios-latest.xcresult
set +e
SWIFTUIHTML_SNAPSHOT_RECORD=1 SNAPSHOT_ARTIFACTS="$snapshot_root" xcodebuild test "${cmd_args[@]}" | tee "$log_path" | xcbeautify --renderer terminal
status=$?
set -e
artifact_root=$(grep -a -m1 "artifactsRoot=" "$log_path" | sed -n 's/.*artifactsRoot=//p' | head -n 1)
if [[ -n "${artifact_root:-}" && -d "$artifact_root" ]]; then
  mkdir -p "$snapshot_root"
  rm -rf "${snapshot_root:?}/HTMLBasicTests"
  cp -a "$artifact_root/HTMLBasicTests" "$snapshot_root/."
fi
python3 scripts/snapshot_report.py --artifacts "$snapshot_root/HTMLBasicTests" --baseline "SwiftUIHTMLExampleTests/__Snapshots__/HTMLBasicTests" --title "SwiftUIHTML iOS Snapshot Report" --out-prefix "$report_prefix" --test-log "$log_path"
exit $status
