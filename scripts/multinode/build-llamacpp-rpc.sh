#!/usr/bin/env bash
# Build llama.cpp (CUDA sm_70 + RPC) at a pinned commit inside the CUDA devel image, source/build tree on /data (persistent).
set -euo pipefail
mkdir -p /data/bench-run/llama-src /data/bench-run/logs
sudo docker run --rm -v /data/bench-run/llama-src:/src -e COMMIT=7d7f0287530b nvidia/cuda:12.4.1-devel-ubuntu22.04 bash -c '
set -euo pipefail
apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends git cmake build-essential ca-certificates python3 >/dev/null
[ -d /src/llama.cpp/.git ] || git clone -q https://github.com/ggml-org/llama.cpp /src/llama.cpp
cd /src/llama.cpp && git checkout -q $COMMIT && git log -1 --format="commit %h %cd"
ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1
export LIBRARY_PATH=/usr/local/cuda/lib64/stubs
cmake -B build -DGGML_CUDA=ON -DGGML_RPC=ON -DCMAKE_CUDA_ARCHITECTURES=70 -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs" -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs" >/dev/null
cmake --build build -j"$(nproc)" 2>&1 | tail -25
ls build/bin | head -40
echo BUILD-KLAAR
'
