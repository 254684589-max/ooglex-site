#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AI 模型天梯取数脚本。

抓取三个公开榜单，合并写入 apps/ai-rankings/data.json：
  1) LMArena 竞技场 Elo   —— 榜单页内嵌 JSON（含厂商/协议/上下文/价格，已实测解析 370+ 模型）
  2) LiveBench 客观评测    —— 站点静态 CSV（从 JS bundle 中发现最新一期的日期 slug）
  3) Artificial Analysis   —— 官方 API（可选，需免费密钥 AA_API_KEY；未配置则跳过该轴）

容错约定（与全站取数脚本一致）：
  - 三源相互独立，单源失败不影响其余；失败轴不会沿用旧分数参与当前综合排名；
  - 三源全部失败则保留上次 data.json，绝不用空/脏数据覆盖好数据；
  - 综合分只在模型完整覆盖本次全部活跃轴时计算；各轴 min-max 归一化后按
    0.4/0.3/0.3 权重（对可用轴重新归一化）合成。
"""
import csv
import io
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
SOURCE_META = {}

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

# ---------------------------------------------------------------- 名称与厂商

ORG_CN = {  # 规范厂商名 → (中文名, 旗帜)
    "OpenAI": ("OpenAI", "🇺🇸"), "Anthropic": ("Anthropic", "🇺🇸"), "Google": ("谷歌", "🇺🇸"),
    "xAI": ("xAI", "🇺🇸"), "Meta": ("Meta", "🇺🇸"), "Mistral AI": ("Mistral", "🇫🇷"),
    "DeepSeek": ("深度求索", "🇨🇳"), "Alibaba": ("阿里巴巴", "🇨🇳"), "Moonshot AI": ("月之暗面", "🇨🇳"),
    "Zhipu AI": ("智谱", "🇨🇳"), "MiniMax": ("MiniMax", "🇨🇳"), "ByteDance": ("字节跳动", "🇨🇳"),
    "01.AI": ("零一万物", "🇨🇳"), "Tencent": ("腾讯", "🇨🇳"), "Baidu": ("百度", "🇨🇳"),
    "NVIDIA": ("英伟达", "🇺🇸"), "Amazon": ("亚马逊", "🇺🇸"), "Cohere": ("Cohere", "🇨🇦"),
    "Microsoft": ("微软", "🇺🇸"), "Reka AI": ("Reka", "🇺🇸"), "AI21 Labs": ("AI21", "🇮🇱"),
}
ORG_ALIAS = [  # 源数据里的写法（小写子串）→ 规范厂商名
    ("moonshot", "Moonshot AI"), ("alibaba", "Alibaba"), ("qwen", "Alibaba"),
    ("zhipu", "Zhipu AI"), ("z.ai", "Zhipu AI"), ("mistral", "Mistral AI"),
    ("google", "Google"), ("deepmind", "Google"), ("openai", "OpenAI"),
    ("anthropic", "Anthropic"), ("meta", "Meta"), ("deepseek", "DeepSeek"),
    ("minimax", "MiniMax"), ("bytedance", "ByteDance"), ("tencent", "Tencent"),
    ("baidu", "Baidu"), ("nvidia", "NVIDIA"), ("amazon", "Amazon"),
    ("cohere", "Cohere"), ("microsoft", "Microsoft"), ("xai", "xAI"),
    ("01", "01.AI"), ("reka", "Reka AI"), ("ai21", "AI21 Labs"),
]
ORG_GUESS = [  # 从模型名猜厂商（源数据没给时兜底）
    ("gpt", "OpenAI"), ("o3", "OpenAI"), ("o4", "OpenAI"), ("chatgpt", "OpenAI"),
    ("claude", "Anthropic"), ("gemini", "Google"), ("gemma", "Google"),
    ("grok", "xAI"), ("llama", "Meta"), ("mistral", "Mistral AI"), ("mixtral", "Mistral AI"),
    ("deepseek", "DeepSeek"), ("qwen", "Alibaba"), ("qwq", "Alibaba"),
    ("kimi", "Moonshot AI"), ("glm", "Zhipu AI"), ("minimax", "MiniMax"),
    ("doubao", "ByteDance"), ("hunyuan", "Tencent"), ("ernie", "Baidu"),
    ("command", "Cohere"), ("nemotron", "NVIDIA"), ("nova", "Amazon"), ("phi-", "Microsoft"),
]
OPEN_HINTS = ["llama", "mistral", "mixtral", "deepseek", "qwen", "qwq", "glm", "gemma",
              "kimi", "minimax", "hunyuan", "yi-", "nemotron", "phi-", "command", "oss"]
SUFFIX = r"-(thinking|preview|latest|exp|beta|instruct|chat|hf|fp8|high|low|medium|max|xhigh|mini|nano)\b"
BRAND = {"gpt": "GPT", "glm": "GLM", "claude": "Claude", "gemini": "Gemini", "qwen": "Qwen",
         "kimi": "Kimi", "deepseek": "DeepSeek", "grok": "Grok", "llama": "Llama",
         "mistral": "Mistral", "minimax": "MiniMax", "doubao": "豆包", "sol": "Sol",
         "muse": "Muse", "spark": "Spark", "pro": "Pro", "flash": "Flash", "ultra": "Ultra",
         "maverick": "Maverick", "scout": "Scout", "hunyuan": "Hunyuan", "ernie": "文心",
         "nova": "Nova", "command": "Command", "gemma": "Gemma", "mixtral": "Mixtral"}


def canon_org(raw):
    s = str(raw or "").lower().strip()
    if not s:
        return None
    for pat, org in ORG_ALIAS:
        if pat in s:
            return org
    return str(raw).strip()


def guess_org(key):
    for pat, org in ORG_GUESS:
        if pat in key:
            return org
    return None


def strip_variant_suffixes(raw):
    """Remove benchmark/runtime variant labels while preserving model family/version.

    The same model can appear as e.g. "Claude Fable 5.1 (Max)" in Arena and
    "claude-fable-5-1-max-effort" in LiveBench. These labels describe evaluation
    effort, not a distinct model family, so they must resolve to one merge key.
    """
    s = str(raw or "").lower().strip()
    s = re.sub(r"[（(].*?[)）]", "", s)
    s = re.sub(r"[\s_.]+", "-", s)
    # Strip effort / reasoning harness suffixes as one unit.
    patterns = [
        r"-(?:(?:thinking|reasoning)(?:-auto)?-)?(?:minimal|low|medium|high|xhigh|max)(?:-effort)?$",
        r"-(?:thinking|reasoning)(?:-auto)?$",
        r"-effort$",
        r"-(?:preview|latest|exp|beta|instruct|chat|hf|fp8)$",
    ]
    changed = True
    while changed:
        before = s
        for pat in patterns:
            s = re.sub(pat, "", s)
        changed = s != before
    # Provider snapshot dates should not split the same named model family.
    s = re.sub(r"-?20\d{2}-?\d{2}-?\d{2}$", "", s)
    s = re.sub(r"-?\d{8}$", "", s)
    return s.strip("-")


def norm_name(raw):
    """Raw model name → canonical merge key across leaderboard variants."""
    return strip_variant_suffixes(raw)


def display_name(raw):
    """Raw model name → display name without benchmark effort/harness suffixes."""
    s = strip_variant_suffixes(raw)
    toks, out = [t for t in re.split(r"[-_\s]+", s) if t], []
    for t in toks:
        if out and re.fullmatch(r"\d+", t) and re.fullmatch(r"\d+(\.\d+)?", out[-1].split(" ")[-1]):
            out[-1] = out[-1] + "." + t
            continue
        mb = re.match(r"([a-z]+)(\d[\d.]*)$", t)
        if t in BRAND:
            out.append(BRAND[t])
        elif mb and mb.group(1) in BRAND:
            out.append(BRAND[mb.group(1)] + mb.group(2))
        elif any(c.isdigit() for c in t) and any(c.isalpha() for c in t):
            out.append(t.upper())
        elif t.isalpha() and len(t) <= 2:
            out.append(t.upper())
        else:
            out.append(t.capitalize() if t[0].isalpha() else t)
    return " ".join(out)

def fmt_ctx(v):
    if not isinstance(v, (int, float)) or v <= 0:
        return None
    if v >= 1e6:
        return f"{round(v / 1e6, 1):g}M"
    return f"{round(v / 1e3)}K"

# ---------------------------------------------------------------- 三个数据源

def fetch_arena():
    """LMArena 文本总榜：页面内嵌（转义）JSON，含厂商/协议/上下文/价格。"""
    html = http_get("https://lmarena.ai/leaderboard/text")
    if not html:
        return None
    u = html.replace('\\\\"', '"').replace('\\"', '"')
    found = {}
    for blk in re.findall(r"\{[^{}]+\}", u):
        if '"rating":' not in blk or '"modelDisplayName":' not in blk:
            continue
        try:
            o = json.loads(blk)
        except Exception:
            continue
        name, r = o.get("modelDisplayName"), o.get("rating")
        if not name or not isinstance(r, (int, float)) or not (800 <= r <= 2000):
            continue
        k = norm_name(name)
        if not k:
            continue
        cur = found.get(k)
        if cur and cur["elo"] >= r:
            continue
        pin, pout = o.get("inputPricePerMillion"), o.get("outputPricePerMillion")
        lic = (o.get("license") or "").lower()
        found[k] = {
            "raw": name, "elo": r, "org": canon_org(o.get("modelOrganization")),
            "open": (bool(lic) and "propriet" not in lic) or None,
            "ctx": fmt_ctx(o.get("contextLength")),
            "price": round((3 * pin + pout) / 4, 2)
                     if isinstance(pin, (int, float)) and isinstance(pout, (int, float)) else None,
        }
    if len(found) >= 20:
        SOURCE_META["arena"] = {
            "ok": True,
            "count": len(found),
            "fetchedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "source": "lmarena.ai/leaderboard/text",
        }
        print(f"  Arena：解析到 {len(found)} 个模型（合并变体后）")
        return found
    SOURCE_META["arena"] = {"ok": False, "count": len(found), "reason": "parse_too_few"}
    print(f"  Arena：仅解析到 {len(found)} 个，判为失败")
    return None


def _score100(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    if x <= 1.5:
        x *= 100
    return x if 0 <= x <= 100 else None


def _livebench_overall(row, categories):
    """Return LiveBench's official-style global average.

    LiveBench weights categories equally, not individual tasks equally. The old
    implementation averaged every numeric CSV column, which overweighted
    categories containing more tasks and could shift the published ordering.
    """
    for key in ("global_average", "Global Average", "overall", "Overall"):
        if row.get(key) not in (None, ""):
            v = _score100(row.get(key))
            if v is not None:
                return v

    cat_scores = []
    if isinstance(categories, dict):
        for tasks in categories.values():
            vals = []
            for task in (tasks or []):
                v = _score100(row.get(task))
                if v is not None:
                    vals.append(v)
            if vals:
                cat_scores.append(sum(vals) / len(vals))
    if len(cat_scores) >= 3:
        return sum(cat_scores) / len(cat_scores)

    # Compatibility fallback for table formats that already expose category
    # averages but not the raw category map.
    avgs = []
    for key, value in row.items():
        lk = str(key or "").lower()
        if lk == "global_average":
            continue
        if lk.endswith("_average") or lk in ("reasoning", "coding", "mathematics", "language"):
            v = _score100(value)
            if v is not None:
                avgs.append(v)
    if len(avgs) >= 3:
        return sum(avgs) / len(avgs)
    return None


def fetch_livebench():
    """LiveBench：主页 → JS bundle → 最新一期 table_<日期>.csv。

    Score uses the benchmark's equal-weight category aggregation, matching the
    published global_average rather than a flat mean across all task columns.
    """
    home = http_get("https://livebench.ai/")
    if not home:
        SOURCE_META["livebench"] = {"ok": False, "reason": "homepage_unavailable"}
        return None
    m = re.search(r'src="\.?(/static/js/[^"]+\.js)"', home)
    if not m:
        SOURCE_META["livebench"] = {"ok": False, "reason": "bundle_not_found"}
        print("  LiveBench：未找到 JS bundle")
        return None
    js = http_get("https://livebench.ai" + m.group(1))
    if not js:
        SOURCE_META["livebench"] = {"ok": False, "reason": "bundle_unavailable"}
        return None

    meta = {}
    for slug, org, disp, rest in re.findall(
            r'"([A-Za-z0-9.\-_/]+)":\{url:"[^"]*",organization:"([^"]*)",displayName:"([^"]*)"([^{}]*)\}', js):
        info = {"org": canon_org(org), "open": "openweight:!0" in rest, "disp": disp}
        meta[norm_name(disp)] = info
        meta[norm_name(slug)] = info

    slugs = sorted(set(re.findall(r"20\d{2}[-_][01]\d[-_][0-3]\d", js)), reverse=True)
    for release in slugs[:8]:
        slug = release.replace("-", "_")
        txt = http_get(f"https://livebench.ai/table_{slug}.csv")
        if not txt or "," not in txt:
            continue

        categories = None
        cat_txt = http_get(f"https://livebench.ai/categories_{slug}.json", tries=1)
        if cat_txt:
            try:
                categories = json.loads(cat_txt)
            except Exception:
                categories = None

        try:
            rows = list(csv.DictReader(io.StringIO(txt)))
        except Exception:
            continue

        found = {}
        for row in rows:
            name = row.get("model") or row.get("Model") or next(iter(row.values()), None)
            if not name:
                continue
            overall = _livebench_overall(row, categories)
            if overall is None or not (5 <= overall <= 100):
                continue
            k = norm_name(name)
            info = meta.get(k, {})
            cur = found.get(k)
            if cur and cur["avg"] >= overall:
                continue
            found[k] = {
                "raw": info.get("disp") or name,
                "avg": round(overall, 1),
                "org": info.get("org"),
                "open": info.get("open"),
            }

        if len(found) >= 10:
            SOURCE_META["livebench"] = {
                "ok": True,
                "count": len(found),
                "release": release.replace("_", "-"),
                "fetchedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "source": f"livebench.ai/table_{slug}.csv",
                "aggregation": "mean_of_category_averages",
            }
            print(f"  LiveBench：{release} 期解析到 {len(found)} 个模型（按官方分类等权均值）")
            return found

    SOURCE_META["livebench"] = {"ok": False, "reason": "all_releases_failed"}
    print("  LiveBench：全部候选期失败")
    return None

def fetch_aa():
    """Artificial Analysis 官方 API（免费密钥，可选）。"""
    key = os.environ.get("AA_API_KEY", "").strip()
    if not key:
        SOURCE_META["aa"] = {"ok": False, "reason": "api_key_not_configured"}
        print("  AA：未配置 AA_API_KEY，跳过该轴（不会沿用旧分数参与综合排名）")
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
        price = (row.get("pricing") or {}).get("price_1m_blended_3_to_1")
        found[norm_name(name)] = {
            "raw": name, "aa": round(float(idx), 1),
            "org": canon_org((row.get("model_creator") or {}).get("name")),
            "price": round(price, 2) if isinstance(price, (int, float)) else None,
        }
    if len(found) >= 10:
        SOURCE_META["aa"] = {
            "ok": True,
            "count": len(found),
            "fetchedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "source": "artificialanalysis.ai/api/v2/data/llms/models",
        }
        print(f"  AA：解析到 {len(found)} 个模型")
        return found
    SOURCE_META["aa"] = {"ok": False, "reason": "parse_too_few", "count": len(found)}
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

    keys = set()
    for src in (arena, lb, aa):
        if src:
            keys |= set(src.keys())

    models = []
    for k in keys:
        a, l, x = (arena or {}).get(k), (lb or {}).get(k), (aa or {}).get(k)
        org = (a or {}).get("org") or (l or {}).get("org") or (x or {}).get("org") or guess_org(k)
        if not org:
            continue  # 认不出厂商的长尾模型不进榜
        org_cn, flag = ORG_CN.get(org, (org, "🌐"))
        is_open = (a or {}).get("open")
        if is_open is None:
            is_open = (l or {}).get("open")
        if is_open is None:
            is_open = any(h in k for h in OPEN_HINTS)
        m = {
            "id": k,
            "name": display_name((a or l or x)["raw"]),
            "org": org, "orgCn": org_cn, "flag": flag, "open": bool(is_open),
            "arena": round(a["elo"]) if a else None,
            "livebench": l["avg"] if l else None,
            "aa": x["aa"] if x else None,
            "ctx": (a or {}).get("ctx"),
            "price": (a or {}).get("price") if a and a.get("price") is not None else (x or {}).get("price"),
        }
        # Source scores are never carried forward when that source failed:
        # stale benchmark values must not contaminate a "current" composite.
        # Non-ranking metadata may still fall back to the previous snapshot.
        old = prev_models.get(k)
        if old:
            if not m["ctx"]:
                m["ctx"] = old.get("ctx")
            if m["price"] is None:
                m["price"] = old.get("price")
        models.append(m)

    # 综合参考分：只使用本次成功抓取的数据源，并要求模型在全部
    # 当前活跃轴上都有数据，避免把 2 榜/3 榜或新旧数据混在同一排名里。
    axis_data = {"arena": arena, "livebench": lb, "aa": aa}
    active_axes = [k for k, src in axis_data.items() if src is not None]
    base_wts = {"arena": 0.4, "livebench": 0.3, "aa": 0.3}

    def ranges(key):
        vs = [m[key] for m in models if isinstance(m[key], (int, float))]
        return (min(vs), max(vs)) if vs else None

    rng = {k: ranges(k) for k in active_axes}
    active_weight_total = sum(base_wts[k] for k in active_axes) or 1.0

    for m in models:
        normalized = {}
        for k in active_axes:
            r = rng.get(k)
            if isinstance(m.get(k), (int, float)) and r and r[1] > r[0]:
                normalized[k] = (m[k] - r[0]) / (r[1] - r[0])

        full_coverage = len(active_axes) >= 2 and len(normalized) == len(active_axes)
        if full_coverage:
            combo = sum(normalized[k] * base_wts[k] for k in active_axes) / active_weight_total
            m["combo"] = round(combo * 100, 1)
            m["comboAxes"] = len(active_axes)
            m["_selection"] = 2.0 + combo
        else:
            m["combo"] = None
            m["comboAxes"] = len(normalized)
            m["_selection"] = max(normalized.values(), default=0.0)

    models.sort(key=lambda m: (m["_selection"], m.get("arena") or 0, m.get("livebench") or 0), reverse=True)
    models = models[:40]
    for m in models:
        m.pop("_selection", None)

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
        "note": "数据每日自动抓取；综合排名只使用本次成功更新且模型完整覆盖的活跃数据源，"
                "不会用旧分数填补失败的数据源。各榜口径不同，跨榜绝对值不可直接比较。",
        "sources": (prev or {}).get("sources") or {},
        "extraSources": (prev or {}).get("extraSources") or [],
        "axisStatus": {"arena": bool(arena), "livebench": bool(lb), "aa": bool(aa)},
        "sourceMeta": SOURCE_META,
        "comboAxes": active_axes,
        "comboWeights": {k: round(base_wts[k] / active_weight_total, 4) for k in active_axes},
        "comboMethod": "minmax_weighted_full_coverage_only",
        "models": models,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"完成：写入 {len(models)} 个模型 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(build())
