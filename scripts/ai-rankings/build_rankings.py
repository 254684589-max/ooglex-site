#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AI 模型天梯取数脚本。

抓取三个公开榜单，合并写入 apps/ai-rankings/data.json：
  1) LMArena 竞技场 Elo   —— 页面内嵌 JSON（多候选正则解析）
  2) LiveBench 客观评测    —— 站点静态 JSON（多候选路径）
  3) Artificial Analysis   —— 官方 API（可选，需免费密钥 AA_API_KEY；未配置则跳过该轴）

容错约定（与全站取数脚本一致）：
  - 三源相互独立，单源失败不影响其余；该轴沿用上次 data.json 的值；
  - 三源全部失败则保留上次 data.json，绝不用空/脏数据覆盖好数据；
  - 结果按「综合参考分」排序（三轴各自 min-max 归一化后加权 0.4/0.3/0.3）。
"""
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "apps", "ai-rankings", "data.json")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
TIMEOUT = 25

# ---------------------------------------------------------------- 基础请求

def http_get(url, headers=None, tries=2):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=dict({"User-Agent": UA}, **(headers or {})))
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            print(f"  ! GET {url} 失败（{i + 1}/{tries}）：{e}")
            time.sleep(2 * (i + 1))
    return None

# ---------------------------------------------------------------- 模型注册表
# pat：小写子串匹配（按序尝试，先命中先得）；open：是否开源权重
ORG_CN = {
    "OpenAI": ("OpenAI", "🇺🇸"), "Anthropic": ("Anthropic", "🇺🇸"), "Google": ("谷歌", "🇺🇸"),
    "xAI": ("xAI", "🇺🇸"), "Meta": ("Meta", "🇺🇸"), "Mistral AI": ("Mistral", "🇫🇷"),
    "DeepSeek": ("深度求索", "🇨🇳"), "Alibaba": ("阿里巴巴", "🇨🇳"), "Moonshot AI": ("月之暗面", "🇨🇳"),
    "Zhipu AI": ("智谱", "🇨🇳"), "MiniMax": ("MiniMax", "🇨🇳"), "ByteDance": ("字节跳动", "🇨🇳"),
    "01.AI": ("零一万物", "🇨🇳"), "Tencent": ("腾讯", "🇨🇳"), "Baidu": ("百度", "🇨🇳"),
    "NVIDIA": ("英伟达", "🇺🇸"), "Amazon": ("亚马逊", "🇺🇸"), "Cohere": ("Cohere", "🇨🇦"),
    "Microsoft": ("微软", "🇺🇸"), "Reka AI": ("Reka", "🇺🇸"), "AI21 Labs": ("AI21", "🇮🇱"),
}
ORG_GUESS = [  # 从原始模型名猜厂商
    ("gpt", "OpenAI"), ("o3", "OpenAI"), ("o4", "OpenAI"), ("chatgpt", "OpenAI"),
    ("claude", "Anthropic"), ("gemini", "Google"), ("gemma", "Google"),
    ("grok", "xAI"), ("llama", "Meta"), ("mistral", "Mistral AI"), ("mixtral", "Mistral AI"),
    ("deepseek", "DeepSeek"), ("qwen", "Alibaba"), ("qwq", "Alibaba"),
    ("kimi", "Moonshot AI"), ("moonshot", "Moonshot AI"), ("glm", "Zhipu AI"),
    ("minimax", "MiniMax"), ("doubao", "ByteDance"), ("seed", "ByteDance"),
    ("hunyuan", "Tencent"), ("ernie", "Baidu"), ("yi-", "01.AI"),
    ("command", "Cohere"), ("nemotron", "NVIDIA"), ("nova", "Amazon"), ("phi-", "Microsoft"),
]
OPEN_HINTS = ["llama", "mistral", "mixtral", "deepseek", "qwen", "qwq", "glm", "gemma",
              "kimi", "minimax", "hunyuan", "yi-", "nemotron", "phi-", "command", "oss"]


def norm_name(raw):
    """原始模型名 → 匹配键：小写，去日期戳/常见后缀。"""
    s = str(raw or "").lower().strip()
    s = re.sub(r"[（(].*?[)）]", "", s)
    s = re.sub(r"-?\d{8}$", "", s)
    s = re.sub(r"-(thinking|preview|latest|exp|beta|instruct|chat|hf|fp8|high|low|medium|max|xhigh)\b", "", s)
    s = re.sub(r"[\s_]+", "-", s)
    return s.strip("-")


def guess_org(key):
    for pat, org in ORG_GUESS:
        if pat in key:
            return org
    return None


def guess_open(key):
    return any(h in key for h in OPEN_HINTS)


def pretty_name(raw):
    """原始名 → 展示名：保留原样但去掉尾部日期戳。"""
    s = re.sub(r"-?\d{8}$", "", str(raw).strip())
    return s

# ---------------------------------------------------------------- 三个数据源

def fetch_arena():
    """LMArena：文本竞技场 Elo。返回 {norm_key: {"name":…, "elo":…}}"""
    pages = [
        "https://lmarena.ai/leaderboard/text",
        "https://lmarena.ai/leaderboard",
        "https://arena.ai/leaderboard/",
    ]
    for url in pages:
        html = http_get(url)
        if not html:
            continue
        # 页面内嵌 JSON：兼容 modelDisplayName/model_name + rating/score/elo 几种字段拼法
        pats = [
            r'"(?:modelDisplayName|model_display_name)"\s*:\s*"([^"]+)"[^{}]*?"(?:rating|score|elo)"\s*:\s*([0-9]{3,4}(?:\.[0-9]+)?)',
            r'"(?:model|model_name|name)"\s*:\s*"([^"]+)"[^{}]*?"(?:rating|elo|arena_score)"\s*:\s*([0-9]{3,4}(?:\.[0-9]+)?)',
        ]
        for pat in pats:
            found = {}
            for name, elo in re.findall(pat, html):
                elo = float(elo)
                if 800 <= elo <= 2000:
                    k = norm_name(name)
                    if k and (k not in found or elo > found[k]["elo"]):
                        found[k] = {"name": pretty_name(name), "elo": elo}
            if len(found) >= 20:
                print(f"  Arena：{url} 解析到 {len(found)} 个模型")
                return found
    print("  Arena：全部候选源失败")
    return None


def fetch_livebench():
    """LiveBench：全局均分。返回 {norm_key: {"name":…, "avg":…}}"""
    urls = [
        "https://livebench.ai/table_data.json",
        "https://livebench.ai/leaderboard_data.json",
        "https://livebench.ai/categories_data.json",
        "https://raw.githubusercontent.com/LiveBench/LiveBench/main/leaderboard/table_data.json",
    ]
    for url in urls:
        txt = http_get(url)
        if not txt:
            continue
        try:
            data = json.loads(txt)
        except Exception:
            continue
        rows = data if isinstance(data, list) else data.get("rows") or data.get("data") or []
        found = {}
        for row in rows:
            if not isinstance(row, dict):
                continue
            name = row.get("model") or row.get("model_name") or row.get("Model") or row.get("name")
            avg = None
            for f in ("global_average", "Global Average", "average", "avg", "score"):
                if isinstance(row.get(f), (int, float)):
                    avg = float(row[f])
                    break
            if avg is None:  # 没有均分字段就对数值列求平均
                nums = [v for k, v in row.items()
                        if isinstance(v, (int, float)) and k.lower() not in ("rank", "index")]
                if len(nums) >= 3:
                    avg = sum(nums) / len(nums)
            if name and avg is not None:
                if avg <= 1.5:  # 0-1 口径统一换算到百分制
                    avg *= 100
                if 5 <= avg <= 100:
                    found[norm_name(name)] = {"name": pretty_name(name), "avg": round(avg, 1)}
        if len(found) >= 10:
            print(f"  LiveBench：{url} 解析到 {len(found)} 个模型")
            return found
    print("  LiveBench：全部候选源失败")
    return None


def fetch_aa():
    """Artificial Analysis 官方 API（免费密钥，可选）。返回 {norm_key: {...}}"""
    key = os.environ.get("AA_API_KEY", "").strip()
    if not key:
        print("  AA：未配置 AA_API_KEY，跳过该轴（可在仓库 Secrets 里配置免费密钥启用）")
        return None
    txt = http_get("https://artificialanalysis.ai/api/v2/data/llms/models",
                   headers={"x-api-key": key})
    if not txt:
        return None
    try:
        rows = json.loads(txt).get("data") or []
    except Exception:
        return None
    found = {}
    for row in rows:
        name = row.get("name") or row.get("slug")
        ev = row.get("evaluations") or {}
        idx = ev.get("artificial_analysis_intelligence_index")
        if not name or not isinstance(idx, (int, float)):
            continue
        org = (row.get("model_creator") or {}).get("name")
        price = (row.get("pricing") or {}).get("price_1m_blended_3_to_1")
        found[norm_name(name)] = {
            "name": pretty_name(name), "aa": round(float(idx), 1),
            "org": org, "price": round(price, 2) if isinstance(price, (int, float)) else None,
        }
    if len(found) >= 10:
        print(f"  AA：解析到 {len(found)} 个模型")
        return found
    return None

# ---------------------------------------------------------------- 合并

def load_prev():
    try:
        with open(OUT, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def build():
    print("抓取 LMArena…"); arena = fetch_arena()
    print("抓取 LiveBench…"); lb = fetch_livebench()
    print("抓取 Artificial Analysis…"); aa = fetch_aa()

    prev = load_prev()
    prev_models = {m["id"]: m for m in (prev or {}).get("models", [])}

    if not arena and not lb and not aa:
        if prev:
            print("三源全部失败：保留上次 data.json 不覆盖")
            return 0
        print("三源全部失败且无历史数据")
        return 1

    # 以三源出现过的模型为全集，逐个合成
    keys = set()
    for src in (arena, lb, aa):
        if src:
            keys |= set(src.keys())

    models = []
    for k in keys:
        a, l, x = (arena or {}).get(k), (lb or {}).get(k), (aa or {}).get(k)
        raw_name = (x or a or l)["name"]
        org = (x or {}).get("org") or guess_org(k)
        if not org:
            continue  # 认不出厂商的长尾模型不进榜
        org_cn, flag = ORG_CN.get(org, (org, "🌐"))
        m = {
            "id": k, "name": raw_name, "org": org, "orgCn": org_cn, "flag": flag,
            "open": guess_open(k),
            "arena": round(a["elo"]) if a else None,
            "livebench": l["avg"] if l else None,
            "aa": x["aa"] if x else None,
            "ctx": None,
            "price": (x or {}).get("price"),
        }
        # 该轴本次整体失败 → 沿用上次值；上次的 ctx 也保留
        old = prev_models.get(k)
        if old:
            if arena is None:
                m["arena"] = old.get("arena")
            if lb is None:
                m["livebench"] = old.get("livebench")
            if aa is None:
                m["aa"] = old.get("aa")
                m["price"] = m["price"] if m["price"] is not None else old.get("price")
            m["ctx"] = old.get("ctx")
        models.append(m)

    # 综合参考分（与前端同口径）用于排序与截断
    def ranges(key):
        vs = [m[key] for m in models if isinstance(m[key], (int, float))]
        return (min(vs), max(vs)) if vs else None
    rng = {k: ranges(k) for k in ("arena", "livebench", "aa")}
    wts = {"arena": 0.4, "livebench": 0.3, "aa": 0.3}
    for m in models:
        s = w = 0.0
        n_axes = 0
        best_single = 0.0
        for k, wt in wts.items():
            r = rng[k]
            if isinstance(m[k], (int, float)) and r and r[1] > r[0]:
                nv = (m[k] - r[0]) / (r[1] - r[0])
                s += nv * wt
                w += wt
                n_axes += 1
                best_single = max(best_single, nv)
        # 与前端同口径：综合分要求至少两个榜有数据；单榜模型排在综合分之后、按单榜归一值排序
        m["_combo"] = (1 + s / w) if n_axes >= 2 else best_single
    models.sort(key=lambda m: m["_combo"], reverse=True)
    models = models[:40]
    for m in models:
        m.pop("_combo", None)

    if len(models) < 8:
        if prev:
            print(f"有效模型过少（{len(models)}）：保留上次 data.json")
            return 0
        return 1

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out = {
        "updatedAt": now,
        "asOf": now[:10],
        "seed": False,
        "note": "数据每日自动抓取自 LMArena / LiveBench / Artificial Analysis 公开榜单；"
                "各榜口径不同，不能跨榜直接比较绝对值。仅供参考。",
        "sources": (prev or {}).get("sources") or {},
        "extraSources": (prev or {}).get("extraSources") or [],
        "axisStatus": {
            "arena": bool(arena), "livebench": bool(lb), "aa": bool(aa),
        },
        "models": models,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"完成：写入 {len(models)} 个模型 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(build())
