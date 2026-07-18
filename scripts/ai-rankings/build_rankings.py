#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AI 模型天梯取数脚本。

抓取三个公开榜单，合并写入 apps/ai-rankings/data.json：
  1) LMArena 竞技场 Elo   —— 榜单页内嵌 JSON（含厂商/协议/上下文/价格，已实测解析 370+ 模型）
  2) LiveBench 客观评测    —— 站点静态 CSV（从 JS bundle 中发现最新一期的日期 slug）
  3) Artificial Analysis   —— 官方 API（可选，需免费密钥 AA_API_KEY；未配置则跳过该轴）

容错约定（与全站取数脚本一致）：
  - 三源相互独立，单源失败不影响其余；该轴逐模型沿用上次 data.json 的值；
  - 三源全部失败则保留上次 data.json，绝不用空/脏数据覆盖好数据；
  - 结果按「综合参考分」排序（三轴各自 min-max 归一化后加权 0.4/0.3/0.3，
    至少两榜有数据才计综合分，单榜模型排在其后）。
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


def norm_name(raw):
    """原始模型名 → 合并键：小写、去日期戳/后缀变体、点归一为连字符。"""
    s = str(raw or "").lower().strip()
    s = re.sub(r"[（(].*?[)）]", "", s)
    s = re.sub(r"-?\d{8}$", "", s)
    s = re.sub(SUFFIX, "", s)
    s = re.sub(r"[\s_.]+", "-", s)
    return s.strip("-")


def display_name(raw):
    """原始模型名 → 展示名：去后缀变体，分词美化（数字段用 . 连接）。"""
    s = str(raw or "").strip()
    s = re.sub(r"-?\d{8}$", "", s)
    s = re.sub(SUFFIX, "", s.lower())
    toks, out = [t for t in re.split(r"[-_\s]+", s) if t], []
    for t in toks:
        if out and re.fullmatch(r"\d+", t) and re.fullmatch(r"\d+(\.\d+)?", out[-1].split(" ")[-1]):
            out[-1] = out[-1] + "." + t
            continue
        if t in BRAND:
            out.append(BRAND[t])
        elif any(c.isdigit() for c in t) and any(c.isalpha() for c in t):
            out.append(t.upper())  # 235b → 235B / a22b → A22B / k3 → K3
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
        print(f"  Arena：解析到 {len(found)} 个模型（合并变体后）")
        return found
    print(f"  Arena：仅解析到 {len(found)} 个，判为失败")
    return None


def fetch_livebench():
    """LiveBench：主页 → JS bundle → 最新一期 table_<日期>.csv。"""
    home = http_get("https://livebench.ai/")
    if not home:
        return None
    m = re.search(r'src="\.?(/static/js/[^"]+\.js)"', home)
    if not m:
        print("  LiveBench：未找到 JS bundle")
        return None
    js = http_get("https://livebench.ai" + m.group(1))
    if not js:
        return None
    # 模型元数据（厂商 / 是否开源权重）
    meta = {}
    for slug, org, disp, rest in re.findall(
            r'"([A-Za-z0-9.\-_/]+)":\{url:"[^"]*",organization:"([^"]*)",displayName:"([^"]*)"([^{}]*)\}', js):
        info = {"org": canon_org(org), "open": "openweight:!0" in rest, "disp": disp}
        meta[norm_name(disp)] = info
        meta[norm_name(slug)] = info
    # 最新一期日期 slug（bundle 内出现的 20xx-xx-xx，从新到旧尝试）
    slugs = sorted(set(re.findall(r"20\d{2}[-_][01]\d[-_][0-3]\d", js)), reverse=True)
    for s in slugs[:6]:
        s2 = s.replace("-", "_")
        txt = http_get(f"https://livebench.ai/table_{s2}.csv")
        if not txt or "," not in txt:
            continue
        found = {}
        try:
            rows = list(csv.DictReader(io.StringIO(txt)))
        except Exception:
            continue
        for row in rows:
            name = row.get("model") or row.get("Model") or next(iter(row.values()), None)
            nums = []
            for k2, v in row.items():
                if k2 in ("model", "Model") or v is None:
                    continue
                try:
                    nums.append(float(v))
                except (TypeError, ValueError):
                    pass
            if not name or len(nums) < 3:
                continue
            avg = sum(nums) / len(nums)
            if avg <= 1.5:
                avg *= 100
            if not (5 <= avg <= 100):
                continue
            k = norm_name(name)
            info = meta.get(k, {})
            cur = found.get(k)
            if cur and cur["avg"] >= avg:
                continue
            found[k] = {"raw": info.get("disp") or name, "avg": round(avg, 1),
                        "org": info.get("org"), "open": info.get("open")}
        if len(found) >= 10:
            print(f"  LiveBench：{s} 期解析到 {len(found)} 个模型")
            return found
    print("  LiveBench：全部候选期失败")
    return None


def fetch_aa():
    """Artificial Analysis 官方 API（免费密钥，可选）。"""
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
        price = (row.get("pricing") or {}).get("price_1m_blended_3_to_1")
        found[norm_name(name)] = {
            "raw": name, "aa": round(float(idx), 1),
            "org": canon_org((row.get("model_creator") or {}).get("name")),
            "price": round(price, 2) if isinstance(price, (int, float)) else None,
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
        # 某轴本次整体失败 → 逐模型沿用上次值；ctx 也回填
        old = prev_models.get(k)
        if old:
            if arena is None:
                m["arena"] = old.get("arena")
            if lb is None:
                m["livebench"] = old.get("livebench")
            if aa is None:
                m["aa"] = old.get("aa")
            if not m["ctx"]:
                m["ctx"] = old.get("ctx")
            if m["price"] is None:
                m["price"] = old.get("price")
        models.append(m)

    # 综合参考分（与前端同口径）：≥2 榜才计综合，单榜模型排在其后
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
        "axisStatus": {"arena": bool(arena), "livebench": bool(lb), "aa": bool(aa)},
        "models": models,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"完成：写入 {len(models)} 个模型 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(build())
