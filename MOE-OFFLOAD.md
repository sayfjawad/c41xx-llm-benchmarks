# MOE-OFFLOAD — Kan de c4140 een 750B-MoE draaien via expert-offload?

> **Status: verkenning op papier, niet gemeten.** Alle cijfers in dit document zijn **schattingen**, afgeleid uit
> hardware-specificaties en de getallen uit een externe demo. Er is niets gedownload of gedraaid. Dit wijkt
> bewust af van de rest van deze repo, waar elk cijfer zelf gemeten is. Het doel is een referentiekader, geen
> resultaat. (Onderzocht 2026-10-30.)

## Aanleiding

In een YouTube-demo (oktober 2026) draaide de start-up Wi-Sci een **~750B-parameter MoE** ("DeepSeek 4.1 Flash",
~508 GB op volle kwaliteit) op één RTX 5090 met **32 GB VRAM**, met **~3–15 t/s, gemiddeld ~8 t/s**. De
WiFi-GPU en het commerciële product zijn hier niet relevant; de vraag is alleen: **werken dezelfde technieken op
onze 4× V100-hardware, en hoe snel zou dat zijn?**

## De techniek (zonder de marketing)

Een MoE-model gebruikt per token maar een klein deel van zijn gewichten. Volgens de demo kiest de router per laag
6 van de 384 experts, waardoor per token ~15 GB gelezen wordt in plaats van 508 GB. Je moet wel het hele model
beschikbaar houden, omdat je niet vooraf weet welke experts gekozen worden. Wi-Sci combineert vier ingrepen:

| # | Ingreep | Wat het oplost |
|---|---|---|
| 1 | **Model over drie lagen verdeeld:** VRAM → RAM → SSD | Het model past niet in 32 GB VRAM. ~475 GB staat op SSD. |
| 2 | **Populaire ("hot") experts blijven in VRAM/RAM** | Slechts ~1 GB/token komt nog van de SSD; in de demo kwam ~61% van de expert-gebruik uit VRAM. |
| 3 | **Gesplitste rekenkracht:** GPU rekent aan de experts in VRAM, CPU aan die in RAM/SSD | Gewichten hoeven niet eerst naar de GPU gekopieerd te worden. |
| 4 | **SSD-layout herschreven:** alle experts in gelijke, uitgelijnde chunks, 64 tegelijk gelezen | SSD-leessnelheid voor dit patroon ging van ~1 naar ~11.5 GB/s. |

Ingrepen 2 en 3 zijn niet nieuw: dit is **hybride CPU/GPU MoE-offload**, zoals llama.cpp (`-ot exps=CPU`,
`--n-cpu-moe`), ik_llama.cpp en ktransformers dat doen. Ingreep 4 (de SSD-trick) is alleen nodig als het model
niet in RAM + VRAM past.

## De c4140 naast de demo-box

| | Wi-Sci-demo | c4140 |
|---|---|---|
| VRAM | 32 GB (RTX 5090, ~1.8 TB/s) | **128 GB** (4× V100-SXM2-32GB, ~900 GB/s per GPU, NVLink) |
| RAM | consumentenklasse | **499 GiB** DDR4 |
| CPU | — | 2 sockets, 48 threads (exact model nog niet vastgelegd; C4140 = Xeon Scalable, 6 DDR4-kanalen per socket) |
| Waar staat een 750B-model? | grotendeels op SSD | **volledig in VRAM + RAM (~620 GB); geen SSD nodig** |

**Conclusie 1:** op de c4140 is de SSD-trick overbodig. Een 750B-MoE in Q4/Q5 (~400–450 GB) en zelfs de
"volle kwaliteit" van ~508 GB passen in RAM + VRAM. Alleen 1T+-modellen op hoge precisie zouden SSD nodig hebben.
Daarvoor zit er geen geschikte NVMe in de c4140; de systeemschijf heeft nu ~88 GB vrij.

## Schatting: hoe snel?

Bij hybride offload bepaalt de **RAM-bandbreedte van de CPU** de decodesnelheid: per token moet de CPU de experts
lezen die niet in VRAM staan.

**Bandbreedte c4140** (aanname: alle 12 kanalen bezet):

| | Waarde |
|---|---|
| Theoretisch, DDR4-2666 / -2933 | 12 × 21.3–23.5 GB/s = **~256–282 GB/s** |
| Realistisch in llama.cpp over 2 NUMA-nodes | **~100–150 GB/s** (verkeer tussen de twee sockets is traag) |

**Rekensom per modelklasse:**

| Model (klasse) | Grootte Q4 | Deel in VRAM | Uit RAM per token | Plafond (100–150 GB/s) | **Verwachting** |
|---|---|---|---|---|---|
| ~750B MoE, ~6 experts/laag (zoals de demo) | ~420–450 GB | ~30% van de experts + attention/shared | ~9–11 GB | ~9–16 t/s | **~5–12 t/s** |
| Qwen3-235B-A22B | ~130–140 GB | ~85–90% | ~1.5–2.5 GB | GPU-gebonden | **~25–40 t/s** |

De "verwachting" rekent met ~60–75% van het plafond. Dat verlies komt van NUMA, de wisselwerking tussen CPU en GPU,
en llama.cpp's layer-split, waarbij in de praktijk ~1 GPU tegelijk bezig is.

**Ter vergelijking:** de demo haalde gemiddeld ~8 t/s vanaf SSD. 1Cat rapporteert voor DeepSeek-V4-Flash
**73.5 t/s**, maar op **8× V100** (zie de README).

**Conclusie 2:** decode komt op het niveau van de demo of iets erboven, op hogere kwaliteit en zonder SSD.
Dat is bruikbaar voor één gebruiker in een chat, maar het is niet "snel" zoals de productieopstelling dat is.

## De kanttekeningen die de demo niet noemt

1. **Prefill is de echte bottleneck.** De Xeons hebben geen AMX (matrix-instructies, pas vanaf Sapphire Rapids) en
   de GPU's hangen aan PCIe 3.0 (~12 GB/s). Gewichten naar de GPU streamen voor een grote prefill-batch kost bij
   ~400 GB tientallen seconden per keer. Korte chatprompts zijn prima, maar een prompt van 20–30k tokens (RAG,
   coding-agent) kan **minuten** duren voordat het eerste woord verschijnt.
2. **Single-user.** Gelijktijdige requests delen dezelfde RAM-bandbreedte. Dit kan de multi-user-productie van
   Qwen3.8-27B NVFP4 (~190 t/s totale doorvoer bij 20 gebruikers) niet vervangen.
3. **Volta beperkt de runtime.** ktransformers en Marlin-kernels hebben sm_80+ nodig. **llama.cpp en
   ik_llama.cpp** werken op sm_70, met `-ot exps=CPU` / `--n-cpu-moe <n>` en `--numa distribute`. Hun
   expert-plaatsing is statisch per laag, niet dynamisch per populariteit zoals bij Wi-Sci, dus het VRAM-aandeel
   in de leesbewerkingen kan lager uitvallen dan de ~61% uit de demo.
4. **Schijf.** Er is >500 GB nodig voor het GGUF-bestand. Na de eerste keer laden blijft het model in de page cache
   van de 499 GiB RAM.

## Eindoordeel

| Vraag | Antwoord |
|---|---|
| Kan de c4140 de Wi-Sci-technieken gebruiken? | **Ja.** Expert-offload (ingrepen 2–3) werkt via llama.cpp. De SSD-trick (1, 4) is overbodig met 499 GiB RAM. |
| Past een ~750B-MoE? | **Ja**, in RAM + VRAM, tot ~5 bits per gewicht. |
| Is het snel? | **~5–12 t/s** decode voor één gebruiker, met trage prefill. Een ~235B-MoE haalt geschat ~25–40 t/s. |
| Vervangt het de productie? | **Nee.** Qwen3.8-27B NVFP4 op 1Cat-vLLM blijft sneller en efficiënter voor gelijktijdige gebruikers. |

Er is bewust besloten dit **niet te testen**. Mocht dat later toch gebeuren, dan is dit de volgorde:
1. Controleer de DIMM-bezetting met `dmidecode -t memory` (499 GiB hoeft geen gelijkmatige 12-kanaals bezetting te
   zijn) en het CPU-model.
2. Meet de echte RAM-bandbreedte per socket en over beide sockets met STREAM of Intel MLC. Die bandbreedte gedeeld
   door ~10–12 GB voorspelt de t/s.
3. Draai llama.cpp met een Q4-GGUF, eerst een ~235B-MoE en daarna een 700B-klasse model. Meet met
   `bench_vllm_speed.py`-stijl usage-telling en ook prefill bij 4k/32k.
