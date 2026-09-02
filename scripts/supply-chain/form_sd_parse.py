#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解析 Form SD 冲突矿产报告里的冶炼厂／精炼厂清单。

## 这个模块只做解析，不联网

拆出来是为了能离线测：`validate_supply_chain_extraction.py` 用夹具跑它，
CI 里不需要网络也能拦下解析回归。取数与编排在 `extract_form_sd.py`。

## 认哪一行是冶炼厂

**只认带 RMI CID 编号的行。** 这不是图省事，是上一轮踩过的坑的直接结论：
正查与反查都败在实体消歧上——EDGAR 里同一个 CIK 有 `Apple Inc.` 和 `APPLE INC`
两种写法，按名字比对必然漏配、错配。RMI 的 CID 是全球统一编号，同一家冶炼厂
在苹果和英伟达的申报里是同一个 CID，跨申报人合并才有依据。

没有 CID 的行一律不发布。冶炼厂名在不同申报人笔下写法不一
（`Asahi Pretec Corp.` / `Asahi Pretec Corporation` / `ASAHI PRETEC CORP`），
只靠名字去重会把一家拆成三家，或把两家并成一家——两种错都会伪造图谱结构。

## 列序不固定，所以不按列序取

各家申报的表头不一样（`Metal / Smelter Name / Smelter ID / Location`、
`Smelter or Refiner Name / Smelter ID / Country`、中间还常插空列）。
按第几列取值必然在某一家上错位，因此改为**按内容识别**：
哪个格子含 CID 就是编号，哪个格子是已知国名就是国别，哪个格子是矿种名就是矿种，
剩下最长的那个才是名字。识别不出来的字段留 None，不猜。
"""
from __future__ import annotations

import re
from html.parser import HTMLParser

# RMI 冶炼厂编号：CID 后接 6 位数字，各家写法有 CID001234 / CID 001234 / CID-001234
CID_PATTERN = re.compile(r"\bCID[\s\-_]?(\d{4,6})\b", re.I)

# 四种冲突矿产（3TG）。钽的矿石名 coltan、锡的矿石名 cassiterite 也一并认。
MINERALS = {
    "tin": "锡", "cassiterite": "锡",
    "tantalum": "钽", "coltan": "钽", "tantalite": "钽",
    "tungsten": "钨", "wolframite": "钨",
    "gold": "金",
}
MINERAL_PATTERN = re.compile(r"\b(" + "|".join(sorted(MINERALS, key=len, reverse=True)) + r")\b", re.I)

# 冶炼厂清单里实际出现的国别。RMI 标准名单集中在这几十个国家／地区，
# 认不出来的保留原文、country 置 None——宁可显示未归类，也不硬塞一个国家。
COUNTRIES: dict[str, str] = {
    "china": "中国", "people's republic of china": "中国", "p.r. china": "中国",
    "hong kong": "中国香港", "hong kong sar": "中国香港", "macau": "中国澳门",
    "taiwan": "中国台湾", "taiwan, province of china": "中国台湾", "chinese taipei": "中国台湾",
    "japan": "日本", "korea, republic of": "韩国", "republic of korea": "韩国",
    "south korea": "韩国", "korea": "韩国",
    "united states": "美国", "united states of america": "美国", "usa": "美国", "u.s.a.": "美国",
    "canada": "加拿大", "mexico": "墨西哥", "brazil": "巴西", "bolivia": "玻利维亚",
    "bolivia, plurinational state of": "玻利维亚", "peru": "秘鲁", "chile": "智利",
    "colombia": "哥伦比亚", "argentina": "阿根廷", "dominican republic": "多米尼加",
    "indonesia": "印度尼西亚", "malaysia": "马来西亚", "thailand": "泰国",
    "viet nam": "越南", "vietnam": "越南", "singapore": "新加坡",
    "philippines": "菲律宾", "india": "印度", "myanmar": "缅甸",
    "lao people's democratic republic": "老挝", "laos": "老挝", "cambodia": "柬埔寨",
    "mongolia": "蒙古", "kazakhstan": "哈萨克斯坦", "uzbekistan": "乌兹别克斯坦",
    "kyrgyzstan": "吉尔吉斯斯坦", "tajikistan": "塔吉克斯坦",
    "russian federation": "俄罗斯", "russia": "俄罗斯", "ukraine": "乌克兰",
    "turkey": "土耳其", "türkiye": "土耳其", "israel": "以色列",
    "united arab emirates": "阿联酋", "saudi arabia": "沙特阿拉伯",
    "germany": "德国", "france": "法国", "italy": "意大利", "spain": "西班牙",
    "united kingdom": "英国", "belgium": "比利时", "netherlands": "荷兰",
    "austria": "奥地利", "switzerland": "瑞士", "poland": "波兰",
    "czech republic": "捷克", "czechia": "捷克", "estonia": "爱沙尼亚",
    "finland": "芬兰", "sweden": "瑞典", "norway": "挪威", "denmark": "丹麦",
    "ireland": "爱尔兰", "portugal": "葡萄牙", "luxembourg": "卢森堡",
    "bulgaria": "保加利亚", "romania": "罗马尼亚", "hungary": "匈牙利",
    "slovakia": "斯洛伐克", "slovenia": "斯洛文尼亚", "serbia": "塞尔维亚",
    "greece": "希腊", "north macedonia": "北马其顿", "belarus": "白俄罗斯",
    "rwanda": "卢旺达", "burundi": "布隆迪", "uganda": "乌干达",
    "congo, the democratic republic of the": "刚果（金）",
    "democratic republic of the congo": "刚果（金）", "drc": "刚果（金）",
    "tanzania, united republic of": "坦桑尼亚", "tanzania": "坦桑尼亚",
    "kenya": "肯尼亚", "ethiopia": "埃塞俄比亚", "sudan": "苏丹",
    "south africa": "南非", "namibia": "纳米比亚", "zimbabwe": "津巴布韦",
    "mozambique": "莫桑比克", "nigeria": "尼日利亚", "ghana": "加纳",
    "mali": "马里", "burkina faso": "布基纳法索", "egypt": "埃及", "morocco": "摩洛哥",
    "australia": "澳大利亚", "new zealand": "新西兰", "papua new guinea": "巴布亚新几内亚",
    "kazakstan": "哈萨克斯坦",
}
# 去掉标点后再比对，容忍 "Korea, Republic of" / "Korea Republic of" 之类差异
_COUNTRY_KEYS = {re.sub(r"[^a-z ]", "", k): v for k, v in COUNTRIES.items()}

# 明显不是冶炼厂名的格子：表头、序号、空白
_HEADER_WORDS = re.compile(
    r"^(metal|mineral|smelter\s*(or\s*refiner)?\s*(name|id|look-?up)?|refiner|"
    r"standard\s*smelter\s*names?|country|location|source|status|no\.?|#|"
    r"facility\s*location|street\s*address|city|state|province)$", re.I)


class _TableRows(HTMLParser):
    """把 HTML 拆成一行行的格子文本。

    **用栈，不用正则切 <tr>/<td>**：申报文件里普遍有嵌套表格——排版用的内层表被塞在
    单元格里。正则会把内层行当成独立行，外层那条真正的冶炼厂行反而被切碎（夹具
    `nested-table` 就是这个形状，早期单指针版本在它上面一条都抽不出来）。

    栈式解析下，内层行结束时把它的文字并回外层格子，外层行因此保持完整；内层行本身
    也照常产出，但它没有 CID，后续会被跳过，不影响结论。
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[str]] = []
        self._rows: list[list[str]] = []          # 未闭合的 <tr> 栈
        self._cells: list[list[str]] = []         # 未闭合的 <td>/<th> 栈
        self._depth: list[int] = []               # 每层行开始时的格子栈深度
        # 表格外文字：矿种常写在小标题里而不在行内
        self.flow: list[tuple[int, str]] = []     # (已产出的行数, 文字)
        self._buf: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:  # noqa: ANN001
        if tag == "tr":
            self._flush_flow()
            self._rows.append([])
            self._depth.append(len(self._cells))
        elif tag in ("td", "th"):
            self._cells.append([])
        elif tag in ("br", "p", "div") and self._cells:
            self._cells[-1].append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in ("td", "th") and self._cells:
            text = re.sub(r"\s+", " ", "".join(self._cells.pop())).strip()
            if self._rows:
                self._rows[-1].append(text)
        elif tag == "tr" and self._rows:
            row = self._rows.pop()
            # 申报 HTML 常有漏闭合的 </td>；行结束时把残留的格子丢掉，
            # 免得它们漂到下一行去。
            keep = self._depth.pop() if self._depth else 0
            del self._cells[keep:]
            self.rows.append(row)
            if self._cells:
                self._cells[-1].append(" " + " ".join(row) + " ")

    def handle_data(self, data: str) -> None:
        if self._cells:
            self._cells[-1].append(data)
        elif not self._rows:
            self._buf.append(data)

    def _flush_flow(self) -> None:
        text = re.sub(r"\s+", " ", "".join(self._buf)).strip()
        self._buf = []
        if text:
            self.flow.append((len(self.rows), text))

    def close(self) -> None:                      # noqa: D102
        self._flush_flow()
        super().close()


def normalise_cid(text: str) -> str | None:
    """统一成 CID + 6 位。各家写法不同，编号本身必须唯一可比。"""
    match = CID_PATTERN.search(text or "")
    if not match:
        return None
    return "CID" + match.group(1).zfill(6)


def match_country(text: str) -> tuple[str | None, str | None]:
    """返回（规范英文名, 中文名）。认不出返回 (None, None)，不猜。"""
    key = re.sub(r"[^a-z ]", "", (text or "").strip().lower())
    key = re.sub(r"\s+", " ", key).strip()
    if not key:
        return None, None
    hit = _COUNTRY_KEYS.get(key)
    if hit:
        return key, hit
    return None, None


def match_mineral(text: str) -> str | None:
    match = MINERAL_PATTERN.search(text or "")
    return MINERALS[match.group(1).lower()] if match else None


def _looks_like_name(cell: str) -> bool:
    if not cell or len(cell) < 3:
        return False
    if _HEADER_WORDS.match(cell.strip()):
        return False
    if CID_PATTERN.search(cell):
        return False
    if re.fullmatch(r"[\d\s.,%/-]+", cell):        # 纯数字／序号格
        return False
    if MINERAL_PATTERN.fullmatch(cell.strip()):    # 「Gold」这种格子是金属列，不是厂名
        return False
    return bool(re.search(r"[A-Za-z一-鿿]{3}", cell))


def _split_trailing_country(name: str) -> tuple[str, str | None, str | None]:
    """有的申报把国别并在名字里（"Asahi Pretec Corp. Japan"），拆开。"""
    for sep in (",", " - ", " – ", " "):
        if sep not in name:
            continue
        head, _, tail = name.rpartition(sep)
        english, chinese = match_country(tail)
        if english and head.strip():
            return head.strip(" ,-–"), english, chinese
    return name, None, None


def parse_smelters(html: str) -> dict:
    """从一份冲突矿产报告里抽出冶炼厂清单。

    返回 {"smelters": [...], "rowsScanned": n, "rowsWithCid": n, "droppedNoCid": n}。
    每条含 cid / name / countryEn / country / minerals / rowIndex。
    """
    parser = _TableRows()
    parser.feed(html or "")
    parser.close()

    # 表格外文字里的矿种小标题：记录「第几行之前出现过什么矿种」
    heading_at: list[tuple[int, str]] = []
    for row_index, text in parser.flow:
        if len(text) > 120:                        # 长段落是正文叙述，不是小标题
            continue
        mineral = match_mineral(text)
        if mineral:
            heading_at.append((row_index, mineral))

    def heading_mineral(row_index: int) -> str | None:
        current = None
        for at, mineral in heading_at:
            if at <= row_index:
                current = mineral
            else:
                break
        return current

    found: dict[str, dict] = {}
    rows_with_cid = 0
    dropped_no_cid = 0
    for index, row in enumerate(parser.rows):
        cid = None
        for cell in row:
            cid = normalise_cid(cell)
            if cid:
                break
        if not cid:
            # 没有 CID 就不发布——但要数出来。这条规则是有代价的：若某家申报人
            # 只列名字不列编号，整份名单会被整个丢弃。代价必须可见，不能默默吞掉，
            # 否则「这家公司没有名单」和「有名单但我们不收」在报告里长得一样。
            if any(match_country(cell)[0] for cell in row) and any(
                    _looks_like_name(cell) and len(cell) >= 8 for cell in row):
                dropped_no_cid += 1
            continue
        rows_with_cid += 1

        country_en = country_zh = None
        minerals: set[str] = set()
        name_candidates: list[str] = []
        for cell in row:
            if CID_PATTERN.search(cell):
                continue
            english, chinese = match_country(cell)
            if english and not country_en:
                country_en, country_zh = english, chinese
                continue
            mineral = match_mineral(cell)
            # 矿种格子通常很短（"Tin"）；长句子里出现 gold 多半是叙述文字
            if mineral and len(cell) <= 24:
                minerals.add(mineral)
                continue
            if _looks_like_name(cell):
                name_candidates.append(cell)

        name = max(name_candidates, key=len) if name_candidates else None
        if name and not country_en:
            name, country_en, country_zh = _split_trailing_country(name)
        if not minerals:
            fallback = heading_mineral(index)
            if fallback:
                minerals.add(fallback)

        existing = found.get(cid)
        if existing:
            existing["minerals"] = sorted(set(existing["minerals"]) | minerals)
            existing["name"] = existing["name"] or name
            existing["countryEn"] = existing["countryEn"] or country_en
            existing["country"] = existing["country"] or country_zh
            continue
        found[cid] = {
            "cid": cid,
            "name": name,
            "countryEn": country_en,
            "country": country_zh,
            "minerals": sorted(minerals),
            "rowIndex": index,
        }

    smelters = sorted(found.values(), key=lambda s: s["cid"])
    return {
        "smelters": smelters,
        "rowsScanned": len(parser.rows),
        "rowsWithCid": rows_with_cid,
        # 看着像冶炼厂行、但没有 RMI 编号因而被丢弃的行数。不为零就说明这份申报
        # 的名单我们只收了一部分，页面上必须照实说，不能显示成完整名单。
        "droppedNoCid": dropped_no_cid,
        "unique": len(smelters),
        "namedRatio": (round(sum(1 for s in smelters if s["name"]) / len(smelters), 3)
                       if smelters else 0.0),
        "countryRatio": (round(sum(1 for s in smelters if s["countryEn"]) / len(smelters), 3)
                         if smelters else 0.0),
    }
