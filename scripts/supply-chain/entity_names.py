#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""公司名的规范化与严格同名判定，供各探针共用。

**为什么单独成一个模块。** 阶段 3 的探针里写了一套「只去法律形式后缀」的
规范化，离线验过 27 条；阶段 4 要拿公司名去 FCC 的库里对，需要**完全同一套**
口径。复制粘贴会立刻制造「同一件事有两个来源」——那正是第二十六轮刚踩过的坑
（`noFilingByStage` 读抽取器原始状态、契约读节点最终状态，对不上）。

## 两条界线，都是实测定下来的，不是想出来的

**一、只去法律形式后缀，不去业务描述词。** 仓库里 `probe_ex21_subsidiaries.py`
的 `norm()` 连 holdings／group／technologies／international 一起去掉——用在
「拿公司名去第三方库里对」的场景会把「General Dynamics Information Technology」
折成「general dynamics」，**自己制造假阳性**。

**二、界线在「这个词说的是法律形式，还是说的是业务」。** 第一版把 `company`
当业务描述词排除在外，于是「3M Company」与「3M CO」判成两家——那是同一家的
两种写法，**方向是假阴性**。`company` 是法律形式，要去；`technologies` 是业务，
不去。

## 搜索串与判定串是两件事

`core_query()` 给**搜索**用：第三方库多是子串搜索，串越长越严，拿完整法定名
去搜会把候选压掉一大半（阶段 3 实测 100 家里只剩 11 家）。
`norm()` 给**判定**用：搜得宽不等于判得松，锚定那一步仍要求严格相等。
"""
from __future__ import annotations

import re

# 法律形式后缀。**业务描述词（holdings／group／technologies／international／
# industries）一个都不在这里**，加进来就是在制造同名碰撞。
LEGAL_SUFFIX = re.compile(
    r"\b(?:co|company|corp|corporation|inc|incorporated|ltd|limited|llc|"
    r"l\.?l\.?c|lp|llp|plc|ag|nv|n\.?v|bv|b\.?v|sa|s\.?a|se|spa|srl|gmbh|"
    r"kg|kgaa|kk|pte|pty|sdn|bhd|oyj|oy|ab|a\/s|as)\b\.?", re.I)
# 领头的 the 要去掉：「THE BOEING COMPANY」与「Boeing Co」是同一家。
# **只去领头的**——名字中间的 the 不能碰。
LEADING_THE = re.compile(r"^the\s+", re.I)
PUNCT = re.compile(r"[^0-9a-z ]+")

# 政府与非企业实体。锚到这些上一律算错配，不算命中。
NOT_A_COMPANY = re.compile(
    r"\b(?:university|college|school\s+district|school|academy|"
    r"city\s+of|county\s+of|town\s+of|state\s+of|"
    r"department\s+of|board\s+of|authority|commission|district|"
    r"regents|trustees|foundation|institute|hospital\s+district)\b", re.I)


def norm(name) -> str:
    """判定用：转小写、去标点、去法律后缀、去领头 the、折空白。"""
    text = str(name or "").lower()
    text = PUNCT.sub(" ", text)
    text = LEGAL_SUFFIX.sub(" ", text)
    text = LEADING_THE.sub("", " ".join(text.split()))
    return " ".join(text.split())


def core_query(name: str) -> str:
    """搜索用：去法律后缀与领头 the，保留原始大小写与空格。"""
    text = LEADING_THE.sub("", str(name or "").strip())
    words = [w for w in text.split()
             if not LEGAL_SUFFIX.fullmatch(w.strip(".,"))]
    # 后缀去掉之后前一个词常常还挂着逗号（「Leidos Holdings, Inc.」→
    # 「Leidos Holdings,」），逗号留在搜索串里等于多要求一个字符匹配。
    kept = " ".join(w.rstrip(",") for w in words).strip()
    return re.sub(r"[,\s]+$", "", kept) or text


def same_entity(a, b) -> bool:
    """严格同名。空串一律不算相等——否则两个取不到名字的东西会被判成同一家。"""
    left, right = norm(a), norm(b)
    return bool(left) and left == right
