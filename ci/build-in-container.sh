#!/usr/bin/env bash
# Build the 1Cat-vLLM SM70/V100 wheel inside an nvidia/cuda:12.8-devel container.
#
# Expects:
#   /work/src      checkout of 1CatAI/1Cat-vLLM (with .git, for setuptools-scm)
#   /work/out      output directory for the wheel
#
# Env:
#   MAX_JOBS            parallel compile jobs (default 4)
#   VERSION_OVERRIDE    force wheel version, empty = derive from git
#   BUILD_REF           informational, the requested ref
set -euo pipefail

SRC=/work/src
OUT=/work/out
MAX_JOBS="${MAX_JOBS:-4}"

mkdir -p "$OUT"
echo "=== build ref: ${BUILD_REF:-unknown} ==="
echo "=== disk ==="
df -h /work / 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential git curl ca-certificates pkg-config \
  python3.12 python3.12-dev python3.12-venv \
  cmake ninja-build patchelf libssl-dev zlib1g-dev binutils perl

echo "=== nvcc ==="
nvcc --version
echo "=== nproc: $(nproc) ==="

# patchelf is a hard requirement: wheel assembly fails closed without it.
command -v patchelf

export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v rustup >/dev/null 2>&1; then
  echo "=== installing rustup ==="
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain none
fi
RUST_TOOLCHAIN="$(grep '^channel' "$SRC/rust-toolchain.toml" | sed 's/.*= *"\(.*\)"/\1/')"
echo "=== rust toolchain: $RUST_TOOLCHAIN ==="
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal
rustc +"$RUST_TOOLCHAIN" --version

git config --global --add safe.directory "$SRC"
cd "$SRC"
echo "=== git describe ==="
git describe --tags --always || true
git rev-parse HEAD

python3.12 -m venv /opt/venv
. /opt/venv/bin/activate
python -m pip install --upgrade pip setuptools wheel

echo "=== installing torch 2.10.0 + cu128 ==="
pip install --index-url https://download.pytorch.org/whl/cu128 \
  torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0

echo "=== installing build requirements ==="
pip install -r "$SRC/requirements/build/cuda.txt"

python - <<'PY'
import sys, torch, shutil
print("Python:", sys.version.split()[0])
print("Torch:", torch.__version__)
print("Torch CUDA:", torch.version.cuda)
print("nvcc:", shutil.which("nvcc"))
PY

if [ -n "${VERSION_OVERRIDE:-}" ]; then
  echo "=== forcing version: $VERSION_OVERRIDE ==="
  export SETUPTOOLS_SCM_PRETEND_VERSION="$VERSION_OVERRIDE"
fi

export TORCH_CUDA_ARCH_LIST=7.0
export CMAKE_CUDA_ARCHITECTURES=70
export NVCC_THREADS=1
export MAX_JOBS
export CMAKE_BUILD_TYPE=Release
export CMAKE_BUILD_PARALLEL_LEVEL="$MAX_JOBS"
export VLLM_TARGET_DEVICE=cuda

echo "=== building wheel (MAX_JOBS=$MAX_JOBS, arch 7.0) ==="
# In-place build via setup.py, matching the official recipe
# (`pip install -e . --no-build-isolation --no-deps` with the same env vars).
python setup.py bdist_wheel -d "$OUT"

echo "=== result ==="
ls -lh "$OUT"
