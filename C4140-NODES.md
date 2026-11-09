# C4140-nodes: single-node en twee-node tests (c4140 + c4140-2)

Uitbreiding op de c4130-rapporten. Dezelfde 43-punts batterij ([METHODOLOGY.md](METHODOLOGY.md)), maar nu op twee Dell PowerEdge C4140's die via een directe 100 GbE-link aan elkaar hangen. Alle runs eisen een **context van minimaal 262.144 tokens**, behalve de 1Cat-run over twee nodes (64k, zie sectie 4).

Gemeten op 8–9 november 2026.

## 1. Hardware

| | **c4140** | **c4140-2** |
|---|---|---|
| CPU | 2× Xeon Gold 6138 (80 threads) | 2× Xeon Gold 6152 (88 threads) |
| RAM | 310 GiB (10×32 GB) | 251 GiB (8×32 GB) |
| GPU | 4× V100-SXM2-**32GB** (NVLink) | 4× V100-SXM2-**16GB** (NVLink) |
| VRAM totaal | 128 GB | 64 GB |
| Data-disk | Samsung 990 PRO 2 TB (`/data`) | 2× Toshiba XG4 512 GB RAID0 (`/data`, 954 GB) |
| OS | Ubuntu 26.04.1 | Linux Mint 22.3 |
| Kernel / driver | 7.0.0-42 / 580.178.04 | 7.0.0-42 / 580.178.04 |
| Link | 100G ConnectX-5 | 100G ConnectX-4 |

Samen 192 GB VRAM, maar gemengd (4×32 + 4×16).

### De 100 GbE-link

Een directe kabel met een vast /30 (`10.77.77.1` ↔ `10.77.77.2`), MTU 9000, geen gateway. Zie [scripts/multinode/100g-link.example.md](scripts/multinode/100g-link.example.md).

| Test | Resultaat |
|---|---|
| iperf3 (TCP) | 91 Gbit/s |
| RoCE v2 `ib_write_bw` | 98 Gbit/s |
| NCCL all-reduce, 8 GPU's, over TCP | 3,3 GB/s |
| NCCL all-reduce, 8 GPU's, over RoCE (IB-verbs) | **11,7 GB/s busbw** |

Het standaard 1Cat-image mist `libibverbs`; NCCL valt dan stilzwijgend terug op TCP (3,5× trager). Het bijgevoegde [Dockerfile.1cat-rdma](scripts/multinode/Dockerfile.1cat-rdma) lost dat op. Flags: `--network host --ipc host --ulimit memlock=-1 --cap-add IPC_LOCK --device /dev/infiniband`, `NCCL_IB_HCA=mlx5_0 NCCL_IB_GID_INDEX=3 NCCL_SOCKET_IFNAME=<100G-interface>`. GPU Direct RDMA staat uit.

## 2. Resultaten

Schaal: harde taken 4, long-context 6, betrouwbaarheid 5, tools 4, kennis 14, rekenen 10 (samen 43). De tabel wordt gegenereerd met `scripts/summarize_runs.py`.

| Run | Zware 4 | Long-ctx 6 | Betrouwb. 5 | Tools 4 | Kennis 14 | Rekenen 10 | Sweep 5/5 tot |
|---|---|---|---|---|---|---|---|
| **c4140:** Qwen3.8-Flash-Next NVFP4 (180B MoE), 1Cat, TP4 | 4/4 | 6/6 | 5/5 | 4/4 | 12/14 | 10/10 | 253k |
| **c4140-2:** Qwen3.8-27B NVFP4, 1Cat, TP4 | 4/4 | 6/6 | 5/5 | 4/4 | 11/14 | 10/10 | 253k |
| **c4140 + c4140-2:** Qwen3.5-397B-A17B IQ3_XXS, llama.cpp RPC | 4/4 | 6/6 | 5/5 | 4/4 | 12/14 | 10/10 | 253k |
| **c4140 + c4140-2:** GLM-5.3-Flash UD-Q3_K_XL, llama.cpp RPC | 4/4 | 6/6 | 4/5 | 4/4 | 12/14 | 10/10 | 252k |
| **c4140 + c4140-2:** Qwen3.8-27B NVFP4, 1Cat PP2×TP4 (64k) | 4/4 | 6/6 | 5/5 | 4/4 | 11/14 | 10/10 | 58k (max 64k) |

De 397B-cijfers van harde taken, kennis en rekenen komen uit de herhaling met `BENCH_MAX_TOKENS=8000`. Met 2000 tokens gaf de 397B lege antwoorden (kennis 8/14, rekenen 5/10): een thinking-budget-artefact, geen kwaliteitsverschil. In `results/` zijn de 8000-token-bestanden de hoofdbestanden; de eerste runs met 2000 tokens staan er als `...-initial2000-*` naast.

### Snelheid

Prefill / decode in tokens per seconde, cold prefill, `completion_tokens`-gebaseerd (1Cat) of sweep-timings (llama.cpp).

| Run | 8k | 32k | 65k | 131k | ~253k |
|---|---|---|---|---|---|
| Flash-Next, c4140 (MTP4) | 238 / 138 *(512 tok)* | 4361 / 125 | – | 4683 / 105 | 4133 / 109 |
| 27B, c4140-2 (16GB-GPU's) | 165 / 148 *(512 tok)* | 4145 / 397\* | – | 2446 / 96 | 1799 / 104 |
| 397B IQ3_XXS, 2 nodes, llama.cpp RPC | 191 / 26 | 165 / 23 | 141 / 21 | 110 / 17 | 90 / 14 |
| GLM-5.3-Flash Q3_K_XL, 2 nodes, llama.cpp RPC | 230 / 15 | 177 / 14 | 131 / 12 | 85 / 10 | 58 / 8 |

\* de 397 t/s decode bij 32k is een artefact van speculatieve decodering op zeer repetitieve tekst; het representatieve getal staat in de rij ernaast.

### Gelijktijdige gebruikers (chat, aggregaat t/s)

| Run | 1 | 2 | 4 | 8 |
|---|---|---|---|---|
| Flash-Next, c4140 | 88 | 130 | 223 | **340** |
| 27B, c4140-2 | 100 | 99 | 135 | 141 |

## 3. Wat werkt waarop

**Eén c4140 met Flash-Next (1Cat 1.5.2) is de beste verhouding tussen kwaliteit en snelheid** bij een eis van 262k context. Het model haalt het volledige 262k-venster, 5/5 retrieval tot 253k tokens, ~110–125 t/s decode en 340 t/s totaal bij 8 gebruikers. Het past omdat het hybride lineaire attention gebruikt en het KV-geheugen van de historie (`qsa_host_kv`, FP8) in vastgepind RAM-geheugen staat.

**Twee nodes helpen niet voor snelheid.** Het 397B-model (IQ3_XXS, 150 GB) past alleen als je het over beide machines verdeelt, en haalt dan dezelfde kwaliteit als Flash-Next op één machine, maar met ~14 t/s decode in plaats van ~110. Prefill zakt van ~190 naar ~90 t/s bij 253k. Het werkt wel stabiel: de gemelde llama.cpp-bug #27756 (stille EOS voorbij ~130k bij hybride DeltaNet) deed zich niet voor.

**GLM-5.3-Flash (321B, 18B actief)** past eveneens op 262k, maar is trager dan de 397B (8–15 t/s decode) en haalt dezelfde kwaliteit, op één punt na: de herhaaltest (betrouwbaarheid) gaf 4/5. Zijn tokenizer is compacter: dezelfde tekst kost ~19% meer tokens dan bij Qwen, dus de sweep-stap van 220.000 (nominaal) paste net niet in 262.144 en is daarom op 212.000 herhaald.

**Grote 1Cat-modellen over twee nodes.** De 1Cat-docs beschrijven PP2×TP4 alleen voor één machine met 8 GPU's. Het werkt hier wel functioneel (zie sectie 4), maar de grote 1Cat-modellen (GLM-5.3-Flash NVFP4 178–204 GB, DeepSeek-V4-Flash 160–167 GB) passen niet in 192 GB gemengd VRAM met 262k KV-cache.

## 4. 1Cat over twee nodes (PP2×TP4)

Qwen3.8-27B NVFP4 met `--tensor-parallel-size 4 --pipeline-parallel-size 2 --nnodes 2` over beide machines en de 100G-link. Het werkt: de eerste poging draaide op 64k context en haalde ~6000 t/s prefill en 41–51 t/s decode (zonder speculatieve decodering). 
| 27B NVFP4, 64k, zonder speculatieve decodering | Prefill @32k | Decode @32k | Decode @60k |
|---|---|---|---|
| 1 node (c4140, TP4) | 3587 t/s | 53 t/s | 48 t/s |
| 2 nodes (PP2×TP4 over 100G) | 6138 t/s | 45 t/s | 41 t/s |

Twee nodes geven dus ~1,7× snellere prefill (8 GPU's rekenen mee) maar ~15% tragere decode, omdat elke token door de link naar de tweede pipeline-stap moet. Een model dat op één node past, draai je beter op één node; twee nodes zijn alleen nuttig voor modellen die niet op één machine passen.

**Meetfouten in de eerste run.** Tools 0/4 kwam door ontbrekende serverflags (`--enable-auto-tool-choice --tool-call-parser qwen3_coder`): HTTP 400 op elk verzoek. Rekenen 5/10 kwam doordat zonder `--reasoning-parser` het denken in het antwoord terechtkwam en het limiet van 2000 tokens bereikt werd. Dit is gecorrigeerd in [q27-1cat-pp2tp4-node.sh](scripts/multinode/q27-1cat-pp2tp4-node.sh); na herhaling met de juiste flags en `BENCH_MAX_TOKENS=8000` is het resultaat tools 4/4 en rekenen 10/10 (de eerste, foute run staat als `...-initial-*` in `results/`).

## 5. Lessen

1. **Slot-3-bifurcatie.** Een NVMe-adapter met 2 SSD's in PCIe-slot 3 van de c4140-2 vereist `DellAutoDiscovery=ManualControl` en `Slot3Bif=x8x4x4`. Op de c4140 moet de waarde `x4x4x8` blijven, anders verdwijnt de data-SSD en stopt de boot bij F1.
2. **Herstart-hang.** De c4140-2 hangt bij elke normale reboot in `device_shutdown`. Een hook in `/usr/lib/systemd/system-shutdown/` (sync + SysRq-b) lost dat op.
3. **RPC-apparaten komen eerst.** In llama.cpp staan RPC-apparaten *vóór* de lokale CUDA-apparaten in de tensor-split: `-ts 12,12,12,12,30,30,30,30` (4×16 GB remote, 4×32 GB lokaal). De omgekeerde volgorde gaf OOM bij het laden.
4. **`-np 1` bij llama.cpp.** `-c` wordt over de slots verdeeld; één slot van 262.144 vraagt `-np 1 -kvu`.
5. **De RPC-server heeft geen authenticatie.** Bind hem alleen aan het IP van de 100G-link, nooit aan LAN of tailnet.
6. **Thinking-budget ≠ kwaliteit.** Lege antwoorden na `max_tokens` zijn een artefact van redeneermodellen. Draai kennis, rekenen en harde taken met een groter budget (`BENCH_MAX_TOKENS=8000`) voordat je kwaliteit vergelijkt.
7. **Controleer de serverflags voor tools en reasoning** voordat je een nieuwe configuratie benchmarkt; een ontbrekende parser geeft 0/4 zonder duidelijke fout.

## 6. Reproduceren

| Script | Doel |
|---|---|
| [scripts/run_vllm_battery.sh](scripts/run_vllm_battery.sh) | Volledige batterij tegen een draaiende server (1Cat of llama-server) |
| [scripts/summarize_runs.py](scripts/summarize_runs.py) | Markdown-rij per run uit `results/` |
| [scripts/multinode/flashnext-1cat-run.sh](scripts/multinode/flashnext-1cat-run.sh) | Flash-Next op één c4140 |
| [scripts/multinode/q27-1cat-16gb-run.sh](scripts/multinode/q27-1cat-16gb-run.sh) | 27B op de 16GB-GPU's van c4140-2 |
| [scripts/multinode/q27-1cat-pp2tp4-node.sh](scripts/multinode/q27-1cat-pp2tp4-node.sh) | 1Cat PP2×TP4 over twee nodes (`<rank> <ip> <iface>`) |
| [scripts/multinode/build-llamacpp-rpc.sh](scripts/multinode/build-llamacpp-rpc.sh) | llama.cpp met CUDA sm_70 en RPC bouwen |
| [scripts/multinode/rpc-worker.sh](scripts/multinode/rpc-worker.sh) | RPC-worker op c4140-2 |
| [scripts/multinode/llama-server-397b-rpc.sh](scripts/multinode/llama-server-397b-rpc.sh) | 397B over twee nodes |
| [scripts/multinode/llama-server-glm53-rpc.sh](scripts/multinode/llama-server-glm53-rpc.sh) | GLM-5.3-Flash over twee nodes |
| [scripts/multinode/Dockerfile.1cat-rdma](scripts/multinode/Dockerfile.1cat-rdma) | 1Cat-image met libibverbs |
| [scripts/multinode/nccl_allreduce_test.py](scripts/multinode/nccl_allreduce_test.py) | NCCL all-reduce-test over de link |

Voorbeeld:

```bash
./scripts/run_vllm_battery.sh flash-next 8082 c4140-qwen3.8-flash-next-nvfp4-vllm-262k
python3 scripts/summarize_runs.py c4140-qwen3.8-flash-next-nvfp4-vllm-262k
```

Voor modellen met een eigen tokenizer-dichtheid (GLM): kies `--sizes` zo dat `size × ~1,2` binnen het contextvenster blijft.
