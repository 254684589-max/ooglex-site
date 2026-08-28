#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Yahoo Finance 月线收盘的共享取数器（免密钥）。

跨资产追踪、加密品类等多个管道都要画 5 年 / 10 年 / 25 年 / 全部，都需要同一份
「月线收盘」口径。取数逻辑集中在这里，各构建脚本导入使用，不各自复制一份，
以免同一口径出现两套实现、两种结果。

口径：月线收盘由数据源自己给出（interval=1mo），不由日线在本地二次聚合；
本模块不做任何插值、前向填充或平滑，取不到就抛异常交给调用方决定如何降级。
"""
import time

import requests

YF_HOSTS = ("query1.finance.yahoo.com", "query2.finance.yahoo.com")
# Yahoo 对非浏览器 UA 容易返回 429，这里伪装成浏览器
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                             "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"),
              "Accept": "application/json"}


def fetch_monthly_range(symbol, rng, timeout=15):
    """取单个代码某个区间的月线：返回按月升序的 [(YYYY-MM, close), ...]。"""
    sym = requests.utils.quote(symbol)
    last_err = ValueError("无可用月线")
    for host in YF_HOSTS:
        url = f"https://{host}/v8/finance/chart/{sym}?range={rng}&interval=1mo"
        try:
            r = requests.get(url, headers=YF_HEADERS, timeout=timeout)
            r.raise_for_status()
            res = r.json()["chart"]["result"][0]
            ts = res["timestamp"]
            closes = res["indicators"]["quote"][0]["close"]
            pts = [(time.strftime("%Y-%m", time.gmtime(t)), float(c))
                   for t, c in zip(ts, closes) if c is not None]
            if len(pts) < 2:
                raise ValueError("月线数据点不足")
            return pts
        except Exception as e:
            last_err = e
    raise last_err


def fetch_monthly(symbol, timeout=15):
    """全区间月线 + 最近十年月线合并。

    数据源对超长区间会自行降采样（部分标的退化成季度末），一次 range=max 拿不到
    逐月点；再取一次 range=10y 把最近十年补稠密，重叠月份以十年那份为准。
    两份都是同一个接口的月线收盘，不做任何本地插值。
    """
    merged = dict(fetch_monthly_range(symbol, "max", timeout=timeout))
    try:
        merged.update(dict(fetch_monthly_range(symbol, "10y", timeout=timeout)))
    except Exception:
        pass
    return sorted(merged.items())
