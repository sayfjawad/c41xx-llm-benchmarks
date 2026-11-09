#!/usr/bin/env python3
"""summarize_runs.py — one markdown row per benchmark run, built from the raw result files in results/.

Usage: python3 scripts/summarize_runs.py [--results-dir results] PREFIX [PREFIX ...]
  PREFIX = result-file prefix, e.g. c4140-qwen3.8-flash-next-nvfp4-vllm-262k  (files <PREFIX>-hard.json, ...)

Columns: quality scores of the 43-point battery (hard 4, long-ctx 6, reliability 5, tools 4, knowledge 14,
math 10), the largest long-context size answered 5/5, prefill/decode speed at 32k and the largest speed size,
and aggregate chat throughput at the highest concurrency level that was measured.
Pure stdlib. Missing files are shown as '–'.
"""
import argparse, json, os


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def ratio(d, total):
    """n_correct/n_total from a result dict (uses _summary when present, else counts 'correct' flags)."""
    if not isinstance(d, dict):
        return "–"
    s = d.get("_summary")
    if isinstance(s, dict) and "n_correct" in s:
        return f"{s['n_correct']}/{s['n_total']}"
    items = [v for k, v in d.items() if isinstance(v, dict) and not k.startswith("_")]
    if items:
        return f"{sum(1 for v in items if v.get('correct') or v.get('ok'))}/{len(items)}"
    return "–"


def longctx(d):
    if isinstance(d, dict) and d.get("score") is not None:
        sc = d["score"]
        return sc if isinstance(sc, str) and "/" in sc else f"{sc}/{d.get('n_needles', 6)}"
    return "–"


def reliability(d):
    if isinstance(d, dict):
        s = d.get("_summary") or {}
        if "n_pass" in s:
            return f"{s['n_pass']}/{s.get('n_total', 5)}"
        runs = d.get("runs")
        if isinstance(runs, list) and runs:
            ok = sum(1 for r in runs if r.get("ok") or r.get("pass") or r.get("correct"))
            return f"{ok}/{len(runs)}"
        for k in ("passed", "n_correct", "ok"):
            if k in s:
                return f"{s[k]}/{s.get('n_total', 5)}"
    return "–"


def sweep_max(d):
    """largest prompt_tokens answered 5/5, plus how many sizes failed."""
    if not isinstance(d, dict):
        return "–"
    best, fails = 0, 0
    for it in d.get("sizes", []):
        sc = it.get("score")
        full = False
        if isinstance(sc, str) and "/" in sc:
            a, b = sc.split("/")
            full = a == b and it.get("status", "ok") == "ok"
        elif isinstance(sc, (int, float)):
            full = sc >= it.get("n_needles", 5)
        if full:
            best = max(best, it.get("prompt_tokens", 0))
        else:
            fails += 1
    return f"{best // 1000}k" + (f" ({fails}✗)" if fails else "")


def speed(d, want):
    if not isinstance(d, dict):
        return "–"
    rows = d.get("sizes", [])
    if not rows:
        return "–"
    r = rows[-1] if want == "max" else min(rows, key=lambda x: abs(x.get("ctx_target", 0) - 32768))
    return f"{r.get('cold_prefill_tps', 0):.0f}/{r.get('decode_tps_median_warm', 0):.0f}"


def conc(d):
    if not isinstance(d, dict):
        return "–"
    rows = [r for r in d.get("results", []) if r.get("scenario") == "chat"]
    if not rows:
        return "–"
    r = max(rows, key=lambda x: x["users"])
    return f"{r['aggregate_tps']:.0f} @{r['users']}u"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results-dir", default=os.path.join(os.path.dirname(__file__), "..", "results"))
    ap.add_argument("prefixes", nargs="+")
    a = ap.parse_args()
    print("| Run | Zware 4 | Long-ctx 6 | Betrouwb. 5 | Tools 4 | Kennis 14 | Rekenen 10 | Sweep 5/5 tot | Prefill/decode t/s @32k | idem @max | Chat t/s totaal |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for p in a.prefixes:
        g = lambda n: load(os.path.join(a.results_dir, f"{p}-{n}.json"))
        print(f"| {p} | {ratio(g('hard'), 4)} | {longctx(g('longctx'))} | {reliability(g('notulen-repeat'))} | "
              f"{ratio(g('tools'), 4)} | {ratio(g('knowledge'), 14)} | {ratio(g('math'), 10)} | "
              f"{sweep_max(g('longctx-sweep'))} | {speed(g('speed'), '32k')} | {speed(g('speed'), 'max')} | {conc(g('concurrency'))} |")


if __name__ == "__main__":
    main()
