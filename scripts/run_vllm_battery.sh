#!/usr/bin/env bash
# run_vllm_battery.sh — complete battery (speed + 43-point quality set + long-context sweep) against an
# ALREADY RUNNING OpenAI-compatible server (1Cat-vLLM or llama-server). Unlike run_benchmarks.sh it does
# not start/stop the server, so it works for multi-GPU docker servers and for the 2-node setups.
#
# Usage:
#   ./run_vllm_battery.sh <SERVED_MODEL> <PORT> <RESULT_PREFIX> [--sizes a,b,c] [--speed-sizes a,b,c]
#                         [--steps speed,hard,longctx,notulen,tools,knowledge,math,sweep]
#
#   SERVED_MODEL   the id the server answers to (the scripts send it as "model"), e.g. qwen3.8-27b
#   PORT           local port of the server (http://127.0.0.1:PORT)
#   RESULT_PREFIX  prefix for the result files, e.g. c4140-2-qwen3.8-27b-nvfp4-vllm-262k
#   --steps        run only these steps (default: all). Results of earlier runs with the same prefix are kept.
#
# Thinking per task type follows scripts/README.md (same as run_benchmarks.sh):
#   format tasks (longctx, notulen, tools) and the retrieval sweep: thinking OFF (--nothink / server default),
#   hard, knowledge, math: thinking ON via FORCE_THINKING=1 (the vLLM servers default to thinking OFF).
# Speed = usage.completion_tokens based. Sweep sizes overshoot ~1.15x, so 220000 is the largest useful size
# inside a 262144 window (-> ~253k tokens).
#
# Output: $OUT_DIR/<RESULT_PREFIX>-{speed,hard,longctx,notulen-repeat,tools,knowledge,math,longctx-sweep}.json
set -uo pipefail

if [ $# -lt 3 ]; then
  sed -n 2,22p "$0"; exit 1
fi
MODEL="$1"; PORT="$2"; PREFIX="$3"; shift 3
SIZES="8192,32768,65536,131072,220000"
SPEED_SIZES="512,4096,32768,131072,250000"
STEPS="speed,hard,longctx,notulen,tools,knowledge,math,sweep"
while [ $# -gt 0 ]; do
  case "$1" in
    --sizes) SIZES="$2"; shift ;;
    --speed-sizes) SPEED_SIZES="$2"; shift ;;
    --steps) STEPS="$2"; shift ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/../results}"
TMP="$OUT_DIR/.tmp-$PREFIX"
mkdir -p "$TMP"
BASE="http://127.0.0.1:$PORT"
cd "$SCRIPT_DIR"

stamp() { date '+%H:%M:%S'; }
want() { case ",$STEPS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
step() {  # name command...
  local name="$1"; shift
  echo ""; echo "=== [$(stamp)] $name"
  "$@" || echo "!! step failed: $name (continuing)"
}

curl -fsS -m 10 "$BASE/v1/models" >/dev/null || { echo "server not reachable on $BASE"; exit 2; }

want speed     && step speed     env -u FORCE_THINKING BENCH_URL="$BASE" python3 bench_vllm_speed.py "$MODEL" "$TMP/$MODEL-speed.json" "$SPEED_SIZES"
want hard      && step hard      env FORCE_THINKING=1 python3 bench_hard.py "$PORT" "$MODEL" --out-dir "$TMP"
want longctx   && step longctx   env FORCE_THINKING=1 python3 bench_longctx.py "$PORT" "$MODEL" --nothink --out-dir "$TMP"
want notulen   && step notulen   env FORCE_THINKING=1 python3 bench_notulen_repeat.py "$PORT" "$MODEL" 5 --nothink --out-dir "$TMP"
want tools     && step tools     env FORCE_THINKING=1 python3 bench_tools.py "$PORT" "$MODEL" --nothink --out-dir "$TMP"
want knowledge && step knowledge env FORCE_THINKING=1 python3 bench_knowledge.py "$PORT" "$MODEL" --out-dir "$TMP"
want math      && step math      env FORCE_THINKING=1 python3 bench_math.py "$PORT" "$MODEL" --out-dir "$TMP"
want sweep     && step sweep     env -u FORCE_THINKING python3 bench_longctx_sweep.py "$PORT" "$MODEL" --out-dir "$TMP" --sizes "$SIZES"

# rename <MODEL>-*.json -> <PREFIX>-*.json (the scripts name files after the served model id)
for f in "$TMP"/"$MODEL"-*; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  mv "$f" "$OUT_DIR/${PREFIX}-${base#"$MODEL"-}"
done
rmdir "$TMP" 2>/dev/null || true
echo ""; echo "=== [$(stamp)] DONE -> $OUT_DIR/${PREFIX}-*"
