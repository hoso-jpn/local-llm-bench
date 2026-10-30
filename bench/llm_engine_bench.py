#!/usr/bin/env python3
"""
llm_engine_bench.py — OpenAI互換サーバ（FreeToken / Strata など）の推論速度を同一条件で計測する。

計測する指標（リクエストごとにJSONLへ1行）:
  ttft_s, total_s, prompt_tokens, completion_tokens,
  decode_tps   = (completion_tokens - 1) / (t_last - t_first)
  prefill_tps  = prompt_tokens / ttft_s
  e2e_tps      = completion_tokens / total_s
  gap_p50/p95/p99_ms, stall_rate (チャンク到着間隔 > --stall-ms の割合)
  mem_available_min_gib, swap_in_mib, swap_out_mib,
  vram_used_max_gib, gpu_power_avg_w, pcie_rx_avg_gbps (pynvmlがあれば)

使い方の例:
  # トラックA（同一GGUF・MTPなし）FreeToken
  python llm_engine_bench.py --base-url http://127.0.0.1:8000/v1 --engine freetoken \
      --track A --model-file GSQ-RCO-IQ3_XXS --source code.txt --prompt-kind code \
      --tokenizer Qwen/Qwen3.8-Flash-Next --input-lens 1024,4096,32768 --output-lens 256,1024

  # トラックC（多ターン・prefix cacheを生かす）
  python llm_engine_bench.py ... --track C --turns 3 --no-nonce

  # 集計だけ
  python llm_engine_bench.py --summarize results.jsonl

依存: Python 3.9+ の標準ライブラリのみ。任意で transformers（正確なトークン長）と pynvml（GPU計測）。
"""
import argparse
import json
import os
import statistics
import subprocess
import threading
import time
import urllib.request
import uuid


# ---------------------------------------------------------------- prompts
class PromptBuilder:
    """ソーステキストからモデルのtokenizerで指定トークン数ぶん切り出す。"""

    def __init__(self, source_path, tokenizer_name=None):
        with open(source_path, encoding="utf-8") as f:
            self.text = f.read()
        self.tok = None
        if tokenizer_name:
            try:
                from transformers import AutoTokenizer
                self.tok = AutoTokenizer.from_pretrained(tokenizer_name, trust_remote_code=True)
                self.ids = self.tok.encode(self.text, add_special_tokens=False)
            except Exception as e:  # noqa: BLE001
                print(f"[warn] tokenizer を読めませんでした ({e})。文字数で近似します")
                self.tok = None
        if self.tok is None:
            print("[warn] tokenizer 未指定: 1トークン≒3文字で近似。正確な比較には --tokenizer を使ってください")

    def cut(self, n_tokens):
        if self.tok is not None:
            ids = self.ids
            while len(ids) < n_tokens:
                ids = ids + self.ids
            return self.tok.decode(ids[:n_tokens])
        text = self.text
        while len(text) < n_tokens * 3:
            text += "\n" + self.text
        return text[: n_tokens * 3]


INSTRUCTIONS = {
    "code": "このコードが何をしているか、日本語で詳しく説明してください。",
    "ja": "上の文章の内容を踏まえて、論点を整理し、自分の意見を交えて日本語で詳しく論じてください。",
}


# ---------------------------------------------------------------- resource sampler
class Sampler(threading.Thread):
    """リクエスト中のメモリ・swap・GPUを0.25秒ごとに記録する。"""

    def __init__(self, interval=0.25):
        super().__init__(daemon=True)
        self.interval = interval
        self.stop_evt = threading.Event()
        self.mem_avail = []
        self.vram = []
        self.power = []
        self.pcie_rx = []
        self.nvml = None
        try:
            import pynvml
            pynvml.nvmlInit()
            self.nvml = pynvml
            self.h = pynvml.nvmlDeviceGetHandleByIndex(int(os.environ.get("BENCH_GPU", "0")))
        except Exception:  # noqa: BLE001
            self.nvml = None
        self.swap0 = self._vmstat()

    @staticmethod
    def _vmstat():
        out = {}
        try:
            with open("/proc/vmstat") as f:
                for line in f:
                    k, v = line.split()
                    if k in ("pswpin", "pswpout"):
                        out[k] = int(v)
        except OSError:
            pass
        return out

    @staticmethod
    def _mem_available_gib():
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemAvailable:"):
                        return int(line.split()[1]) / 1024 / 1024
        except OSError:
            return None
        return None

    def run(self):
        while not self.stop_evt.is_set():
            m = self._mem_available_gib()
            if m is not None:
                self.mem_avail.append(m)
            if self.nvml:
                try:
                    self.vram.append(self.nvml.nvmlDeviceGetMemoryInfo(self.h).used / 1024**3)
                    self.power.append(self.nvml.nvmlDeviceGetPowerUsage(self.h) / 1000)
                    # KB/s, 20ms窓。H2D = RX(GPU側から見た受信)
                    rx = self.nvml.nvmlDeviceGetPcieThroughput(self.h, self.nvml.NVML_PCIE_UTIL_RX_BYTES)
                    self.pcie_rx.append(rx * 1024 / 1e9)
                except Exception:  # noqa: BLE001
                    pass
            time.sleep(self.interval)

    def finish(self):
        self.stop_evt.set()
        self.join(timeout=2)
        s1 = self._vmstat()
        page_kib = os.sysconf("SC_PAGE_SIZE") / 1024
        avg = lambda xs: round(sum(xs) / len(xs), 3) if xs else None  # noqa: E731
        return {
            "mem_available_min_gib": round(min(self.mem_avail), 2) if self.mem_avail else None,
            "swap_in_mib": round((s1.get("pswpin", 0) - self.swap0.get("pswpin", 0)) * page_kib / 1024, 1),
            "swap_out_mib": round((s1.get("pswpout", 0) - self.swap0.get("pswpout", 0)) * page_kib / 1024, 1),
            "vram_used_max_gib": round(max(self.vram), 2) if self.vram else None,
            "gpu_power_avg_w": avg(self.power),
            "pcie_rx_avg_gbps": avg(self.pcie_rx),
        }


# ---------------------------------------------------------------- one request
def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = (len(xs) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def stream_request(opts, base_url, model, messages, max_tokens, thinking, extra, stall_ms):
    body = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
        "reasoning_effort": thinking,
        "chat_template_kwargs": {"enable_thinking": thinking != "none"},
    }
    body.update(extra)
    sampler = Sampler()
    sampler.start()
    t0 = time.perf_counter()
    arrivals, text, usage = [], [], None
    req = urllib.request.Request(
        f"{base_url}/chat/completions", data=json.dumps(body).encode("utf-8"), method="POST",
        headers={"Content-Type": "application/json", "Accept": "text/event-stream",
                 "Authorization": f"Bearer {opts['api_key']}"})
    with urllib.request.urlopen(req, timeout=opts["timeout"]) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            obj = json.loads(data)
            if obj.get("usage"):
                usage = obj["usage"]
            for ch in obj.get("choices", []):
                d = ch.get("delta", {}) or {}
                piece = (d.get("content") or "") + (d.get("reasoning_content") or d.get("reasoning") or "")
                if piece or d.get("tool_calls"):
                    arrivals.append(time.perf_counter())
                    text.append(piece)
    t_end = time.perf_counter()
    res = sampler.finish()

    if not arrivals:
        raise RuntimeError("出力トークンを受信できませんでした")
    ttft = arrivals[0] - t0
    total = t_end - t0
    usage = usage or {}
    n_out = usage.get("completion_tokens") or len(arrivals)
    n_in = usage.get("prompt_tokens")
    cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens")
    gaps = [(b - a) * 1000 for a, b in zip(arrivals, arrivals[1:])]
    span = arrivals[-1] - arrivals[0]
    out = {
        "ttft_s": round(ttft, 3),
        "total_s": round(total, 3),
        "prompt_tokens": n_in,
        "cached_tokens": cached,
        "completion_tokens": n_out,
        "chunks": len(arrivals),
        "decode_tps": round((n_out - 1) / span, 2) if span > 0 and n_out > 1 else None,
        "prefill_tps": round(n_in / ttft, 1) if n_in else None,
        "e2e_tps": round(n_out / total, 2),
        "gap_p50_ms": round(pct(gaps, 50), 1) if gaps else None,
        "gap_p95_ms": round(pct(gaps, 95), 1) if gaps else None,
        "gap_p99_ms": round(pct(gaps, 99), 1) if gaps else None,
        "stall_rate": round(sum(g > stall_ms for g in gaps) / len(gaps), 4) if gaps else None,
    }
    out.update(res)
    return out, "".join(text)


# ---------------------------------------------------------------- main loop
def run_bench(a):
    pb = PromptBuilder(a.source, a.tokenizer)
    extra = json.loads(a.extra_body) if a.extra_body else {}
    client = {"api_key": a.api_key, "timeout": a.timeout}
    in_lens = [int(x) for x in a.input_lens.split(",")]
    out_lens = [int(x) for x in a.output_lens.split(",")]
    meta = {"engine": a.engine, "track": a.track, "model_file": a.model_file,
            "prompt_kind": a.prompt_kind, "thinking": a.thinking, "label": a.label}

    with open(a.out, "a", encoding="utf-8") as fout:
        for n_in in in_lens:
            body_text = pb.cut(n_in)
            for n_out in out_lens:
                for run in range(-a.warmup, a.runs):
                    nonce = "" if a.no_nonce else f"[req {uuid.uuid4().hex}]\n"
                    messages = [{"role": "user",
                                 "content": f"{nonce}{body_text}\n\n{INSTRUCTIONS[a.prompt_kind]}"}]
                    for turn in range(a.turns):
                        try:
                            m, reply = stream_request(client, a.base_url, a.model, messages, n_out,
                                                      a.thinking, extra, a.stall_ms)
                        except Exception as e:  # noqa: BLE001
                            m, reply = {"error": str(e)}, ""
                        rec = dict(meta, input_len=n_in, output_len=n_out, run=run, turn=turn,
                                   warmup=run < 0, ts=time.strftime("%Y-%m-%dT%H:%M:%S"), **m)
                        fout.write(json.dumps(rec, ensure_ascii=False) + "\n")
                        fout.flush()
                        tag = "warmup" if run < 0 else f"run {run}"
                        print(f"[{a.engine}/{a.track}] in={n_in} out={n_out} {tag} turn={turn}: "
                              f"TTFT={m.get('ttft_s')}s decode={m.get('decode_tps')} tok/s "
                              f"cached={m.get('cached_tokens')} p99gap={m.get('gap_p99_ms')}ms "
                              f"{'ERROR ' + m['error'] if 'error' in m else ''}")
                        # 多ターン: 返答を履歴に積み、短い追質問を足す
                        messages = messages + [
                            {"role": "assistant", "content": reply},
                            {"role": "user", "content": "続けて、改善点を3つ挙げてください。"}]
                    if a.cooldown:
                        time.sleep(a.cooldown)


def summarize(path):
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    rows = [r for r in rows if not r.get("warmup") and "error" not in r]
    keys = ("engine", "track", "model_file", "prompt_kind", "input_len", "output_len", "turn")
    groups = {}
    for r in rows:
        groups.setdefault(tuple(r.get(k) for k in keys), []).append(r)
    cols = ("ttft_s", "decode_tps", "prefill_tps", "gap_p99_ms", "mem_available_min_gib", "pcie_rx_avg_gbps")
    print("\t".join(keys + tuple(f"{c}(median[min-max])" for c in cols) + ("n",)))
    for g, rs in sorted(groups.items(), key=lambda kv: tuple(str(x) for x in kv[0])):
        cells = []
        for c in cols:
            v = [r[c] for r in rs if r.get(c) is not None]
            cells.append(f"{statistics.median(v):.2f}[{min(v):.2f}-{max(v):.2f}]" if v else "-")
        print("\t".join([str(x) for x in g] + cells + [str(len(rs))]))


def record_env(path):
    """計測環境（GPU・PCIe幅・ドライバ・RAM速度）を記録する。"""
    cmds = {
        "gpu": "nvidia-smi --query-gpu=name,driver_version,pcie.link.gen.current,pcie.link.width.current,"
               "pcie.link.width.max,memory.total --format=csv,noheader",
        "ram_speed": "sudo -n dmidecode -t memory 2>/dev/null | grep -i 'Configured Memory Speed' | sort | uniq -c",
        "kernel": "uname -r",
        "cpu": "lscpu | grep 'Model name'",
    }
    env = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
    for k, c in cmds.items():
        env[k] = subprocess.run(c, shell=True, capture_output=True, text=True).stdout.strip()
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(env, ensure_ascii=False) + "\n")
    print(json.dumps(env, ensure_ascii=False, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--base-url", default="http://127.0.0.1:8080/v1")
    p.add_argument("--api-key", default="local")
    p.add_argument("--model", default="default", help="サーバに渡すmodel名")
    p.add_argument("--engine", help="freetoken / strata など（記録用ラベル）")
    p.add_argument("--track", default="A", help="A / B / C（記録用）")
    p.add_argument("--model-file", default="", help="使用したモデルファイル名（記録用）")
    p.add_argument("--label", default="", help="自由記述（例: x8_3600MTs_offload）")
    p.add_argument("--source", help="プロンプトの元テキスト")
    p.add_argument("--prompt-kind", choices=sorted(INSTRUCTIONS), default="code")
    p.add_argument("--tokenizer", help="HF tokenizer名またはパス（正確なトークン長のため推奨）")
    p.add_argument("--input-lens", default="1024,4096,16384,32768")
    p.add_argument("--output-lens", default="256,1024")
    p.add_argument("--runs", type=int, default=5)
    p.add_argument("--warmup", type=int, default=1)
    p.add_argument("--turns", type=int, default=1, help="トラックC用: 同じ会話を続けるターン数")
    p.add_argument("--no-nonce", action="store_true", help="prefix cacheを生かす（トラックC）")
    p.add_argument("--thinking", default="none", choices=["none", "low", "medium", "high"])
    p.add_argument("--extra-body", help='追加のリクエストJSON。例: \'{"ignore_eos": true}\'')
    p.add_argument("--stall-ms", type=float, default=200)
    p.add_argument("--cooldown", type=float, default=2.0)
    p.add_argument("--timeout", type=float, default=1800)
    p.add_argument("--out", default="results.jsonl")
    p.add_argument("--summarize", metavar="JSONL", help="計測せず、結果ファイルを集計して表示")
    p.add_argument("--record-env", metavar="JSONL", help="計測せず、環境情報を記録")
    a = p.parse_args()

    if a.summarize:
        return summarize(a.summarize)
    if a.record_env:
        return record_env(a.record_env)
    if not (a.engine and a.source):
        p.error("--engine と --source が必要です")
    run_bench(a)


if __name__ == "__main__":
    main()
