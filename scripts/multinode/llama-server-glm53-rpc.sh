#!/usr/bin/env bash
set -euo pipefail
sudo docker rm -f llamaglm 2>/dev/null || true
M=/models/GLM-5.3-Flash-UD-Q3_K_XL/GLM-5.3-Flash-UD-Q3_K_XL-00001-of-00004.gguf
sudo docker run -d --name llamaglm --restart no --gpus all --network host --ipc host \
  -v /data/models:/models:ro -v /data/bench-run/llama-src/llama.cpp/build/bin:/b:ro -e LD_LIBRARY_PATH=/b \
  nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  /b/llama-server -m $M --alias glm-5.3-flash --rpc 10.77.77.2:50052 -ngl 999 -c 262144 -np 1 -fa on \
  -ctk q8_0 -ctv q8_0 -kvu -sm layer -ts 12,12,12,12,30,30,30,30 --host 127.0.0.1 --port 8081 --jinja
