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
import re
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


def check_adapter_decoding():
    """适配器的解码与异常收敛 —— 用桩把 urlopen 换掉，不需要外网。

    这一节是为一次真实事故加的：第一版在请求头里发了
    `Accept-Encoding: gzip, deflate` 却没写解压（`urllib` 不像 requests
    那样自动解压），SEC 照头返回 gzip 字节流，`json.loads` 抛
    `UnicodeDecodeError: 'utf-8' codec can't decode byte 0x8b in position 1`。

    两条教训各对应一组断言：
      1. **别发自己没实现的头。** 现在只声明 gzip（deflate 有两种封装要猜），
         并且除了看 Content-Encoding 还嗅一次魔数（过代理时头可能被剥掉）。
      2. **一切失败必须收敛成 AdapterError。** 上层只捕获 AdapterError 才会走
         「保留上一份 JSON 不覆盖」那条路；漏出别的异常型，脚本会带 traceback
         崩掉，那条保护路径就被绕过了 —— 当时正是这样绕过去的。

    这类 bug 在没有外网的开发容器里对所有既有检查都是隐形的，所以必须用桩钉住。
    """
    import gzip as _gzip
    import importlib.util
    import json as _json

    ad = ROOT / "scripts" / "fundamentals" / "adapter_sec.py"
    require(ad.is_file(), "缺少 scripts/fundamentals/adapter_sec.py")
    if not ad.is_file():
        return
    src = ad.read_text(encoding="utf-8")
    # 只看 Accept-Encoding 这一行的**值**：整文件搜 "deflate" 会被注释里
    # 「为什么去掉 deflate」那句话误伤 —— 实测就误报过一次。
    hdr = re.search(r'"Accept-Encoding"\s*:\s*"([^"]*)"', src)
    require(hdr is not None, "adapter 里找不到 Accept-Encoding 头，解析可能已失效")
    if hdr:
        require("deflate" not in hdr.group(1),
                f"请求头声明了 deflate（实际 {hdr.group(1)!r}）—— 它有 zlib 包装与裸流"
                "两种封装，而解压只实现了 gzip。只声明自己处理得了的编码")
    require("gzip.decompress" in src, "必须真的解压 gzip，不能只在头里声明")
    require("GZIP_MAGIC" in src or "x1f" in src,
            "除了 Content-Encoding 还要嗅魔数：过代理时头可能被剥掉而正文仍是压缩的")

    spec = importlib.util.spec_from_file_location("adapter_sec_probe", ad)
    m = importlib.util.module_from_spec(spec)
    sys.modules["adapter_sec_probe"] = m
    import os as _os
    keep = _os.environ.get("SEC_CONTACT")
    _os.environ["SEC_CONTACT"] = "contract-test@example.invalid"
    try:
        spec.loader.exec_module(m)
        m.MIN_INTERVAL = 0

        class _Resp:
            def __init__(self, body, headers):
                self._b, self.headers = body, headers
            def read(self):
                return self._b
            def __enter__(self):
                return self
            def __exit__(self, *a):
                return False

        def stub(body, headers):
            m.urlopen = lambda req, timeout=None: _Resp(body, headers)

        URL = "https://data.sec.gov/contract-probe.json"
        want = {"0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."}}
        plain = _json.dumps(want).encode()
        gz = _gzip.compress(plain)

        def decodes(body, headers, label):
            stub(body, headers)
            try:
                require(m._get(URL) == want, f"{label}：解出的内容不对")
            except Exception as exc:
                require(False, f"{label}：抛了 {type(exc).__name__}: {exc}")

        decodes(gz, {"Content-Encoding": "gzip"}, "gzip 正文 + gzip 头（SEC 实际返回的情形）")
        decodes(gz, {}, "gzip 正文但头被剥掉，须靠魔数救回")
        decodes(plain, {}, "未压缩正文不得被误当成压缩流")

        def is_adapter_error(body, headers, label):
            stub(body, headers)
            try:
                m._get(URL)
                require(False, f"{label}：该抛却没抛")
            except m.AdapterError:
                require(True, "")
            except Exception as exc:
                require(False, f"{label}：漏出了 {type(exc).__name__}，"
                               "非 AdapterError 会绕过「保留上一份」的保护路径")

        is_adapter_error(b"\x1f\x8b" + b"garbage", {"Content-Encoding": "gzip"},
                         "声明 gzip 但正文坏掉")
        is_adapter_error(b"\xff\xfe\x00bad", {}, "非 UTF-8 的非压缩垃圾")

        # 上面两条都命中了显式的 handler（gzip 解不开 / UnicodeDecodeError），
        # 打不到最后那个 `except Exception` 兜底。这一条专打兜底：让解析阶段
        # 抛一个谁都没预料到的异常型，它也必须变成 AdapterError。
        # 兜底漏一个异常型，「保留上一份 JSON」那条保护路径就会被绕过。
        import types as _types
        real_json = m.json
        m.json = _types.SimpleNamespace(
            loads=lambda b: (_ for _ in ()).throw(RuntimeError("模拟未预期的解析异常")),
            JSONDecodeError=real_json.JSONDecodeError)
        try:
            is_adapter_error(plain, {}, "解析阶段抛出未预期的异常型（专打兜底分支）")
        finally:
            m.json = real_json

        seen = {}
        m.urlopen = lambda req, timeout=None: (seen.update(req.headers), _Resp(plain, {}))[1]
        m._get(URL)
        require(seen.get("Accept-encoding") == "gzip",
                f"Accept-Encoding 应只声明 gzip，实际 {seen.get('Accept-encoding')!r}")
        require("contract-test@example.invalid" in seen.get("User-agent", ""),
                "User-Agent 必须带 SEC_CONTACT 提供的联系方式")

        # 没设 SEC_CONTACT 就不许发请求
        _os.environ.pop("SEC_CONTACT", None)
        try:
            m._contact()
            require(False, "没设 SEC_CONTACT 时 _contact() 应当拒绝")
        except m.AdapterError:
            require(True, "")
    finally:
        if keep is None:
            _os.environ.pop("SEC_CONTACT", None)
        else:
            _os.environ["SEC_CONTACT"] = keep


def check_bail_path():
    """三处闸门必须走同一个出口，且把原因写进运行摘要。"""
    b = ROOT / "scripts" / "fundamentals" / "build_fundamentals.py"
    require(b.is_file(), "缺少 build_fundamentals.py")
    if not b.is_file():
        return
    src = b.read_text(encoding="utf-8")
    require("def bail(" in src, "三处闸门应收敛到一个 bail() 出口")
    require(src.count("bail(") >= 4, f"闸门没有全部走 bail()（只找到 {src.count('bail(')} 处）")
    # 不能只查「文件里出现过 ::error::」—— bail() 里有三处，删掉报原因那一处
    # 其余两处仍在，子串还在，断言就假通过了（这种松断言今天已踩过三次）。
    require('print(f"::error::{reason}")' in src,
            "闸门的 reason 必须自己用 ::error:: 打出来 —— 否则 GitHub 运行摘要里只有"
            "「Process completed with exit code 1」，等于把真正的原因藏起来")
    require(src.count("::error::") >= 3,
            f"bail() 三条输出（原因／保留上一份／没有上一份）都应进运行摘要，"
            f"当前只有 {src.count('::error::')} 处")
    require("except Exception as exc" in src,
            "adapter 之外万一漏出别的异常型，也不能带 traceback 崩掉、"
            "绕过「保留上一份」的保护路径")


def main() -> int:
    check_source_record()
    check_adapter_decoding()
    check_bail_path()
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

        # 现算的必须能复算：ROE = 净利 / **同财年末**权益（不是最新那一期）
        if num(raw.get("netIncome")) and num(raw.get("equityAligned")) \
                and raw["equityAligned"] > 0 and num(r.get("roe")):
            want = raw["netIncome"] / raw["equityAligned"] * 100
            if abs(want - r["roe"]) > 0.01:
                mismatch.append(f"{sym} ROE 复算不符：{r['roe']:.4f} vs {want:.4f}")
        # 反过来钉住：ROE 不得用最新那一期权益（跨期）算出来
        if num(raw.get("netIncome")) and num(r.get("roe")) and num(raw.get("equity")) \
                and num(raw.get("equityAligned")) and raw["equity"] > 0 \
                and abs(raw["equity"] - raw["equityAligned"]) > 1:
            wrong = raw["netIncome"] / raw["equity"] * 100
            if abs(wrong - r["roe"]) < 0.01:
                mismatch.append(
                    f"{sym} ROE 是用最新一期权益算的（跨期）—— 分母必须与分子同财年")

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

    # ── 「像不像真的」：直接复用 build 里的那套常量与函数，不在这里抄第二份 ──
    # 抄一份的话，两边迟早对不上，而对不上的时候没人知道该信哪个。
    import importlib.util as _ilu
    bf = ROOT / "scripts" / "fundamentals" / "build_fundamentals.py"
    require(bf.is_file(), "缺少 build_fundamentals.py")
    if bf.is_file():
        _spec = _ilu.spec_from_file_location("build_fundamentals_probe", bf)
        _m = _ilu.module_from_spec(_spec)
        sys.modules["build_fundamentals_probe"] = _m
        _spec.loader.exec_module(_m)
        require(hasattr(_m, "sanity_check") and hasattr(_m, "SANE_MEDIAN"),
                "build 端必须暴露 sanity_check 与 SANE_MEDIAN，契约要复用同一套口径")
        if hasattr(_m, "sanity_check"):
            for bad_msg in _m.sanity_check(rows):
                require(False, "合理性检查：" + bad_msg)
        require(getattr(_m, "MARKET_CAP_UNIT", None) == 1e9,
                "站内 marketCap 是十亿美元（build_companies.py 写的是 cap_usd/1e9），"
                "换算常量必须是 1e9 —— 这个假设没写在 JSON 里，只能在这里钉住")
        # 反过来也钉一次：换算若被去掉，PB 会掉到 1e-9 量级
        pbs = [r["pb"] for r in rows if isinstance(r.get("pb"), (int, float))]
        if pbs:
            mid = sorted(pbs)[len(pbs) // 2]
            require(mid > 0.01,
                    f"PB 中位数 {mid:.4g} 小得不像真的 —— 站内市值是十亿美元、"
                    "SEC 权益是原始美元，忘了换算就会差 1e9 个量级")

    # 同类报表项必须取同一个期间：营收来自一个年度、净利来自另一个年度，
    # 拼出来的利润率是假的。
    pu = d.get("periodsUsed") or {}
    require(isinstance(pu, dict) and pu, "必须记录实际用了哪些期间（periodsUsed）")
    dur = {pu.get(k) for k in ("Revenues", "RevenueFromContractWithCustomerExcludingAssessedTax",
                               "NetIncomeLoss", "EarningsPerShareDiluted") if pu.get(k)}
    inst = {pu.get(k) for k in ("StockholdersEquity", "Assets", "Liabilities") if pu.get(k)}
    require(len(dur) <= 1,
            f"期间类（营收／净利／每股收益）取了多个期间 {sorted(dur)} —— "
            "同类必须同期，否则利润率是两个年度拼的")
    require(len(inst) <= 1,
            f"时点类（权益／资产／负债）取了多个期间 {sorted(inst)} —— 同类必须同期")
    # 利润表与资产负债表可能挑到不同财年（实测 CY2024 vs CY2025Q4I）。这不是错，
    # 但 ROE 必须另取同财年的权益当分母，所以那一期要在册。
    if dur and inst and pu.get("_equityAligned"):
        yr = sorted(dur)[0][2:6]
        require(pu["_equityAligned"] == f"CY{yr}Q4I",
                f"ROE 用的权益期 {pu['_equityAligned']} 与利润表期 {sorted(dur)[0]} 不同财年")
    has_roe = any(r.get("roe") is not None for r in rows if isinstance(r, dict))
    require(not has_roe or pu.get("_equityAligned"),
            "给出了 ROE 却没记录同期权益取自哪一期 —— 分母口径必须可核")
    require(("同财年" in str(m.get("roe", ""))) if isinstance(m, dict) else False,
            "method 段必须写明 ROE 的分母是同财年末权益，不是最新那一期")
    require("分母口径不同" in note or "各自写明" in note,
            "PB 用最新一期权益、ROE 用同期权益，两者分母不同，note 必须说明")
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
