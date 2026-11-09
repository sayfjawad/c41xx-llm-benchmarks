#!/usr/bin/env bash
# c4140: llama-server master, layer-split over the 4 V100-16GB of c4140-2 (RPC devices come FIRST in the device list: RPC0-3) + its own 4 V100-32GB (CUDA0-3) -> -ts 12,12,12,12,30,30,30,30.
# Listens on 127.0.0.1 only. -np 1: llama.cpp splits -c over slots, so one 262144-token slot needs -np 1.
set -euo pipefail
sudo docker rm -f llama397 2>/dev/null || true
M=/models/Qwen3.5-397B-A17B-UD-IQ3_XXS/Qwen3.5-397B-A17B-UD-IQ3_XXS-00001-of-00004.gguf
sudo docker run -d --name llama397 --restart no --gpus all --network host --ipc host \
  -v /data/models:/models:ro -v /data/bench-run/llama-src/llama.cpp/build/bin:/b:ro -e LD_LIBRARY_PATH=/b \
  nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  /b/llama-server -m $M --alias qwen3.5-397b --rpc 10.77.77.2:50052 -ngl 999 -c 262144 -np 1 -fa on \
  -ctk q8_0 -ctv q8_0 -kvu -sm layer -ts 12,12,12,12,30,30,30,30 --host 127.0.0.1 --port 8081 --jinja
