1Cat-vLLM 的 SM70 / V100 wheel，在 GitHub Actions 上从源码构建。

## 内容

- 源码：`1CatAI/1Cat-vLLM` 的 `{{REF}} @ {{COMMIT}}`
- 包名：`{{WHEEL}}`
- SHA256：`{{SHA256}}`
- 环境：Python 3.12 / Linux x86_64 / `torch==2.10.0`（cu128）
- 构建日志：{{RUN_URL}}

## 构建方式

在 `nvidia/cuda:12.8.1-devel-ubuntu24.04` 容器内，`TORCH_CUDA_ARCH_LIST=7.0`、
`NVCC_THREADS=1`、`compute_70,code=sm_70`，走 `python setup.py bdist_wheel`。
Rust 前端 `vllm-rs` 由仓库自带的 `tools/install_protoc.sh` 装好 protoc 后一并编出。

## 校验

构建流程自动执行 `ci/verify-wheel.sh`：

- 所有原生库零 `RPATH`/`RUNPATH`（官方 1.5.0 曾因构建机缺 patchelf 把 conda 路径
  焊进扩展，废掉过一版）
- 必需的 9 个 SM70 组件齐全
- 记录 sha256
- 编译进二进制的源码路径（`__FILE__`）仅作提示：官方 wheel 同样带有

## 安装

```bash
pip install {{WHEEL}}
```

自检：

```bash
python - <<'PY'
import torch, vllm, flash_attn_v100
from flash_attn_v100 import flash_attn_grouped_verify_max_query_tokens
print("Torch:", torch.__version__, "| vLLM:", vllm.__version__)
print("FlashAttention-V100: OK | max Q:", flash_attn_grouped_verify_max_query_tokens())
PY
```

## 注意

如果 `{{REF}}` 是 `main` 一类的分支，这是**未发版代码**，上游只对正式 tag 做过完整
质量门禁。用于生产前请自行评估。
