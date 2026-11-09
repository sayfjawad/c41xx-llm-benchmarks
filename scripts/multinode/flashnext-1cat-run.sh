#!/usr/bin/env bash
# c4140 single node: Qwen3.8 Flash-Next NVFP4 + MTP4 (180B MoE, RadixArk checkpoint) on 1Cat-vLLM v1.5.2, 4x V100-32GB, TP4.
# Official 1.5.2 release recipe (RELEASE_NOTES.en.md, "Flash-Next uses these parameters"): 262144 ctx, 8 seqs,
# 4096 prefill, FP8 KV history in pinned host RAM (qsa_host_kv), prefix caching, MTP4 (in-model MTP layers).
# Port published on 127.0.0.1 ONLY (docker bypasses ufw). Compile caches kept on /data so restarts are faster.
set -euo pipefail
sudo docker rm -f flashnext 2>/dev/null || true
mkdir -p /data/bench-run/vllm-cache-152
sudo docker run -d --name flashnext --restart no --gpus all --ipc host --ulimit memlock=-1 --cap-add IPC_LOCK \
  -p 127.0.0.1:8082:8000 -v /data/models:/models:ro -v /data/bench-run/vllm-cache-152:/root/.cache \
  -e PYTHONFAULTHANDLER=1 -e NCCL_DEBUG=WARN \
  --entrypoint vllm ghcr.io/dsyzayn/1cat-vllm-v100-docker:latest \
  serve /models/Qwen3.8-Flash-Next-NVFP4 --served-model-name flash-next --host 0.0.0.0 --port 8000 \
  --tensor-parallel-size 4 --dtype half --kv-cache-dtype float16 --max-model-len 262144 \
  --max-num-seqs 8 --max-num-batched-tokens 4096 --gpu-memory-utilization 0.89 \
  --attention-backend FLASH_ATTN_V100 --enable-prefix-caching --partial-prefix-cache \
  --block-size 2048 --mamba-block-size 2048 --mixed-prefill-step-latency-ms 0 \
  --mamba-ssm-cache-dtype float32 --language-model-only --trust-remote-code \
  --enable-prompt-tokens-details --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 --default-chat-template-kwargs '{"enable_thinking":false}' --seed 0 \
  --kernel-config '{"sm70_hcx": true, "sm70_qsa_prep": true, "sm70_hcx_local_schedule": true, "qsa_host_kv": true, "qsa_host_kv_dtype": "fp8_e4m3", "qsa_host_kv_hot_dtype": "fp8_e4m3", "qsa_host_kv_hot_tokens": 32768, "qsa_host_kv_prefill_stage_tokens": 262144}' \
  --speculative-config '{"method": "mtp", "num_speculative_tokens": 4, "draft_sample_method": "greedy"}'
