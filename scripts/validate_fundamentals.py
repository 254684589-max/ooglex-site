#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""基本面数据的契约校验。

这份数据最容易出的错不是算错，是**把缺的说成有的**：
  · 取不到的字段写 0（0 是一个有意义的值，null 才是「没有」）；
  · 负权益算出的 PB、负 EPS 算出的 PE 被当成「便宜」摆出去；
  · 只标一个日期，让人把「今天的价格 ÷ 上一期报表」读成当前值；
  · 非美申报人没有数据，却不说明原因。

所以这里逐条查这四类，并核对比率与报表项能对得上（现算的东西必须能复算）。

数据文件不存在时**跳过而不失败** —— 管道是手动触发的，owner 还没跑第一次的时候
这份校验不该把 CI 弄红。文件一旦存在，就必须全部通过。

用法：python3 scripts/validate_fundamentals.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATH = ROOT / "apps" / "companies" / "fundamentals.json"

_failures: list[str] = []
_checks = 0


def require(cond, message):
    global _checks
    _checks += 1
    if not cond:
        _failures.append(message)


def num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


SRC = ROOT / "apps" / "companies" / "fundamentals-source.json"


def check_source_record():
    """许可与选源记录必须在册，且必须如实标出「推定而非核实」。"""
    require(SRC.is_file(), "缺少 apps/companies/fundamentals-source.json（选源与许可记录）")
    if not SRC.is_file():
        return
    r = json.loads(SRC.read_text(encoding="utf-8"))
    sel = r.get("selection") or {}
    require(sel.get("source"), "选源记录缺 source")
    require(sel.get("documentationUrl", "").startswith("https://"), "选源记录缺文档链接")
    require(isinstance(sel.get("rationale"), list) and sel["rationale"],
            "选源记录必须写明为什么选它")
    require(isinstance(sel.get("rejected"), list) and sel["rejected"],
            "选源记录必须写明否决了哪些候选、为什么——否则看不出这是权衡过的")
    ver = r.get("verification") or {}
    require(ver.get("status") == "reasoned-not-fetched",
            "条款是推定的而非逐条读过，verification.status 必须如实写成 reasoned-not-fetched")
    require("无外网" in str(ver.get("why", "")), "必须写明为什么没能核实")
    require(isinstance(ver.get("ownerShouldConfirm"), list) and ver["ownerShouldConfirm"],
            "必须列出仍需 owner 确认的事项")
    terms = r.get("terms") or {}
    require(terms.get("userAgentRequired") is True and terms.get("userAgentContactSource"),
            "SEC 要求 User-Agent 带联系方式，记录里必须写明它从哪来（不得写死在仓库）")
    require("SEC_CONTACT" in str(terms.get("userAgentContactSource")),
            "联系方式应来自仓库变量 SEC_CONTACT")
    require(terms.get("rateLimitImplemented"), "必须记录实现的限速")
    use = r.get("useCase") or {}
    require(use.get("rawDataStored") is True and use.get("publicApiRedistribution") is True,
            "本站落盘并公开分发，这两项必须如实为 true（与嵌入展示的先例不同）")
    require(isinstance(r.get("safeguards"), list) and len(r["safeguards"]) >= 4,
            "必须列出数据保护措施")
    # 联系邮箱绝不能出现在仓库里
    for f in (SRC, ROOT / "scripts" / "fundamentals" / "adapter_sec.py",
              ROOT / ".github" / "workflows" / "fundamentals.yml"):
        if f.is_file():
            txt = f.read_text(encoding="utf-8")
            require("@ooglex.com" not in txt and "@gmail" not in txt,
                    f"{f.name} 里出现了具体邮箱——联系方式必须由 SEC_CONTACT 提供，不写进仓库")


def main() -> int:
    check_source_record()
    if not PATH.is_file():
        print("apps/companies/fundamentals.json 还不存在 —— 管道是手动触发的，"
              "owner 尚未跑第一次。数据部分跳过（不算失败），选源记录仍已校验。")
        return report()

    d = json.loads(PATH.read_text(encoding="utf-8"))

    # ── 文件级出处四要素 ──────────────────────────────────────────────────
    for k in ("source", "asOf", "updatedAt", "frequency", "status"):
        require(d.get(k), f"文件级缺少 {k}")
    require("SEC" in str(d.get("source", "")), "来源应指明 SEC")
    require(d.get("frequency") == "quarterly", "报表是季/年频，frequency 应为 quarterly")
    require(d.get("sourceUrl", "").startswith("https://"), "sourceUrl 应为 https 链接")

    # ── 口径必须写在数据里，不能只写在页面上 ────────────────────────────────
    m = d.get("method")
    require(isinstance(m, dict), "缺少 method 段：比率是现算的，公式必须随数据一起给出")
    if isinstance(m, dict):
        for k in ("pe", "pb", "ps", "roe", "netMargin", "debtToAssets"):
            require(m.get(k), f"method 段缺少 {k} 的公式")
        require(m.get("nonPositiveDenominator"),
                "method 段必须写明分母非正时不给数")
    note = str(d.get("note", ""))
    for frag in ("滞后", "statementEnd", "priceAsOf", "不构成投资建议"):
        require(frag in note, f"note 缺少必要说明：{frag}")
    require("美国申报人" in note or "非美" in note, "note 必须写明覆盖面只有美国申报人")
    require("null" in note or "不是 0" in note, "note 必须写明缺的字段是 null 而不是 0")

    # ── 逐行 ───────────────────────────────────────────────────────────────
    rows = d.get("rows")
    require(isinstance(rows, list) and rows, "rows 应为非空数组")
    if not isinstance(rows, list):
        return report()

    RATIOS = ("pe", "pb", "ps", "roe", "netMargin", "debtToAssets")
    zero_filled, bad_pb, bad_pe, no_reason, no_meta, mismatch = [], [], [], [], [], []
    with_ratio = 0

    for r in rows:
        if not isinstance(r, dict):
            continue
        sym = r.get("symbol", "?")
        meta = r.get("dataMeta")
        if not isinstance(meta, dict) or not meta.get("source") or not meta.get("status"):
            no_meta.append(sym)

        if not r.get("available"):
            if not r.get("reason"):
                no_reason.append(sym)
            continue

        raw = r.get("raw") or {}
        if any(r.get(k) is not None for k in RATIOS):
            with_ratio += 1

        # 缺值不得写成 0
        for k in RATIOS:
            if r.get(k) == 0:
                zero_filled.append(f"{sym}.{k}")

        # 负权益不得给 PB；负 EPS 不得给 PE
        if num(raw.get("equity")) and raw["equity"] <= 0 and r.get("pb") is not None:
            bad_pb.append(sym)
        if num(raw.get("epsDiluted")) and raw["epsDiluted"] <= 0 and r.get("pe") is not None:
            bad_pe.append(sym)

        # 两个日期都要有：今天的价格 ÷ 上一期报表，读者必须能对照
        if r.get("pe") is not None or r.get("pb") is not None:
            if not r.get("statementEnd"):
                mismatch.append(f"{sym} 缺 statementEnd")

        # 现算的必须能复算：ROE = 净利 / 权益
        if num(raw.get("netIncome")) and num(raw.get("equity")) and raw["equity"] > 0 \
                and num(r.get("roe")):
            want = raw["netIncome"] / raw["equity"] * 100
            if abs(want - r["roe"]) > 0.01:
                mismatch.append(f"{sym} ROE 复算不符：{r['roe']:.4f} vs {want:.4f}")

    require(not zero_filled,
            f"有 {len(zero_filled)} 处把缺值写成了 0（0 是有意义的值，缺应为 null）：{zero_filled[:5]}")
    require(not bad_pb,
            f"有 {len(bad_pb)} 家权益非正却给了 PB —— 负权益的 PB 不是「便宜」：{bad_pb[:5]}")
    require(not bad_pe,
            f"有 {len(bad_pe)} 家 EPS 非正却给了 PE：{bad_pe[:5]}")
    require(not no_reason,
            f"有 {len(no_reason)} 行 available=false 却没写原因：{no_reason[:5]}")
    require(not no_meta, f"有 {len(no_meta)} 行缺逐条 dataMeta：{no_meta[:5]}")
    require(not mismatch, f"复算或日期不符 {len(mismatch)} 处：{mismatch[:5]}")
    require(with_ratio >= 50,
            f"能算出比率的只有 {with_ratio} 家 —— 低于 50 家说明取数出了问题")
    require(d.get("withRatio") == with_ratio,
            f"withRatio 与逐行统计不符：{d.get('withRatio')} vs {with_ratio}")
    require(d.get("count") == len(rows),
            f"count 与 rows 长度不符：{d.get('count')} vs {len(rows)}")

    dq = d.get("dataQuality")
    require(isinstance(dq, dict) and dq.get("total") == len(rows),
            "dataQuality 摘要缺失或与 rows 不符")

    return report()


def report() -> int:
    if _failures:
        print(f"基本面契约：{len(_failures)} / {_checks} 条不通过", file=sys.stderr)
        for f in _failures:
            print("  ✗ " + f, file=sys.stderr)
        return 1
    print(f"基本面契约：{_checks} 条全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
