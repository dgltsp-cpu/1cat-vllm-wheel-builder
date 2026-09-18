# 1Cat-vLLM SM70 wheel builder

Builds the `1cat-vllm` wheel for NVIDIA Tesla V100 / SM70 from source on GitHub
Actions, following the official build contract in
`1CatAI/1Cat-vLLM` (`docs/design/sm70_v100_migration_control.md`, README
"Build From Source").

## Usage

Actions -> **Build 1Cat-vLLM SM70 wheel** -> *Run workflow*.

| Input | Meaning |
| --- | --- |
| `ref` | 1Cat-vLLM tag / branch / commit to build. Default `v1.5.0`. |
| `version` | Force the wheel version. Leave empty to derive it from git. |
| `max_jobs` | Parallel compile jobs. Default `4` (runner has 4 vCPU). |

The finished wheel and its `.sha256` are uploaded as the `1cat-vllm-wheel`
artifact.

## What the build does

1. Frees disk space on the runner (the build needs tens of GB).
2. Checks out `1CatAI/1Cat-vLLM` at `ref` with full history, so
   `setuptools-scm` can resolve the version from tags.
3. Runs `ci/build-in-container.sh` inside
   `nvidia/cuda:12.8.1-devel-ubuntu24.04`: Python 3.12, torch 2.10.0+cu128,
   Rust toolchain from `rust-toolchain.toml`, cmake / ninja / patchelf, then
   `python -m build --wheel --no-isolation` with
   `TORCH_CUDA_ARCH_LIST=7.0` and `CMAKE_CUDA_ARCHITECTURES=70`.
4. Runs `ci/verify-wheel.sh`, which reproduces the official acceptance gates:
   every native library must have no `RPATH`/`RUNPATH`, no build-host path may
   leak into the wheel, and the metadata must match the expected dependency
   contract.

## Local use

The same container recipe works on any Linux x86_64 box with Docker, including
the V100 host itself:

```bash
mkdir -p out
GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/1CatAI/1Cat-vLLM src
docker run --rm \
  -v "$PWD/src:/work/src" -v "$PWD/builder:/work/builder" -v "$PWD/out:/work/out" \
  -e MAX_JOBS=4 nvidia/cuda:12.8.1-devel-ubuntu24.04 \
  bash /work/builder/ci/build-in-container.sh
bash ci/verify-wheel.sh out
```

## Notes

- Expectations: `cp312` / Linux x86_64 / `torch==2.10.0`. A wheel built here is
  ABI-bound to that combination.
- A full source build compiles vLLM's CUDA extensions plus the bundled
  FlashAttention-V100, FlashQLA and SM70 kernels. On a 4 vCPU runner this is
  measured in hours; `timeout-minutes` is set close to the 6 h job ceiling.
- Private repositories consume GitHub Actions minutes; a public builder repo
  does not.
