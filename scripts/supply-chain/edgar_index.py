#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EDGAR 季度全量索引的读取与解析。**探针与取数脚本共用这一份实现。**

拆出来的理由和 `skip_reason` 当初拆出来一样：两处各写一套的话，改了一处另一处
就开始说假话。这里的解析器已经被离线夹具逐条钉住（含「公司名里有连续空格」
那种会把定宽解析骗过去的负例），共用等于两处同时受保护。

索引本身：https://www.sec.gov/Archives/edgar/full-index/<年>/QTR<季>/master.idx
管道分隔，一行一份申报。**选它而不是定宽的 form.idx**，因为定宽在长公司名上
会串列。全量索引是公共领域数据，与本板块其余 SEC 取数同源同规矩：
声明身份的 User-Agent、远低于每秒 10 次的间隔。
"""
from __future__ import annotations

import json
import os
import re
import zlib
from datetime import date
from urllib import error, request

TIMEOUT = 60
GAP = 0.20                     # SEC 建议不超过 10 请求/秒，这里远低于
READ_CHUNK = 1 << 20

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# 20-F 非加拿大外国私人发行人年报；40-F 是加拿大 MJDS 制度下的对应表。
FOREIGN_ANNUAL = {"20-F", "20-F/A", "40-F", "40-F/A"}
FOREIGN_INTERIM = {"6-K", "6-K/A"}
SD_FORMS = {"SD", "SD/A"}

INDEX_URL = "https://www.sec.gov/Archives/edgar/full-index/{year}/QTR{quarter}/master.idx"
SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik:010d}.json"
TICKERS_EXCHANGE_URL = "https://www.sec.gov/files/company_tickers_exchange.json"


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    return f"{type(exc).__name__}: {exc}"

def _get_json(url: str) -> dict:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read(20_000_000).decode("utf-8", "replace"))

def stream_lines(url: str, stats: dict):
    """按行流式读取一份季度索引。索引有几十兆，不整份读进内存。

    请求 gzip 能把下载量压到五分之一，但服务端**不一定给**——所以按响应头判断，
    两条路都走得通，并把实际走的哪条记进 stats 供人核对。
    """
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "text/plain",
                                        "Accept-Encoding": "gzip"})
    with request.urlopen(req, timeout=TIMEOUT) as resp:
        gz = "gzip" in (resp.headers.get("Content-Encoding") or "").lower()
        stats["gzip"] = gz
        dec = zlib.decompressobj(16 + zlib.MAX_WBITS) if gz else None
        tail = b""
        while True:
            chunk = resp.read(READ_CHUNK)
            if not chunk:
                break
            stats["bytes"] = stats.get("bytes", 0) + len(chunk)
            if dec is not None:
                chunk = dec.decompress(chunk)
            parts = (tail + chunk).split(b"\n")
            tail = parts.pop()
            for line in parts:
                yield line.decode("utf-8", "replace")
        if dec is not None:
            rest = dec.flush()
            if rest:
                parts = (tail + rest).split(b"\n")
                tail = parts.pop()
                for line in parts:
                    yield line.decode("utf-8", "replace")
        if tail.strip():
            yield tail.decode("utf-8", "replace")

# master.idx 每行： CIK|公司名|表格类型|申报日期|归档路径
# 用管道分隔的这份而不是定宽的 form.idx——定宽在长公司名上会串列，此前吃过亏。
_ROW = re.compile(r"^\s*(\d{1,10})\|([^|]*)\|([^|]{1,40})\|(\d{4}-\d{2}-\d{2})\|(\S.*?)\s*$")


def parse_index_line(line: str) -> dict | None:
    """解析一行 master.idx。解析不了就返回 None——由调用方计数并报出来，不吞掉。"""
    match = _ROW.match(line)
    if not match:
        return None
    return {
        "cik": int(match.group(1)),
        "name": match.group(2).strip(),
        "form": match.group(3).strip().upper(),
        "date": match.group(4),
        "path": match.group(5).strip(),
    }

def recent_quarters(today: date, count: int) -> list[tuple[int, int]]:
    """从今天往回数 count 个季度（含本季度）。"""
    out = []
    year, quarter = today.year, (today.month - 1) // 3 + 1
    for _ in range(count):
        out.append((year, quarter))
        quarter -= 1
        if quarter == 0:
            year, quarter = year - 1, 4
    return out

def accession_dir(cik: int, path: str) -> str | None:
    """从 master.idx 的归档路径推出申报目录地址。

    路径形如 edgar/data/1046179/0001046179-25-000012.txt，
    目录是同名去掉横杠的那一层。
    """
    match = re.search(r"/(\d{10}-\d{2}-\d{6})\.txt$", path)
    if not match:
        return None
    return (f"https://www.sec.gov/Archives/edgar/data/{cik}/"
            f"{match.group(1).replace('-', '')}/")
