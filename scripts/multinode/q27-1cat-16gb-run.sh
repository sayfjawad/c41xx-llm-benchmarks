#!/usr/bin/env bash
# c4140-2 single node: Qwen3.8-27B NVFP4 + DFlash2 on 1Cat-vLLM (image v1.5.1 = same as the c4130/c4140 repo results), 262144 ctx.
# c4140-2 has 4x V100-16GB (c4130/c4140: 32GB) => --gpu-memory-utilization 0.85 (was 0.8 of 32GB), --max-num-seqs 2 (was 4).
# Port published on 127.0.0.1 ONLY (docker bypasses ufw; see c4130 q38-vllm-run.sh SECURITY note).
set -euo pipefail
sudo docker rm -f q27 2>/dev/null || true
sudo docker run -d --name q27 --restart no --gpus all --shm-size 2g \
  -p 127.0.0.1:8083:8000 \
  -v /data/models:/models:ro \
  -e PYTHONFAULTHANDLER=1 -e NCCL_DEBUG=WARN \
  ghcr.io/dsyzayn/1cat-vllm-v100-docker:latest \
  --model /models/Qwen3.8-27B-QUASAR-NVFP4 \
  --served-model-name qwen3.8-27b \
  --host 0.0.0.0 --port 8000 \
  --trust-remote-code --dtype half \
  --tensor-parallel-size 4 \
  --attention-backend FLASH_ATTN_V100 \
  --kv-cache-dtype fp8_e4m3 \
  --max-model-len 262144 \
  --gpu-memory-utilization 0.85 \
  --max-num-batched-tokens 4096 \
  --max-num-seqs 2 \
  --block-size 2048 --mamba-block-size 8192 \
  --enable-prefix-caching --mamba-cache-mode align \
  --limit-mm-per-prompt '{"image":4,"video":0}' \
  --mm-processor-kwargs '{"size":{"longest_edge":3211264,"shortest_edge":65536}}' \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 \
  --default-chat-template-kwargs '{"enable_thinking":false}' \
  --seed 0 \
  --speculative-config '{"method":"dflash","model":"/models/Qwen3.8-27B-DFlash2","num_speculative_tokens":7,"kv_cache_dtype":"auto","attention_backend":"FLASH_ATTN_V100","draft_sample_method":"probabilistic","enforce_eager":false}'

