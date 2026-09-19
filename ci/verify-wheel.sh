#!/usr/bin/env bash
# Reproduce the official 1.5.0 wheel acceptance gates
# (docs/design/sm70_v100_migration_control.md).
#
# HARD  no RPATH / RUNPATH on any native library. The 1.5.0 release was blocked
#       once because a build host without patchelf baked its Conda prefix into
#       the bundled Flash-V100 extensions.
# HARD  the expected SM70 native libraries are present.
# NOTE  absolute source paths compiled in through __FILE__ (TORCH_CHECK and
#       friends). Every ordinary vLLM build carries these; the published 1.5.0
#       wheel contains /data/minimax-h3/task-cache/... strings too. Reported,
#       not failed.
#
# Also reports per-library sizes and whether the optional Rust frontend made it
# into the wheel, then records the sha256.
set -euo pipefail

OUT="${1:-out}"
cd "$OUT"

WHEEL="$(ls -1 ./*.whl | head -n1)"
echo "Wheel: $WHEEL"
ls -l "$WHEEL"
echo "size_bytes: $(stat -c %s "$WHEEL")"

rm -rf extracted
mkdir -p extracted
unzip -q "$WHEEL" -d extracted

echo "=== native libraries (by size) ==="
find extracted -type f -name '*.so' -printf '%s\t%p\n' | sort -rn \
  | awk -F'\t' '{printf "%8.1f MB  %s\n", $1/1048576, $2}'
mapfile -t SO_FILES < <(find extracted -type f -name '*.so' | sort)
echo "count: ${#SO_FILES[@]}"

fail=0

echo "=== HARD GATE: RPATH / RUNPATH ==="
found=0
for so in "${SO_FILES[@]}"; do
  dyn="$(readelf -d "$so" 2>/dev/null | grep -E 'RPATH|RUNPATH' || true)"
  if [ -n "$dyn" ]; then
    found=1
    echo "::error::$so carries RPATH/RUNPATH"
    echo "$dyn"
  fi
done
if [ "$found" -eq 0 ]; then
  echo "clean: no RPATH/RUNPATH in ${#SO_FILES[@]} native libraries"
else
  fail=1
fi

echo "=== HARD GATE: expected SM70 components ==="
for want in \
  vllm/_C.abi3.so \
  vllm/_moe_C.abi3.so \
  vllm/_sm70_sampler_C.abi3.so \
  vllm/cumem_allocator.abi3.so \
  vllm/spinloop.abi3.so \
  vllm/vllm_flash_attn/_vllm_fa2_C.abi3.so \
  flash_attn_v100/flash_attn_v100_cuda.cpython-312-x86_64-linux-gnu.so \
  flash_attn_v100/paged_kv_utils.cpython-312-x86_64-linux-gnu.so \
  flash_qla/ops/gated_delta_rule/chunk/sm70/flash_qla_sm70_gdn_strided.so
do
  if [ -f "extracted/$want" ]; then
    echo "ok   $want"
  else
    echo "::error::missing $want"
    fail=1
  fi
done

echo "=== NOTE: compiled-in source paths (informational) ==="
grep -rlE '/home/[a-zA-Z0-9._-]+/|/data/[a-zA-Z0-9._-]+/|/work/src' extracted --include='*.so' 2>/dev/null \
  | head -20 || true
echo "(the published 1.5.0 wheel has the same, e.g. /data/minimax-h3/task-cache/...)"

echo "=== optional Rust frontend ==="
if [ -f extracted/vllm/vllm-rs ]; then
  ls -lh extracted/vllm/vllm-rs
else
  echo "vllm/vllm-rs absent (the published 1.5.0 wheel also ships without it)"
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
