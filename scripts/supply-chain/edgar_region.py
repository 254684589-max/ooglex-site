#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 EDGAR 的地区字段折成「国别 + 下级地区」。

## 为什么需要这一步

EDGAR 的 `stateOrCountryDescription` 混着三种东西，直接当国别用会错得很难看：

- **加拿大省名**：`Ontario, Canada` / `British Columbia, Canada` /
  `Canada (Federal Level)`。实测 147 家外国发行人里 46 家是加拿大，
  却被拆成 6 行，「按国别」的表里加拿大出现六次。
- **美国州的两字母代码**：描述字段缺失时回落到原始代码，于是
  爱尔康（瑞士）显示 `TX`、壳牌（英荷）显示 `DC`、Stratasys（以色列）
  显示 `MN`——**营业地址是美国办公室，不是这家公司的国别**。
- **空**：台积电、本田、沃达丰、英美烟草都是空的。

所以「营业地址」这个字段本身就不该拿来回答「这家公司是哪国的」。

## 改用注册地，并说清它的局限

按优先级取 `stateOfIncorporation`（公司依哪国法律存在）→ 营业地址 → 通讯地址，
每家记下 `countryBasis`，页面照实标。注册地也有它的偏差：开曼、泽西、卢森堡
的控股架构会把公司记到避税地而不是实际总部——**这一条必须写在页面上，
不能靠猜「它其实是中国公司」去修正**。没有出处的修正就是编造。

## 代码表从 EDGAR 自己的数据里长出来，不硬编

同一个代码在别家申报里往往带着描述（`F5` ↔ `TAIWAN`）。因此先扫一遍全部
输入，把所有见过的「代码 ↔ 描述」配对收集起来，再拿这张表去补那些只有代码
没有描述的公司。表是 SEC 自己给的，不是我记的——记错一个代码就等于把一家
公司放到别的国家去。表里没有的代码保持未归类，不猜。
"""
from __future__ import annotations

import importlib.util
import os
import re


def _countries() -> dict[str, str]:
    """复用 form_sd_parse 里那张 201 条的国名表，不另抄一份。

    抄一份的代价是漂移：那边加一个国家，这边不知道，于是同一个国名在
    冶炼厂页和公司页给出两个答案。
    """
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "form_sd_parse.py")
    spec = importlib.util.spec_from_file_location("_form_sd_parse_for_region", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.COUNTRIES


COUNTRIES = _countries()

# 美国州与属地的两字母邮政代码。EDGAR 用同一套代码表示美国州，
# 出现这些代码只说明「这条地址在美国」，对外国发行人而言通常是它的美国办公室。
US_STATES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI",
    "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN",
    "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
    "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
    "WV", "WI", "WY", "PR", "VI", "GU", "AS", "MP",
}

# 「<下级地区>, <国家>」与「<国家> (Federal Level)」两种写法，
# 都是 EDGAR 描述字段里实际出现过的形态，不是推测的。
_FEDERAL = re.compile(r"^(.*?)\s*\(Federal Level\)\s*$", re.I)


def split_region(description: str | None) -> tuple[str | None, str | None]:
    """把一条描述折成 (国家, 下级地区)。认不出就原样当国家返回。

    **只在逗号后面确实是个认得出的国家时才拆。** 一上来按最后一个逗号无脑拆，
    `Korea, Republic of` 会被拆成一个叫「Republic of」的国家——ISO 的倒装写法
    （`X, Republic of` / `X, Province of China` / `X, Plurinational State of`）
    和 EDGAR 的「省, 国」写法长得一模一样，只能靠「拆出来的那半是不是国家」
    来分。判据用的就是国名表本身，不另立规则。

    >>> split_region("Ontario, Canada")
    ('Canada', 'Ontario')
    >>> split_region("Canada (Federal Level)")
    ('Canada', None)
    >>> split_region("Israel")
    ('Israel', None)
    >>> split_region("Korea, Republic of")
    ('Korea, Republic of', None)
    >>> split_region("Taiwan, Province of China")
    ('Taiwan, Province of China', None)
    """
    text = (description or "").strip()
    if not text:
        return None, None
    federal = _FEDERAL.match(text)
    if federal:
        return federal.group(1).strip() or None, None
    if "," in text:
        head, _, tail = text.rpartition(",")
        country = tail.strip()
        if country and head.strip() and country.lower() in COUNTRIES:
            return country, head.strip()
    return text, None


def build_code_map(records) -> dict[str, str]:
    """扫全部输入，收集 EDGAR 自己给出的「代码 → 描述」。

    records 是若干 (code, description) 对。同一代码出现多个不同描述时
    取最常见的那个——真出现分歧说明这个代码不可靠，宁可让调用方看见。
    """
    seen: dict[str, dict[str, int]] = {}
    for code, description in records:
        code = (code or "").strip().upper()
        description = (description or "").strip()
        if not code or not description:
            continue
        seen.setdefault(code, {})
        seen[code][description] = seen[code].get(description, 0) + 1
    table: dict[str, str] = {}
    for code, counts in seen.items():
        table[code] = max(sorted(counts), key=lambda d: counts[d])
    return table


def describe(code: str | None, description: str | None,
             code_map: dict[str, str]) -> str | None:
    """拿到这条地区的描述文本：优先用它自带的，缺了就查代码表。

    描述字段里**也可能直接躺着一个两字母代码**——壳牌那条
    `stateOfIncorporationDescription` 就是字符串 "DC"。所以拿到描述之后
    仍要过一遍代码表，不能因为「有描述」就当它是国名。
    """
    text = (description or "").strip()
    if text and not (len(text) == 2 and text.upper() in US_STATES):
        return text
    key = (text or code or "").strip().upper()
    if not key:
        return None
    if key in code_map:
        return code_map[key]
    if key in US_STATES:
        # 是美国州代码。**这一池是外国私人发行人**（报 20-F／40-F），
        # 真在美国注册的公司报的是 10-K 而不是 20-F，所以这里出现美国州
        # 代码基本都是 SEC 记录里的美国办公室或代理人，不是这家公司的国别。
        # 返回代码本身，由 resolve_country 判定不可用、换下一个字段。
        return key
    return None


def resolve_country(meta: dict, code_map: dict[str, str]) -> dict:
    """定这家公司的国别，并说明这个结论是从哪个字段来的。

    顺序是**注册地优先**：营业地址回答的是「办公室在哪」，对在美上市的外国
    发行人来说那往往是它的美国办公室（爱尔康 TX、壳牌 DC、Stratasys MN），
    拿来当国别是错的。注册地回答的是「依哪国法律成立」，偏差在控股架构
    （开曼／泽西／卢森堡），页面照实标注即可。
    """
    addresses = meta.get("addresses") or {}
    attempts = [
        ("state-of-incorporation",
         meta.get("stateOfIncorporation"),
         meta.get("stateOfIncorporationDescription")),
        ("business-address",
         (addresses.get("business") or {}).get("stateOrCountry"),
         (addresses.get("business") or {}).get("stateOrCountryDescription")),
        ("mailing-address",
         (addresses.get("mailing") or {}).get("stateOrCountry"),
         (addresses.get("mailing") or {}).get("stateOrCountryDescription")),
    ]
    rejected: list[str] = []
    for basis, code, description in attempts:
        text = describe(code, description, code_map)
        if not text:
            continue
        country, region = split_region(text)
        if not country:
            continue
        if len(country) == 2 and country.upper() in US_STATES:
            # 只能确定到「美国某个州」。对这一池来说那不是国别（见 describe），
            # 硬写成美国会把壳牌说成美国公司。记下来，换下一个字段。
            rejected.append(f"{basis}={country.upper()}")
            continue
        return {"country": country, "region": region, "countryBasis": basis,
                "countryCode": (code or "").strip().upper() or None,
                "countryRejected": rejected or None}
    return {"country": None, "region": None, "countryBasis": None,
            "countryCode": None, "countryRejected": rejected or None}


def address_pairs(meta: dict):
    """这家公司贡献给代码表的全部「代码 ↔ 描述」配对。"""
    addresses = meta.get("addresses") or {}
    yield (meta.get("stateOfIncorporation"),
           meta.get("stateOfIncorporationDescription"))
    for key in ("business", "mailing"):
        block = addresses.get(key) or {}
        yield (block.get("stateOrCountry"), block.get("stateOrCountryDescription"))
