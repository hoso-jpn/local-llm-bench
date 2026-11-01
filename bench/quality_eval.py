#!/usr/bin/env python3
"""
quality_eval.py — OpenAI 互換サーバ（FreeToken / Strata）の回答の品質を評価する。

サブコマンド:
  prepare   評価データを data/quality/ に作る（GSM8K・HumanEval・JCommonsenseQA は Hugging Face から取得、
            JSON 抽出は固定の乱数で生成）。要 huggingface_hub と pyarrow
  run       サーバに問題を送り、回答をそのまま JSONL に記録する（途中から再開できる）
  score     回答を採点する。HumanEval は、ネットワークを切った使い捨てのコンテナの中でテストを実行する
  report    採点結果を集計する（正答率と Wilson の 95% 信頼区間、1問あたり・正答1件あたりの時間）
  compare   2つの構成の回答の一致度を比べる（同じ重みでエンジンが違う場合など）

使い方の例:
  uv run --with huggingface_hub --with pyarrow python bench/quality_eval.py prepare
  python3 bench/quality_eval.py run --base-url http://127.0.0.1:8082/v1 --model x --label strata-B \\
      --tasks gsm8k,humaneval,jcqa,json --out results/q/strata_B/quality.jsonl
  python3 bench/quality_eval.py score results/q/strata_B/quality.jsonl
  python3 bench/quality_eval.py report results/q/*/scored.jsonl
"""
import argparse
import json
import math
import os
import random
import re
import shutil
import statistics
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "quality"
TASKS = ("gsm8k", "humaneval", "jcqa", "json")
LIMITS = {"gsm8k": 300, "humaneval": 164, "jcqa": 300, "json": 50}


# ============================================================ prepare
# Hugging Face のキャッシュは、この評価専用の場所に置く（~/.cache/huggingface が他の用途で root の持ち物になっていることがあるため）
HF_CACHE = os.environ.get("QUALITY_HF_CACHE",
                          str(Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "local-llm-bench" / "hf"))


def _find_parquet(api, repo, *must):
    files = [f for f in api.list_repo_files(repo, repo_type="dataset") if f.endswith(".parquet")]
    hits = [f for f in files if all(m in f for m in must)]
    if not hits:
        raise SystemExit(f"{repo}: {must} に合う parquet がありません: {files}")
    return sorted(hits)[0]


def _read_parquet(repo, path, revision=None):
    from huggingface_hub import hf_hub_download
    import pyarrow.parquet as pq
    local = hf_hub_download(repo, path, repo_type="dataset", revision=revision, cache_dir=HF_CACHE)
    return pq.read_table(local).to_pylist()


def _write(task, rows, source):
    DATA.mkdir(parents=True, exist_ok=True)
    with open(DATA / f"{task}.jsonl", "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{task}: {len(rows)} 問 -> {DATA / f'{task}.jsonl'}  （出典: {source}）")


def prepare(_a):
    from huggingface_hub import HfApi
    api = HfApi()
    Path(HF_CACHE).mkdir(parents=True, exist_ok=True)
    print(f"Hugging Face のキャッシュ: {HF_CACHE}")
    sources = {}

    # GSM8K（MIT）：test の先頭から
    repo = "openai/gsm8k"; path = _find_parquet(api, repo, "main/", "test")
    rows = _read_parquet(repo, path)[: LIMITS["gsm8k"]]
    out = []
    for i, r in enumerate(rows):
        gold = r["answer"].split("####")[-1].strip().replace(",", "")
        out.append({"id": f"gsm8k-{i:04d}", "question": r["question"], "gold": gold})
    _write("gsm8k", out, f"{repo}/{path}"); sources["gsm8k"] = f"{repo}/{path}"

    # HumanEval（MIT）：全164問
    repo = "openai/openai_humaneval"; path = _find_parquet(api, repo, "test")
    rows = _read_parquet(repo, path)[: LIMITS["humaneval"]]
    out = [{"id": r["task_id"].replace("/", "-"), "prompt": r["prompt"], "test": r["test"],
            "entry_point": r["entry_point"]} for r in rows]
    _write("humaneval", out, f"{repo}/{path}"); sources["humaneval"] = f"{repo}/{path}"

    # JCommonsenseQA v1.1（CC-BY-4.0）：validation の先頭から
    repo = "leemeng/jcommonsenseqa-v1.1"; path = _find_parquet(api, repo, "validation")
    rows = _read_parquet(repo, path)[: LIMITS["jcqa"]]
    out = []
    for i, r in enumerate(rows):
        choices = [r[k] for k in sorted(k for k in r if k.startswith("choice"))]
        out.append({"id": f"jcqa-{r.get('q_id', i)}", "question": r["question"], "choices": choices,
                    "gold": str(r["label"])})
    _write("jcqa", out, f"{repo}/{path}"); sources["jcqa"] = f"{repo}/{path}"

    # JSON 抽出：固定の乱数で生成（著作物を含まない）
    _write("json", make_json_tasks(), "合成（seed 20261101）"); sources["json"] = "synthetic seed 20261101"
    with open(DATA / "SOURCES.json", "w", encoding="utf-8") as f:
        json.dump(sources, f, ensure_ascii=False, indent=1)


def make_json_tasks(n=LIMITS["json"], seed=20261101):
    rnd = random.Random(seed)
    sei = ["佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤"]
    mei = ["陽菜", "蓮", "結衣", "湊", "葵", "悠真", "凛", "大和", "紬", "樹"]
    products = ["ワイヤレスマウス", "USB-C ハブ", "メカニカルキーボード", "27インチモニター", "ノートPCスタンド",
                "外付けSSD 1TB", "Webカメラ", "ノイズキャンセリングヘッドホン", "LANケーブル 5m", "デスクライト"]
    templates = [
        "{name}様より、{y}年{m}月{d}日付で{product}を{q}点ご注文いただきました。単価は{p:,}円（税込）です。"
        "確認のご連絡は {email} までお願いいたします。",
        "【注文受付】注文日：{y}年{m}月{d}日／お名前：{name}／商品：{product}／数量：{q}／単価：{p}円／"
        "連絡先メール：{email}",
        "お世話になっております。{name}です。{product}を{q}個お願いします。カタログの価格は1個{p:,}円でした。"
        "{m}月{d}日（{y}年）に注文します。返信は{email}にください。",
        "{y}/{m}/{d} の注文です。購入者は{name}さん、品目は「{product}」、{q}点、1点あたり{p}円。"
        "メールアドレス：{email}",
    ]
    tasks = []
    for i in range(n):
        name = rnd.choice(sei) + " " + rnd.choice(mei)
        product = rnd.choice(products)
        q = rnd.randint(1, 12)
        p = rnd.choice([980, 1480, 2980, 4500, 6980, 12800, 19800, 32800, 45000])
        y, m, d = 2026, rnd.randint(1, 12), rnd.randint(1, 28)
        email = f"user{rnd.randint(100, 999)}@example.jp"
        text = rnd.choice(templates).format(name=name, product=product, q=q, p=p, y=y, m=m, d=d, email=email)
        gold = {"customer_name": name, "product": product, "quantity": q, "unit_price_yen": p,
                "order_date": f"{y:04d}-{m:02d}-{d:02d}", "email": email}
        tasks.append({"id": f"json-{i:03d}", "text": text, "gold": gold})
    return tasks


# ============================================================ prompts
JSON_INSTRUCTION = (
    "次の文章から注文情報を抜き出し、次のキーだけを持つ JSON オブジェクトを1つ出力してください。"
    "customer_name（文字列。姓と名の間は半角スペース1つ）、product（文字列）、quantity（整数）、"
    "unit_price_yen（整数）、order_date（YYYY-MM-DD 形式の文字列）、email（文字列）。"
    "JSON 以外は出力しないでください。\n\n文章:\n"
)


def build_prompt(task, item):
    if task == "gsm8k":
        return (f"{item['question']}\n\nSolve the problem. Show brief reasoning, then end with a final line "
                f"of the form 'Answer: <number>'.")
    if task == "humaneval":
        return ("Complete the following Python function. Return the complete function, including the signature "
                "and any imports it needs, in a single ```python code block.\n\n```python\n"
                f"{item['prompt']}```")
    if task == "jcqa":
        lines = "\n".join(f"{i}. {c}" for i, c in enumerate(item["choices"]))
        return ("次の質問に対して最も適切な選択肢を 0〜4 の番号で1つ選び、番号だけを答えてください。\n\n"
                f"質問: {item['question']}\n{lines}\n\n答え:")
    if task == "json":
        return JSON_INSTRUCTION + item["text"]
    raise ValueError(task)


def load_task(task):
    p = DATA / f"{task}.jsonl"
    if not p.exists():
        raise SystemExit(f"{p} がありません。先に prepare を実行してください")
    return [json.loads(l) for l in open(p, encoding="utf-8")]


# ============================================================ run
def chat(base_url, api_key, body, timeout):
    req = urllib.request.Request(f"{base_url}/chat/completions", data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def run(a):
    out = Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
    done = set()
    if out.exists():
        for l in open(out, encoding="utf-8"):
            r = json.loads(l)
            if "error" not in r:
                done.add(r["id"])
    tasks = [t for t in a.tasks.split(",") if t]
    with open(out, "a", encoding="utf-8") as f:
        for task in tasks:
            items = load_task(task)[: a.limit or None]
            todo = [it for it in items if it["id"] not in done]
            print(f"[{a.label}] {task}: {len(items)} 問中 {len(todo)} 問を実行")
            for k, it in enumerate(todo):
                body = {"model": a.model, "messages": [{"role": "user", "content": build_prompt(task, it)}],
                        "max_tokens": a.max_tokens, "temperature": 0, "reasoning_effort": a.effort}
                t0 = time.perf_counter()
                rec = {"id": it["id"], "task": task, "label": a.label, "effort": a.effort,
                       "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
                try:
                    resp = chat(a.base_url, a.api_key, body, a.timeout)
                    msg = resp["choices"][0]["message"]
                    rec.update({
                        "content": msg.get("content") or "",
                        "reasoning": msg.get("reasoning_content") or msg.get("reasoning") or "",
                        "finish_reason": resp["choices"][0].get("finish_reason"),
                        "usage": resp.get("usage"), "timings": resp.get("timings"),
                    })
                except (urllib.error.URLError, TimeoutError, KeyError, json.JSONDecodeError) as e:
                    rec["error"] = f"{type(e).__name__}: {e}"
                rec["elapsed_s"] = round(time.perf_counter() - t0, 3)
                f.write(json.dumps(rec, ensure_ascii=False) + "\n"); f.flush()
                if (k + 1) % 20 == 0 or k + 1 == len(todo):
                    print(f"  {task} {k + 1}/{len(todo)}  直近 {rec['elapsed_s']:.1f}s"
                          f"{'  ERROR ' + rec['error'] if 'error' in rec else ''}")


# ============================================================ score
NUM = re.compile(r"-?\d[\d,]*\.?\d*")


def _num(s):
    try:
        v = float(s.replace(",", "").rstrip("."))
        return v
    except ValueError:
        return None


def score_gsm8k(content, gold):
    m = re.findall(r"Answer\s*[:：]\s*\$?\s*(-?[\d,]*\.?\d+)", content, flags=re.I)
    cand = m[-1] if m else (NUM.findall(content)[-1] if NUM.findall(content) else None)
    if cand is None:
        return False, None
    v, g = _num(cand), _num(gold)
    return (v is not None and g is not None and abs(v - g) < 1e-6), cand


def score_jcqa(content, gold):
    m = re.search(r"[0-4]", content.translate(str.maketrans("０１２３４", "01234")))
    ans = m.group(0) if m else None
    return ans == gold, ans


def _extract_json(content):
    s = content.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", s, flags=re.S)
    if m:
        s = m.group(1)
    a, b = s.find("{"), s.rfind("}")
    if a < 0 or b < a:
        return None
    try:
        return json.loads(s[a:b + 1])
    except json.JSONDecodeError:
        return None


def score_json(content, gold):
    obj = _extract_json(content)
    if not isinstance(obj, dict):
        return False, {"parse_ok": False, "fields_correct": 0}
    correct = sum(1 for k, v in gold.items() if obj.get(k) == v)
    exact_keys = set(obj) == set(gold)
    return (correct == len(gold) and exact_keys), {"parse_ok": True, "fields_correct": correct,
                                                   "extra_keys": sorted(set(obj) - set(gold))}


def extract_code(content, item):
    blocks = re.findall(r"```(?:python|py)?\s*\n(.*?)```", content, flags=re.S)
    code = blocks[-1] if blocks else content
    if f"def {item['entry_point']}" not in code:
        code = item["prompt"] + code
    return code


RUNNER = r'''
import json, os, subprocess, sys
res = {}
for name in sorted(os.listdir("/work/progs")):
    try:
        p = subprocess.run([sys.executable, "-I", "/work/progs/" + name], cwd="/tmp",
                           capture_output=True, timeout=10)
        res[name[:-3]] = "pass" if p.returncode == 0 else "fail"
    except subprocess.TimeoutExpired:
        res[name[:-3]] = "timeout"
print(json.dumps(res))
'''


SANDBOX_IMAGE = os.environ.get("QUALITY_SANDBOX_IMAGE", "python:3.12-slim")


def run_humaneval_sandbox(programs, sandbox):
    """programs: {id: source}。ネットワークなし・読み取り専用・権限なしのコンテナで1問10秒まで実行する。"""
    if not programs:
        return {}
    d = Path(tempfile.mkdtemp(prefix="humaneval-"))
    try:
        (d / "progs").mkdir()
        for k, src in programs.items():
            (d / "progs" / f"{k}.py").write_text(src, encoding="utf-8")
        (d / "runner.py").write_text(RUNNER, encoding="utf-8")
        os.chmod(d, 0o755)
        for p in d.rglob("*"):
            os.chmod(p, 0o755 if p.is_dir() else 0o644)
        if sandbox == "docker":
            cmd = ["docker", "run", "--rm", "--pull", "never", "--network", "none", "--memory", "2g",
                   "--cpus", "4", "--pids-limit", "256", "--read-only", "--tmpfs", "/tmp:rw,size=256m",
                   "--cap-drop", "ALL", "--security-opt", "no-new-privileges", "--user", "65534:65534",
                   "-v", f"{d}:/work:ro", SANDBOX_IMAGE, "python", "/work/runner.py"]
        else:  # テスト専用。モデルの出力を素のまま実行するので、本番では使わない
            cmd = ["python3", str(d / "runner.py")]
            (d / "runner.py").write_text(RUNNER.replace("/work/", str(d) + "/").replace('cwd="/tmp"', f'cwd="{d}"'))
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60 + 15 * len(programs))
        if p.returncode != 0:
            raise SystemExit(f"サンドボックスの実行に失敗しました: {p.stderr[-2000:]}")
        return json.loads(p.stdout.strip().splitlines()[-1])
    finally:
        shutil.rmtree(d, ignore_errors=True)


def score(a):
    for path in a.files:
        rows = [json.loads(l) for l in open(path, encoding="utf-8")]
        # 同じ id は最後の記録を採用（再開時のやり直し）
        latest = {}
        for r in rows:
            latest[r["id"]] = r
        rows = list(latest.values())
        items = {t: {it["id"]: it for it in load_task(t)} for t in {r["task"] for r in rows}}
        programs = {}
        for r in rows:
            if r["task"] == "humaneval" and "error" not in r:
                it = items["humaneval"][r["id"]]
                programs[r["id"]] = extract_code(r["content"], it) + "\n\n" + it["test"] + \
                    f"\n\ncheck({it['entry_point']})\n"
        he = run_humaneval_sandbox(programs, a.sandbox)
        out = Path(path).with_name("scored.jsonl")
        with open(out, "w", encoding="utf-8") as f:
            for r in rows:
                s = {k: r.get(k) for k in ("id", "task", "label", "effort", "elapsed_s", "finish_reason")}
                u = r.get("usage") or {}
                s["completion_tokens"] = u.get("completion_tokens")
                if "error" in r:
                    s.update(correct=False, error=r["error"])
                else:
                    it = items[r["task"]][r["id"]]
                    if r["task"] == "gsm8k":
                        s["correct"], s["answer"] = score_gsm8k(r["content"], it["gold"])
                    elif r["task"] == "jcqa":
                        s["correct"], s["answer"] = score_jcqa(r["content"], it["gold"])
                    elif r["task"] == "json":
                        s["correct"], s["detail"] = score_json(r["content"], it["gold"])
                    elif r["task"] == "humaneval":
                        s["answer"] = he.get(r["id"], "missing")
                        s["correct"] = s["answer"] == "pass"
                f.write(json.dumps(s, ensure_ascii=False) + "\n")
        print(f"採点: {path} -> {out}（{len(rows)} 件）")


# ============================================================ report / compare
def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (max(0.0, c - h), min(1.0, c + h))


def report(a):
    rows = [json.loads(l) for p in a.files for l in open(p, encoding="utf-8")]
    groups = {}
    for r in rows:
        groups.setdefault((r["label"], r["task"]), []).append(r)
    print("| 構成 | 課題 | 問題数 | 正答 | 正答率 | 95%信頼区間 | エラー | 打ち切り | 1問あたり | 正答1件あたり | 出力トークン（中央値） |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for (label, task), rs in sorted(groups.items()):
        n = len(rs); k = sum(1 for r in rs if r["correct"])
        lo, hi = wilson(k, n)
        err = sum(1 for r in rs if r.get("error"))
        cut = sum(1 for r in rs if r.get("finish_reason") == "length")
        t = sum(r.get("elapsed_s") or 0 for r in rs)
        toks = [r["completion_tokens"] for r in rs if r.get("completion_tokens")]
        print(f"| {label} | {task} | {n} | {k} | {k / n * 100:.1f}% | {lo * 100:.1f}〜{hi * 100:.1f}% | {err} | {cut} | "
              f"{t / n:.1f} s | {(t / k if k else float('nan')):.1f} s | {statistics.median(toks) if toks else '-'} |")


def compare(a):
    def load(p):
        d = {}
        for l in open(p, encoding="utf-8"):
            r = json.loads(l); d[r["id"]] = r
        return d
    x, y = load(a.a), load(a.b)
    common = sorted(set(x) & set(y))
    by = {}
    for i in common:
        t = x[i]["task"]
        b = by.setdefault(t, {"n": 0, "same_answer": 0, "same_correct": 0, "both": 0, "only_a": 0, "only_b": 0})
        b["n"] += 1
        b["same_answer"] += x[i].get("answer") == y[i].get("answer") if t != "json" else \
            (x[i].get("detail") == y[i].get("detail"))
        b["same_correct"] += x[i]["correct"] == y[i]["correct"]
        b["both"] += x[i]["correct"] and y[i]["correct"]
        b["only_a"] += x[i]["correct"] and not y[i]["correct"]
        b["only_b"] += y[i]["correct"] and not x[i]["correct"]
    print(f"A = {a.a}\nB = {a.b}")
    print("| 課題 | 問題数 | 答えが一致 | 正誤が一致 | 両方正解 | A だけ正解 | B だけ正解 |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for t, b in sorted(by.items()):
        print(f"| {t} | {b['n']} | {b['same_answer'] / b['n'] * 100:.1f}% | {b['same_correct'] / b['n'] * 100:.1f}% | "
              f"{b['both']} | {b['only_a']} | {b['only_b']} |")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prepare")
    r = sub.add_parser("run")
    r.add_argument("--base-url", required=True); r.add_argument("--model", default="default")
    r.add_argument("--api-key", default="local"); r.add_argument("--label", required=True)
    r.add_argument("--tasks", default=",".join(TASKS)); r.add_argument("--limit", type=int, default=0)
    r.add_argument("--effort", default="low"); r.add_argument("--max-tokens", type=int, default=4096)
    r.add_argument("--timeout", type=float, default=900); r.add_argument("--out", required=True)
    s = sub.add_parser("score"); s.add_argument("files", nargs="+")
    s.add_argument("--sandbox", choices=["docker", "none"], default="docker")
    rp = sub.add_parser("report"); rp.add_argument("files", nargs="+")
    c = sub.add_parser("compare"); c.add_argument("a"); c.add_argument("b")
    a, rest = p.parse_known_args()
    {"prepare": prepare, "run": run, "score": score, "report": report, "compare": compare}[a.cmd](a)


if __name__ == "__main__":
    main()
