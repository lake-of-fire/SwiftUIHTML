#!/bin/sh
set -euo pipefail
root="${1:-/tmp/swiftuihtml-ios-artifacts}"
# Find the newest artifacts directory under any simulator app container.
base="$HOME/Library/Developer/CoreSimulator/Devices"
latest_path=""
latest_mtime=0
while IFS= read -r -d '' dir; do
  mtime=$(stat -f %m "$dir" 2>/dev/null || echo 0)
  if [ "$mtime" -gt "$latest_mtime" ]; then
    latest_mtime="$mtime"
    latest_path="$dir"
  fi
done <<EOF
$(find "$base" -path "*/data/Containers/Data/Application/*/Documents/swiftuihtml-ios-artifacts" -type d -print0 2>/dev/null)
EOF

if [ -z "$latest_path" ]; then
  echo "No simulator artifacts found."
  exit 1
fi

mkdir -p "$root"
rsync -a "$latest_path/" "$root/"
echo "Copied iOS artifacts from: $latest_path"
echo "Into: $root"
