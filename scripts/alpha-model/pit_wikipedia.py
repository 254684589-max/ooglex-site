#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从维基百科取 S&P 500 的当前成分与带日期的增删记录。

选它是因为**免费、无需密钥、且带日期**——这是重建 point-in-time 成分股
最低成本的可行路径。代价是记录越早越不全，所以 ``pit_universe`` 会
逐年统计条数并给出可靠边界，而不是假装重建结果处处可信。

解析与取数分开：``parse_constituents`` 与 ``parse_changes`` 是纯函数，
可以对着固定样本离线断言，不依赖网络。仓库没有 lxml/BeautifulSoup，
因此用正则解析表格——维基的表格标记足够规整，但也因此必须有测试兜底。
"""

import html as html_mod
import re

import requests

from config import HTTP_TIMEOUT, YF_HEADERS
from pit_universe import _parse_date, normalize_ticker

PAGE_URL = "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"
SOURCE_NAME = "Wikipedia · List of S&P 500 companies"

_TABLE_RE = re.compile(r"<table[^>]*\bclass=\"[^\"]*wikitable[^\"]*\"[^>]*>(.*?)</table>",
                       re.S | re.I)
_ROW_RE = re.compile(r"<tr[^>]*>(.*?)</tr>", re.S | re.I)
_CELL_RE = re.compile(r"<t[dh][^>]*>(.*?)</t[dh]>", re.S | re.I)
_TAG_RE = re.compile(r"<[^>]+>")


def _text(cell):
    """去标签、解实体、压空白。维基的单元格里常有 <a>、<span>、脚注。"""
    cleaned = re.sub(r"<sup[^>]*>.*?</sup>", "", cell, flags=re.S | re.I)  # 去脚注
    cleaned = _TAG_RE.sub("", cleaned)
    cleaned = html_mod.unescape(cleaned)
    return re.sub(r"\s+", " ", cleaned).strip()


def _tables(page_html):
    return [_TABLE_RE.match(m.group(0)).group(1) if False else m.group(1)
            for m in _TABLE_RE.finditer(page_html)]


def _rows(table_html):
    out = []
    for match in _ROW_RE.finditer(table_html):
        cells = [_text(c) for c in _CELL_RE.findall(match.group(1))]
        if cells:
            out.append(cells)
    return out


def parse_constituents(page_html, min_members=400):
    """解析当前成分表。返回 (代码列表, {代码: 行业})。

    认表方式是看表头是否同时含 Symbol 与 GICS Sector，不依赖表的位置或 id——
    维基改版时位置会变，表头相对稳定。
    """
    for table in _tables(page_html):
        rows = _rows(table)
        if not rows:
            continue
        header = [h.lower() for h in rows[0]]
        if not any("symbol" in h for h in header):
            continue
        if not any("gics sector" in h or h == "sector" for h in header):
            continue
        sym_i = next(i for i, h in enumerate(header) if "symbol" in h)
        sec_i = next(i for i, h in enumerate(header)
                     if "gics sector" in h or h == "sector")
        tickers, sectors = [], {}
        for row in rows[1:]:
            if len(row) <= max(sym_i, sec_i):
                continue
            ticker = normalize_ticker(row[sym_i])
            if not ticker:
                continue
            tickers.append(ticker)
            sectors[ticker] = row[sec_i]
        # S&P 500 应有约 500 只；明显偏少说明认错了表（维基页面上还有别的表）。
        # min_members 可调低用于测试。
        if len(tickers) >= min_members:
            return tickers, sectors
    return [], {}


def parse_changes(page_html):
    """解析「Selected changes to the list of S&P 500 components」表。

    返回 [{"date","added","removed","reason"}, …]，按日期升序。

    **必须处理 rowspan**：同一天有多笔调整时，日期单元格会跨行合并，
    后续行少一个单元格。这里用「首格解析不出日期就沿用上一行日期」来兜底——
    比解析 rowspan 属性更耐维基的标记变化。漏掉这一步会让当天第二笔之后的
    调整全部错位，且不会报错。
    """
    for table in _tables(page_html):
        rows = _rows(table)
        if len(rows) < 3:
            continue
        header = " ".join(rows[0]).lower()
        if "date" not in header or "added" not in header or "removed" not in header:
            continue

        changes, last_date = [], None
        for row in rows[1:]:
            if not row:
                continue
            when = _parse_date(row[0])
            if when is not None:
                last_date = when
                fields = row[1:]
            else:
                fields = row              # rowspan 合并行：日期沿用上一行
            if last_date is None or len(fields) < 2:
                continue
            added = normalize_ticker(fields[0])
            removed = normalize_ticker(fields[2]) if len(fields) > 2 else None
            reason = fields[4] if len(fields) > 4 else ""
            if not added and not removed:
                continue
            changes.append({
                "date": last_date.isoformat(),
                "added": added,
                "removed": removed,
                "reason": reason[:120],
            })
        if changes:
            changes.sort(key=lambda c: c["date"])
            return changes
    return []


def fetch(session=None):
    """抓页面并解析。返回 (代码列表, 行业映射, 变更记录)。失败抛异常。"""
    session = session or requests.Session()
    session.headers.update({**YF_HEADERS,
                            "User-Agent": "OoglexAlphaModel/1.0 (research; contact via repo)"})
    response = session.get(PAGE_URL, timeout=HTTP_TIMEOUT)
    response.raise_for_status()
    page = response.text
    tickers, sectors = parse_constituents(page)
    if not tickers:
        raise RuntimeError("未能在页面里认出成分表——维基可能改版，请检查解析器")
    changes = parse_changes(page)
    if not changes:
        raise RuntimeError("未能认出变更表；没有变更记录就无法重建 PIT 成分")
    return tickers, sectors, changes


# ---------------------------------------------------------------------------
def main():
    """命令行：抓取并落盘成 pit_membership.json。

        python3 scripts/alpha-model/pit_wikipedia.py
    """
    import argparse
    from datetime import date as _date

    from pit_universe import DEFAULT_PATH, build_snapshots, coverage_report, save

    parser = argparse.ArgumentParser(description="抓取 S&P 500 的 PIT 成分股")
    parser.add_argument("--out", default=DEFAULT_PATH)
    args = parser.parse_args()

    print(f"抓取 {PAGE_URL} …")
    tickers, sectors, changes = fetch()
    print(f"  当前成分 {len(tickers)} 只，变更记录 {len(changes)} 条")

    path = save(args.out, tickers, _date.today().isoformat(), changes,
                SOURCE_NAME, sectors)
    snapshots = build_snapshots(tickers, _date.today().isoformat(), changes)
    report = coverage_report(snapshots, changes)

    print(f"\n已写入 {path}")
    print(f"  快照 {report['snapshots']} 份，"
          f"成分数范围 {report['membershipSizeRange']}")
    print(f"  变更记录覆盖 {report['earliestChange']} → {report['latestChange']}")
    print(f"  可靠起点 {report['reliableFrom']}"
          f"（每年少于 {report['minChangesPerYear']} 条即判为不可靠）")
    print("\n逐年变更条数：")
    for year, count in sorted(report["changesPerYear"].items()):
        flag = "  " if count >= report["minChangesPerYear"] else " ← 记录不全"
        print(f"    {year}  {count:>3}{flag}")
    print("\n早于「可靠起点」的回测结论不应采信——那段的成分重建缺口太大。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
