#!/usr/bin/env bash
# c4140-2: llama.cpp RPC worker exposing its 4 V100-16GB to the master on c4140. Bound to the 100G link IP ONLY
# (rpc-server is unauthenticated: arbitrary tensor read/write -> never on LAN/tailnet).
set -euo pipefail
sudo docker rm -f rpcworker 2>/dev/null || true
mkdir -p /data/bench-run/rpc-cache
sudo docker run -d --name rpcworker --restart no --gpus all --network host --ipc host \
  -v /data/bench-run/llama-src/llama.cpp/build/bin:/b:ro -v /data/bench-run/rpc-cache:/root/.cache/llama.cpp \
  -e LD_LIBRARY_PATH=/b nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  /b/ggml-rpc-server -H 10.77.77.2 -p 50052 -c
