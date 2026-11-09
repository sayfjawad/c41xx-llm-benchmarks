# usage: mn-node.sh <rank> <my_ip> <iface>
RANK=$1; MYIP=$2; IFACE=$3
sudo docker rm -f mn27 2>/dev/null || true
if [ "$RANK" = 0 ]; then ROLE="--host 127.0.0.1 --port 8090"; else ROLE="--headless"; fi
sudo docker run -d --name mn27 --restart no --gpus all --network host --ipc host --ulimit memlock=-1 --cap-add IPC_LOCK --device /dev/infiniband \
  -v /data/models:/models:ro -v /data/bench-run/vllm-cache-152:/root/.cache \
  -e NCCL_IB_HCA=mlx5_0 -e NCCL_IB_GID_INDEX=3 -e NCCL_SOCKET_IFNAME=$IFACE -e GLOO_SOCKET_IFNAME=$IFACE -e VLLM_HOST_IP=$MYIP \
  -e NCCL_DEBUG=INFO -e NCCL_DEBUG_SUBSYS=INIT,NET -e PYTHONFAULTHANDLER=1 \
  --entrypoint vllm 1cat152-rdma:local \
  serve /models/Qwen3.8-27B-QUASAR-NVFP4 --served-model-name qwen3.8-27b $ROLE \
  --tensor-parallel-size 4 --pipeline-parallel-size 2 --nnodes 2 --node-rank $RANK --master-addr 10.77.77.1 --master-port 29501 \
  --trust-remote-code --dtype half --attention-backend FLASH_ATTN_V100 --kv-cache-dtype fp8_e4m3 \
  --max-model-len 65536 --gpu-memory-utilization 0.80 --max-num-batched-tokens 4096 --max-num-seqs 2 \
  --block-size 2048 --mamba-block-size 8192 --enable-prefix-caching --mamba-cache-mode align --seed 0 \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 --default-chat-template-kwargs '{"enable_thinking":false}'
