#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""因子变体与尝试台账。

**这个模块存在的唯一目的是防止自欺。**

看过回测结果之后再改模型，改动就带着「已经看过答案」的污染。试十个变体挑最好的
那个，它的 t 值天然偏高——即使十个全是噪声，出现至少一个 |t|>2 的概率约 37%。

所以这里做两件事：
  1. 变体必须**具名**并写进代码，不能在配置里随手改数字后跑一次就忘了；
  2. 每跑一次回测就往台账追加一条，报告页显示「这是第 N 次尝试」
     以及按 N 打折后的显著性阈值。

台账只增不改。它会让你看见自己到底试了多少次——这个数字通常比记忆中大得多。
"""

import json
import math
import os
from datetime import datetime, timezone

from config import WEIGHTS_A

HERE = os.path.dirname(os.path.abspath(__file__))
# 刻意**不**放在 output/ 或 cache/ 下：那两个目录是 gitignore 的、且会被
# 「清缓存重跑」一并删掉。台账被删掉就等于失去意义——它的价值就在于
# 「试了多少次」这个数字无法被顺手抹掉。放这里会随代码一起进版本库。
DEFAULT_LEDGER = os.path.join(HERE, "variant_ledger.json")

# 变体定义。每个都要写清「为什么试它」——理由必须来自数据，不能是「感觉」。
VARIANTS = {
    "baseline": {
        "label": "基线",
        "reason": "config.py 里冻结的原始权重",
    },
    "no-risk": {
        "label": "去掉风险块",
        "drop": ("risk",),
        "reason": "四个风险子因子三段同负且单调加深；先看拿掉它会怎样",
    },
    "flip-risk": {
        "label": "风险块反向",
        "flip": ("risk",),
        "reason": "同上，但把符号翻过来而不是丢弃——等价于「买高波动」，风险很大",
    },
    "momentum-only": {
        "label": "只用动量",
        "keep": ("momentum",),
        "reason": "隔离动量：全期 IC≈0 是段2崩溃与段1/3为正平均出来的",
    },
    "reversal-only": {
        "label": "只用反转",
        "keep": ("reversal",),
        "reason": "唯一三段同正的因子，虽然量级很小",
    },
    "no-momentum": {
        "label": "去掉动量",
        "drop": ("momentum",),
        "reason": "动量符号翻转，不稳定；看剩下的部分有没有东西",
    },
}


def resolve_weights(name, base=None):
    """按变体名解出实际使用的族权重。未知变体名直接报错，不静默回退。"""
    if name not in VARIANTS:
        raise ValueError(f"未知变体 {name!r}；可选：{'、'.join(VARIANTS)}")
    spec = VARIANTS[name]
    weights = dict(base or WEIGHTS_A)
    if spec.get("keep"):
        weights = {k: v for k, v in weights.items() if k in spec["keep"]}
    for family in spec.get("drop", ()):
        weights.pop(family, None)
    if not weights:
        raise ValueError(f"变体 {name!r} 把权重清空了")
    return weights, tuple(spec.get("flip", ()))


def apply_flips(rows, flip_families, subweights):
    """把指定族的子因子分数取反（100 − 分数），就地修改。

    在**已归一化的分位分数**上翻转，而不是在原始值上——分位是 0–100 均匀的，
    100−x 仍然是合法分位；在原始值上取负号则会改变去极值与排名的结果。
    """
    if not flip_families:
        return
    names = [n for fam in flip_families for n in subweights.get(fam, {})]
    for row in rows:
        ranked = row.get("ranked") or {}
        for name in names:
            if ranked.get(name) is not None:
                ranked[name] = 100.0 - ranked[name]


# ---------------------------------------------------------------------------
def load_ledger(path=DEFAULT_LEDGER):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def append_ledger(entry, path=DEFAULT_LEDGER):
    """追加一条尝试记录。只增不改——台账被编辑过就失去意义了。"""
    ledger = load_ledger(path)
    ledger.append(entry)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(ledger, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    return len(ledger)


def deflate(num_attempts, alpha=0.05):
    """按尝试次数打折后的 |t| 阈值，以及「至少出现一次假阳性」的概率。

    试 N 次挑最好的，等价于做 N 次独立检验。要维持整体 5% 的错误率，
    单次阈值必须收紧到 alpha/N。
    """
    from statistics import NormalDist
    n = max(1, num_attempts)
    return {
        "attempts": n,
        "anyFalsePositiveProb": 1.0 - (1.0 - 0.0455) ** n,
        "deflatedT": abs(NormalDist().inv_cdf(alpha / 2.0 / n)),
        "note": ("阈值按尝试次数收紧。这是「试到出结果为止」的唯一解药——"
                 "它让每多试一次都变贵，而不是免费。"),
    }


def summarize(ledger):
    """台账摘要：试过哪些变体、各自最好的 t 值。"""
    by_variant = {}
    for entry in ledger:
        name = entry.get("variant", "?")
        current = by_variant.get(name)
        t = entry.get("tStat")
        if current is None or (t is not None and abs(t) > abs(current.get("tStat") or 0)):
            by_variant[name] = entry
    best = None
    for entry in ledger:
        t = entry.get("tStat")
        if t is not None and (best is None or abs(t) > abs(best.get("tStat") or 0)):
            best = entry
    return {
        "total": len(ledger),
        "distinctVariants": len(by_variant),
        "best": best,
        "byVariant": [
            {"variant": k, "tStat": v.get("tStat"), "icMean": v.get("icMean"),
             "passed": v.get("passed"), "at": v.get("at")}
            for k, v in sorted(by_variant.items())
        ],
    }
