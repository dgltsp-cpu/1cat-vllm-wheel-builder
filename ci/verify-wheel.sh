#!/usr/bin/env bash
# Reproduce the official 1.5.0 wheel acceptance gates
# (docs/design/sm70_v100_migration_control.md):
#   - the expected native libraries are present
#   - no RPATH / RUNPATH anywhere, so no build-host path leaks into the wheel
#   - no hard-coded build-host string such as /home/<user>
#   - sha256 recorded next to the wheel
set -euo pipefail

OUT="${1:-out}"
cd "$OUT"

WHEEL="$(ls -1 ./*.whl | head -n1)"
echo "Wheel: $WHEEL"
ls -l "$WHEEL"

rm -rf extracted
mkdir -p extracted
unzip -q "$WHEEL" -d extracted

echo "=== native libraries ==="
mapfile -t SO_FILES < <(find extracted -type f -name '*.so' | sort)
printf '%s\n' "${SO_FILES[@]}"
echo "count: ${#SO_FILES[@]}"

fail=0

echo "=== RPATH / RUNPATH check ==="
for so in "${SO_FILES[@]}"; do
  dyn="$(readelf -d "$so" 2>/dev/null | grep -E 'RPATH|RUNPATH' || true)"
  if [ -n "$dyn" ]; then
    echo "::error::dynamic section entries in $so"
    echo "$dyn"
    fail=1
  fi
done

echo "=== build-host path check ==="
if grep -rlE '/home/[a-zA-Z0-9._-]+/|/data/minimax|miniconda3|/work/src' extracted 2>/dev/null | head -n 20; then
  echo "::error::build-host path leaked into the wheel"
  fail=1
else
  echo "no build-host paths found"
fi

echo "=== metadata ==="
unzip -p "$WHEEL" '*.dist-info/METADATA' | grep -E '^(Name|Version|Requires-Python):|instrumentator'
unzip -p "$WHEEL" '*.dist-info/WHEEL' | grep -E '^(Tag|Root-Is-Purelib):'

echo "=== sha256 ==="
sha256sum ./*.whl | tee "$(basename "$WHEEL" .whl).sha256"

if [ "$fail" -ne 0 ]; then
  echo "::error::wheel verification failed"
  exit 1
fi
echo "wheel verification passed"
