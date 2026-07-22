#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""临时诊断：打印 OFR STFM / HFM 各数据集的真实序列结构，用于精修 build_ofr.py 的匹配逻辑。
仅在 Actions 上跑一次看日志，用完即删（连同 ofr_diag.yml）。不写任何文件。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ofr as b  # noqa: E402


def show(title, url):
    print("\n\n########## %s\n########## %s" % (title, url))
    try:
        data = b.get_json(url)
    except Exception as e:  # noqa: BLE001
        print("  FETCH FAIL:", repr(e))
        return
    if isinstance(data, list):
        print("  (list) 前 40 项:", str(data[:40])[:800])
        return
    seen = set()
    n = 0
    for root in b.dataset_roots(data):
        if not isinstance(root, dict):
            continue
        for k, v in root.items():
            if k in seen:
                continue
            pairs = b.deep_pairs(v)
            if not pairs:
                # 无时间序列的键，打印其字符串内容片段（可能是元数据/说明）
                if n < 60 and isinstance(v, (str, int, float)):
                    print("  [meta] %-28s = %s" % (str(k)[:28], str(v)[:70]))
                continue
            seen.add(k)
            strs = []
            b.collect_strings(v, strs)
            meta = " | ".join(s for s in strs if s != k)[:90]
            d, val = b.latest(pairs)
            print("  %-30s last=%s=%-14s n=%-4d %s" % (str(k)[:30], d, round(val, 4), len(pairs), meta))
            n += 1
            if n >= 60:
                print("  … (截断)")
                return


def search(title, url):
    print("\n\n########## SEARCH %s\n########## %s" % (title, url))
    try:
        data = b.get_json(url)
    except Exception as e:  # noqa: BLE001
        print("  FAIL:", repr(e)); return
    print(str(data)[:1500])


STFM = b.STFM
HF = b.STFM_HF
show("STFM datasets 列表", STFM + "/metadata/datasets")
show("HFM datasets 列表", HF + "/metadata/datasets")
show("STFM fnyr（找 SOFR 利率 mnemonic）", STFM + "/series/dataset?dataset=fnyr")
show("STFM mmf（看是否含总规模 AUM）", STFM + "/series/dataset?dataset=mmf")
show("HFM fpf（找合格对冲基金 GAV/NAV）", HF + "/series/dataset?dataset=fpf")
search("STFM 搜 money market fund total", STFM + "/metadata/search?query=money%20market%20fund")
search("HFM 搜 gross asset hedge", HF + "/metadata/search?query=gross%20asset")
print("\n\n########## DONE")
