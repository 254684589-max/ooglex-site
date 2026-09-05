#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解析 Form SD 冲突矿产报告里的冶炼厂／精炼厂清单。

## 这个模块只做解析，不联网

拆出来是为了能离线测：`validate_supply_chain_extraction.py` 用夹具跑它，
CI 里不需要网络也能拦下解析回归。取数与编排在 `extract_form_sd.py`。

## 认哪一行是冶炼厂

两种行都收，但**来源类型分开标记**：

1. **带 RMI CID 编号的行**（`identifierType: "rmi-cid"`）。CID 是全球统一编号，
   同一家冶炼厂在应用材料和 Skyworks 的申报里是同一个 CID，跨申报人合并有依据。
2. **无编号但形态完整的行**（`identifierType: "name-only"`）：矿种 + 厂名 + 国别
   三者齐全才收。英伟达 2026 年那份报告 407 行、一个编号都没有，全是
   `Tantalum | AMG Brasil | BRAZIL` 这个形状——只认编号会把它整个丢掉。

**代价写在标记里，不藏起来**：没有编号就没有全球统一标识，跨申报人只能按名字
规范化合并，而冶炼厂名各家写法不一（`Asahi Pretec Corp.` / `Corporation` / `CORP`），
写法不同就会重复。因此 `_slug()` 只做大小写与标点归一，**不做任何同义合并**——
宁可一家重复出现，不可两家被错并成一家。登记表里这两类分开统计、分开说明。

## 什么不算冶炼厂行

实测踩过的三种假名单，都在离线夹具里：

- **纯国名附录**（微软 274 行）：三列全是国名的原产国清单，一家冶炼厂都没有。
- **国别 × 矿种矩阵**（英特尔 243 行）：有国名有矿种，但没有第三类格子。
- **叙述正文**：正文里矿种与国名满天飞，不得凭空造厂。

因此「有国名 + 有矿种」不足以收一行，必须还有一个既不是国名也不是矿种的厂名格。

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
    # 以下多见于「原产国」附录而非冶炼厂所在国。表不全的代价是把国名当成厂名：
    # 微软那份三列国名附录里，Andorra 因为不在表里就被当成了漏收的冶炼厂行。
    "andorra": "安道尔", "antigua and barbuda": "安提瓜和巴布达", "madagascar": "马达加斯加",
    "fiji": "斐济", "french guiana": "法属圭亚那", "mauritania": "毛里塔尼亚",
    "solomon islands": "所罗门群岛", "malta": "马耳他", "mali": "马里",
    "guyana": "圭亚那", "suriname": "苏里南", "venezuela": "委内瑞拉",
    "ecuador": "厄瓜多尔", "paraguay": "巴拉圭", "uruguay": "乌拉圭",
    "guatemala": "危地马拉", "honduras": "洪都拉斯", "nicaragua": "尼加拉瓜",
    "costa rica": "哥斯达黎加", "panama": "巴拿马", "cuba": "古巴",
    "haiti": "海地", "jamaica": "牙买加", "trinidad and tobago": "特立尼达和多巴哥",
    "guinea": "几内亚", "sierra leone": "塞拉利昂", "liberia": "利比里亚",
    "cote d ivoire": "科特迪瓦", "ivory coast": "科特迪瓦", "senegal": "塞内加尔",
    "niger": "尼日尔", "chad": "乍得", "cameroon": "喀麦隆", "gabon": "加蓬",
    "congo": "刚果（布）", "central african republic": "中非",
    "angola": "安哥拉", "zambia": "赞比亚", "malawi": "马拉维",
    "botswana": "博茨瓦纳", "lesotho": "莱索托", "eswatini": "埃斯瓦蒂尼",
    "madagascar republic": "马达加斯加", "somalia": "索马里", "eritrea": "厄立特里亚",
    "djibouti": "吉布提", "libya": "利比亚", "tunisia": "突尼斯", "algeria": "阿尔及利亚",
    "pakistan": "巴基斯坦", "bangladesh": "孟加拉国", "sri lanka": "斯里兰卡",
    "nepal": "尼泊尔", "bhutan": "不丹", "afghanistan": "阿富汗",
    "turkmenistan": "土库曼斯坦", "georgia": "格鲁吉亚", "armenia": "亚美尼亚",
    "azerbaijan": "阿塞拜疆", "iran islamic republic of": "伊朗", "iraq": "伊拉克",
    "jordan": "约旦", "lebanon": "黎巴嫩", "syrian arab republic": "叙利亚",
    "kuwait": "科威特", "qatar": "卡塔尔", "bahrain": "巴林", "oman": "阿曼",
    "yemen": "也门", "cyprus": "塞浦路斯", "iceland": "冰岛", "greenland": "格陵兰",
    "latvia": "拉脱维亚", "lithuania": "立陶宛", "moldova republic of": "摩尔多瓦",
    "croatia": "克罗地亚", "bosnia and herzegovina": "波黑", "albania": "阿尔巴尼亚",
    "montenegro": "黑山", "kosovo": "科索沃", "liechtenstein": "列支敦士登",
    "monaco": "摩纳哥", "san marino": "圣马力诺", "brunei darussalam": "文莱",
    "brunei": "文莱", "timor leste": "东帝汶", "new caledonia": "新喀里多尼亚",
    "french polynesia": "法属波利尼西亚", "vanuatu": "瓦努阿图", "samoa": "萨摩亚",
    "tonga": "汤加", "guam": "关岛", "puerto rico": "波多黎各",
    "korea democratic peoples republic of": "朝鲜", "north korea": "朝鲜",
}
# 上面那张表只覆盖真的出现过冶炼厂的国家，够用来显示中文名。但**识别**必须覆盖
# 得更广：申报里还有大段「原产国」附录，里面什么国家都有。一个国名没被认出来，
# 就会被当成厂名候选，进而把整行误判成「漏收的冶炼厂」——微软那份附录里的
# Andorra、Skyworks 那份里的 Sint Maarten 都这么错过。
#
# 因此再列一份只管识别、不给中文名的清单。命中它的格子按原文显示：
# 认得出是国家但没有中文名，照原文写出来，比硬塞一个译名或干脆认不出都强。
KNOWN_COUNTRIES = {
    "afghanistan", "aland islands", "albania", "algeria", "american samoa", "andorra",
    "angola", "anguilla", "antarctica", "antigua and barbuda", "argentina", "armenia",
    "aruba", "azerbaijan", "bahamas", "bahrain", "bangladesh", "barbados", "belarus",
    "belize", "benin", "bermuda", "bhutan", "bonaire", "bosnia and herzegovina",
    "botswana", "bouvet island", "british indian ocean territory", "brunei darussalam",
    "bulgaria", "burkina faso", "burundi", "cabo verde", "cambodia", "cameroon",
    "cape verde", "cayman islands", "central african republic", "chad", "christmas island",
    "cocos islands", "comoros", "congo", "congo democratic republic of the",
    "congo the democratic republic of the", "cook islands", "costa rica", "cote divoire",
    "croatia", "cuba", "curacao", "cyprus", "djibouti", "dominica", "dominican republic",
    "ecuador", "egypt", "el salvador", "equatorial guinea", "eritrea", "eswatini",
    "ethiopia", "falkland islands", "faroe islands", "fiji", "french guiana",
    "french polynesia", "french southern territories", "gabon", "gambia", "georgia",
    "ghana", "gibraltar", "greenland", "grenada", "guadeloupe", "guam", "guatemala",
    "guernsey", "guinea", "guinea bissau", "guyana", "haiti", "holy see", "honduras",
    "iceland", "iran islamic republic of", "iraq", "isle of man", "israel", "jamaica",
    "jersey", "jordan", "kenya", "kiribati", "korea democratic peoples republic of",
    "kosovo", "kuwait", "kyrgyzstan", "lao peoples democratic republic", "latvia",
    "lebanon", "lesotho", "liberia", "libya", "liechtenstein", "lithuania", "luxembourg",
    "macao", "macau", "madagascar", "malawi", "maldives", "mali", "malta",
    "marshall islands", "martinique", "mauritania", "mauritius", "mayotte",
    "micronesia federated states of", "moldova republic of", "monaco", "montenegro",
    "montserrat", "morocco", "mozambique", "myanmar", "namibia", "nauru", "nepal",
    "new caledonia", "nicaragua", "niger", "nigeria", "niue", "norfolk island",
    "north macedonia", "northern mariana islands", "oman", "pakistan", "palau",
    "palestine state of", "panama", "papua new guinea", "paraguay", "puerto rico",
    "qatar", "reunion", "romania", "rwanda", "saint barthelemy", "saint helena",
    "saint kitts and nevis", "saint lucia", "saint martin", "saint pierre and miquelon",
    "saint vincent and the grenadines", "samoa", "san marino", "sao tome and principe",
    "saudi arabia", "senegal", "serbia", "seychelles", "sierra leone", "sint maarten",
    "slovakia", "slovenia", "solomon islands", "somalia", "south georgia", "south sudan",
    "sri lanka", "sudan", "suriname", "svalbard", "syrian arab republic", "tajikistan",
    "timor leste", "togo", "tokelau", "tonga", "trinidad and tobago", "tunisia",
    "turkmenistan", "turks and caicos islands", "tuvalu", "uganda", "ukraine",
    "united republic of tanzania", "united states minor outlying islands", "uruguay",
    "vanuatu", "venezuela", "venezuela bolivarian republic of", "virgin islands",
    "virgin islands british", "virgin islands us", "wallis and futuna",
    "western sahara", "yemen", "zambia", "zimbabwe",
}

# 去掉标点后再比对，容忍 "Korea, Republic of" / "Korea Republic of" 之类差异
_COUNTRY_KEYS = {re.sub(r"[^a-z ]", "", k): v for k, v in COUNTRIES.items()}
_KNOWN_KEYS = {re.sub(r"[^a-z ]", "", k) for k in KNOWN_COUNTRIES}

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


# 脚注标记：英特尔那份名单里每个厂名后面都跟着一个 `*`。不去掉的话
# `A.L.M.T. Corp.*` 与 `A.L.M.T. Corp.` 会算成两家不同的冶炼厂——正是
# 「按名字合并会把一家拆成几家」那个风险的具体形态。
_FOOTNOTE = re.compile(r"[\s*†‡§¶]+$|\s*\((?:\d{1,2}|[a-z])\)$", re.I)


def clean_name(name: str | None) -> str | None:
    if not name:
        return name
    text = _FOOTNOTE.sub("", name.strip()).strip()
    return text or None


def _slug(name: str) -> str:
    """名字规范化，只用于无编号条目的内部标识。

    大小写、标点与多余空格统一，但**不做任何同义合并**——
    `Aurubis AG` 与 `Aurubis AG, Hamburg` 会得到两个不同的 id，这是刻意的：
    它们可能是同一家，也可能是同一集团的不同厂，没有编号就无从判断。
    宁可重复，不可错并。
    """
    text = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")
    return text[:80] or "unnamed"


def normalise_cid(text: str) -> str | None:
    """统一成 CID + 6 位。各家写法不同，编号本身必须唯一可比。"""
    match = CID_PATTERN.search(text or "")
    if not match:
        return None
    return "CID" + match.group(1).zfill(6)


def match_country(text: str) -> tuple[str | None, str | None]:
    """返回（规范英文名, 显示名）。认不出返回 (None, None)，不猜。

    有中文名的给中文名；只在识别清单里的按原文显示——认得出是国家但没有译名，
    照原文写出来，比硬塞一个译名诚实，也比认不出（会被当成厂名）安全。
    """
    raw = (text or "").strip()
    key = re.sub(r"[^a-z ]", " ", raw.lower())
    key = re.sub(r"\s+", " ", key).strip()
    if not key or len(key) > 60:
        return None, None
    hit = _COUNTRY_KEYS.get(key)
    if hit:
        return key, hit
    if key in _KNOWN_KEYS:
        return key, raw
    return None, None


def match_mineral(text: str) -> str | None:
    """宽松匹配：文字里出现矿种词即算。只用于小标题（"Tin Smelters"）。"""
    match = MINERAL_PATTERN.search(text or "")
    return MINERALS[match.group(1).lower()] if match else None


_FILLER = {"and", "or", "amp", "the"}

# 元素符号。**只在 mineral_cell 的严格匹配里用，绝不能进 MINERAL_PATTERN**——
# 那是个宽松正则，把 \bw\b 放进去会把正文里每一个 "W" 都当成钨。
#
# 缘由：迪尔那份 531KB 的冲突矿产报告，483 行里 402 行是这个形状——
#
#     Gold (Au) | Al Etihad Gold Refinery DMCC | UNITED ARAB EMIRATES
#     Gold (Au) | L'Orfebre S.A.               | ANDORRA
#     Gold (Au) | SOLEIL METALS (Chala One Plant) | PERU
#
# 一份排版规整的真名单，402 家冶炼厂，一条都没抽出来。原因就是 "Gold (Au)"
# 去掉标点后剩下 ["gold", "au"]，而 "au" 既不是矿种词也不是填充词，
# 严格匹配一票否决整格。**卡在括号里的元素符号上，不是卡在别的地方。**
_SYMBOLS = {"sn": "锡", "ta": "钽", "w": "钨", "au": "金"}


def mineral_cell(text: str) -> set[str]:
    """严格匹配：整个格子都是矿种词才算「矿种列」。

    不能用宽松匹配：`Changsha South Tantalum Niobium Co` 里也有 Tantalum，
    按宽松匹配会被当成矿种列吞掉，那正是英伟达名单里冶炼厂名所在的那一列。

    「整格都是矿种词」这条本身仍然是严格的——加进来的只是元素符号，
    而且必须与矿种词同格出现或单独成格才成立。`Ta Chen Stainless` 里有 "Ta"，
    但 "chen" 不是矿种词，整格照样一票否决。
    """
    token = re.sub(r"[^A-Za-z ]", " ", text or "").strip()
    if not token or len(token) > 48:
        return set()
    words = [w.lower() for w in token.split()]
    picked = {MINERALS[w] for w in words if w in MINERALS}
    picked |= {_SYMBOLS[w] for w in words if w in _SYMBOLS}
    if not picked or any(w not in MINERALS and w not in _SYMBOLS and w not in _FILLER
                         for w in words):
        return set()
    return picked


def _looks_like_name(cell: str) -> bool:
    if not cell or len(cell) < 3:
        return False
    if _HEADER_WORDS.match(cell.strip()):
        return False
    if CID_PATTERN.search(cell):
        return False
    if re.fullmatch(r"[\d\s.,%/-]+", cell):        # 纯数字／序号格
        return False
    if mineral_cell(cell):                         # 「Gold」这种格子是金属列，不是厂名
        return False
    if match_country(cell)[0]:                     # 整格是国名的，是国别列，不是厂名
        return False
    return bool(re.search(r"[A-Za-z一-鿿]{3}", cell))


_CORPORATE = re.compile(
    r"\b(co|corp|corporation|inc|incorporated|ltd|limited|llc|l\.?l\.?c|plc|ag|gmbh|"
    r"s\.?a|n\.?v|b\.?v|pte|sdn|bhd|kk|k\.?k|oyj|a/s|as|spa|s\.?p\.?a|"
    r"metals?|mining|smelt\w*|refin\w*|industr\w*|group|materials?|technolog\w*|"
    r"chemical\w*|resources?)\b", re.I)


def _looks_like_company(name: str) -> bool:
    """粗判一个名字像不像企业名，只用于统计「被丢弃的行」有多少。

    不参与建边判定——建边靠的是「矿种 + 厂名 + 国别」三者齐全。这里只是防止
    没登记进国名表的地名（Andorra、Fiji）被算成漏收的冶炼厂，把代价报大。
    """
    text = (name or "").strip()
    return bool(_CORPORATE.search(text)) or len(text.split()) >= 2


# 公司名末尾的法律形式后缀。用途见 _split_trailing_country：只有名字已经
# 以后缀收尾时，后面跟的国名才是**附加的元数据**；否则它多半是名字本身的一部分。
_LEGAL_SUFFIX = re.compile(
    r"(?:corp|corporation|inc|ltd|limited|llc|llp|co|company|group|holdings?|"
    r"gmbh|ag|kg|sa|sas|sarl|nv|bv|plc|pte|pty|kk|sdn|bhd|jsc|ojsc|pjsc|ooo|oao|"
    r"spa|srl|ab|as|oy|oyj|kft|doo|zrt|cjsc|pt|tbk|sac|cia|sl)\.?$",
    re.I)


def _split_trailing_country(name: str) -> tuple[str, str | None, str | None]:
    """名字里带着国名时，取出国别；**只在有把握时才把名字截短**。

    这里要分开两个问题，上一版把它们混成了一个，两边都做错过：

      一、这家公司**叫什么**  —— 截错就等于改了它的身份，代价最大
      二、这一格**提到了哪个国家** —— 认出国名是在读，不是在猜

    实测踩过两次，方向相反：

      第一次（太松）：见空格就拿最后一个词试国名，试中就把前半段当名字。
        KEMET de Mexico                  →  砍成 "KEMET de"
        Umicore Precious Metals Thailand →  砍成 "Umicore Precious Metals"
        PT Premium Tin Indonesia         →  砍成 "PT Premium Tin"
        四个都是名字本身就以国名收尾的合法实体。

      第二次（太紧）：改成不确定就不拆，结果**连国别一起丢了**。
        无编号的行要「矿种 + 厂名 + 国别」三样齐全才收，国别一没，整行被弃，
        卡特彼勒、迪士尼、乐天化学、相干、星巴克、陶氏六家的名单整份消失
        （实测 88 → 80 家）。为了几个名字的准确度，赔掉六家公司的全部数据。

    正确的做法是两件事分开办：国名照认（进 country 字段），名字只在有把握时截。

      有把握 —— 逗号、破折号这类约定俗成的元数据分隔符，
                或前半段以法律形式后缀（Corp. / Ltd. / K.K. / S.A.…）收尾
      没把握 —— 名字原样保留，国别照样给出

    于是 "Asahi Pretec Corp. Japan" 截成 "Asahi Pretec Corp." + 日本；
    "KEMET de Mexico" 名字不动，国别仍然是墨西哥——两样都对。
    """
    for sep in (",", " - ", " \u2013 "):
        if sep not in name:
            continue
        head, _, tail = name.rpartition(sep)
        english, chinese = match_country(tail)
        if english and head.strip():
            return head.strip(" ,-\u2013"), english, chinese

    head, _, tail = name.rpartition(" ")
    if not head.strip():
        return name, None, None
    english, chinese = match_country(tail)
    if not english:
        return name, None, None
    # 去掉点再比后缀，"K.K." / "S.A." / "N.V." 这类带点写法才认得出来。
    confident = _LEGAL_SUFFIX.search(head.strip(" ,-\u2013").replace(".", ""))
    if confident:
        return head.strip(" ,-\u2013"), english, chinese
    # 没把握就只取国别，名字一个字不动。
    return name, english, chinese


# Form SD 底下其实是**两套互不相干的披露**：
#   13p-1  冲突矿产（Conflict Minerals）—— 有冶炼厂名单的是这一套
#   13q-1  资源开采付款（Resource Extraction Payments，即 Section 1504）
#          —— 油气与矿业公司申报向各国政府付了多少钱，与冶炼厂毫无关系
#
# 康菲的 sd-2024df1504.htm、纽蒙特的 a2025formsd-estma.htm 都是后者。
# 把它们算进「申报了但正文未列名单」是错的：那句话暗示「本可以列却没列」，
# 而事实是**这套披露里本来就没有冶炼厂这个概念**。能源板块 15/22 家落在
# 那一档，多半就是这么来的。
#
# 判据取自文档正文的固有词，不猜文件名——文件名叫什么是申报人的自由。
_EXTRACTION_MARKS = (
    "resource extraction",
    "section 1504",
    "rule 13q-1",
    "13q-1",
    "extractive sector transparency",
    "estma",
    "payments to governments",
    "government payments",
)
# Form SD 有固定的条目标题，这是这份表最可靠的结构信号：
#
#     Item 1.01  Conflict Minerals Disclosure and Report     ← 13p-1
#     Item 2.01  Resource Extraction Issuer Disclosure       ← 13q-1
#
# 申报人报哪一套就写哪个条目，不会两个都写（除非真的两套都报）。
#
# **不能拿 "rule 13p-1" 当强特征**：Form SD 的封面把两条规则都印在勾选框里，
# 勾没勾都印，所以每一份 SD 都含 13p-1 三个字。条目标题不一样，它只在
# 真的报了那一套时才出现。
_MINERAL_TITLE = (
    "conflict minerals disclosure",
    "conflict minerals report",
    "conflict mineral report",
)
_EXTRACTION_TITLE = (
    "resource extraction issuer disclosure",
    "resource extraction payment",
)
_MINERAL_MARKS = (
    "conflict minerals",
    "rule 13p-1",
    "13p-1",
    "smelter",
    "refiner",
    "3tg",
)


# XBRL 渲染文件的名字形状。SEC 从 2024 年起要求 13q-1 资源开采付款用内联 XBRL
# 标记，13p-1 冲突矿产没有这个要求——所以「申报目录里有没有 XBRL 渲染件」
# 是一条**结构性**判据，不受正文用词影响。
_XBRL_RENDER = re.compile(r"^R\d+\.html?$", re.I)


def filing_is_xbrl_tagged(names) -> bool:
    """这份申报是不是做了 XBRL 标记（看目录里的文件名，不看正文）。"""
    for name in names or ():
        base = str(name).strip()
        if _XBRL_RENDER.match(base):
            return True
        low = base.lower()
        if low.endswith("_htm.xml") or low == "metalinks.json":
            return True
    return False


def disclosure_kind(html: str, xbrl_tagged: bool = False) -> str:
    """这份申报是冲突矿产还是资源开采付款。

    返回 "conflict-minerals" / "resource-extraction" / "unknown"。

    **只在没抽到名单时才会调用它**，所以它决定的不是「要不要这份名单」，
    而是「这家没有名单的原因怎么写」。写错了就是对读者说错话：
    「有申报但没列名单」暗示本可以列却没列，而 13q-1 那套披露里根本没有
    冶炼厂这个概念。

    ## 只按用词判会出错，实测过

    第一版的规则是「出现矿产词就判冲突矿产」，理由是冲突矿产报告里提一句
    1504 很常见。拿外国发行人一跑就露馅了：

        力拓  formsd2025govpayment.htm  —— 通篇是向各国政府的付款，判成了「未列名单」
        壳牌  shel-20251231.htm         —— 表格是「保加利亚能源部 658,383」，同样判错

    原因很直白：**力拓有铝冶炼厂、壳牌有炼油厂**，"smelter" 与 "refiner"
    是它们的业务词，出现在 13q-1 报告里再正常不过。矿业与能源公司正是
    资源开采付款申报的主力，这条规则对它们系统性地判错。

    ## 改法：先看结构，再看用词

    13q-1 的付款数据必须用内联 XBRL 标记，13p-1 没有这个要求。目录里有没有
    XBRL 渲染件（R4.htm / *_htm.xml / MetaLinks.json）不受正文用词影响。
    因此：**有 XBRL 标记且正文有开采类特征 → 资源开采付款**；其余情况仍按
    用词判，并保留原来「宁可判成冲突矿产」的偏向。
    """
    text = re.sub(r"<[^>]+>", " ", html or "").lower()
    # 条目标题最先看，它直接说明这份 SD 报的是哪一套。
    # 两个都出现时判冲突矿产：那说明申报人两套都报了，而只有 13p-1 才可能有名单。
    minerals_title = any(m in text for m in _MINERAL_TITLE)
    extraction_title = any(m in text for m in _EXTRACTION_TITLE)
    if minerals_title:
        return "conflict-minerals"
    if extraction_title:
        return "resource-extraction"
    has_minerals = any(m in text for m in _MINERAL_MARKS)
    has_extraction = any(m in text for m in _EXTRACTION_MARKS)
    if xbrl_tagged and has_extraction:
        return "resource-extraction"
    if has_minerals:
        return "conflict-minerals"
    if has_extraction:
        return "resource-extraction"
    return "unknown"


def parse_smelters(html: str) -> dict:
    """从一份冲突矿产报告里抽出冶炼厂清单。

    返回 {"smelters": [...], "rowsScanned": n, "rowsWithCid": n, "droppedNoCid": n}。
    每条含 cid / name / countryEn / country / minerals / rowIndex。
    """
    parser = _TableRows()
    parser.feed(html or "")
    parser.close()

    # 矿种小标题：可能在表格外的文字里（"Tin Smelters"），也可能自己占一整行
    # （微软那份名单就是这样分节的——不认表内小标题会丢掉 100 家真实冶炼厂，
    # 因为它们那几节的行里没有矿种列）。两处都收，按行号排序后合并。
    heading_at: list[tuple[int, str]] = []
    for row_index, text in parser.flow:
        if len(text) > 120:                        # 长段落是正文叙述，不是小标题
            continue
        mineral = match_mineral(text)
        if mineral:
            heading_at.append((row_index, mineral))
    for row_index, row in enumerate(parser.rows):
        cells = [c for c in row if c.strip()]
        # 只认「整行只有一个格子、且这个格子短到只可能是小标题」的情况。
        # 放宽一点就会把矿种矩阵的数据行当成小标题。
        if len(cells) != 1 or len(cells[0]) > 40:
            continue
        mineral = match_mineral(cells[0])
        if mineral and not match_country(cells[0])[0]:
            heading_at.append((row_index, mineral))
    heading_at.sort(key=lambda pair: pair[0])

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
    name_only = 0
    dropped_no_cid = 0
    dropped_sample: list[list[str]] = []
    dropped_headings: list[str] = []
    for index, row in enumerate(parser.rows):
        cid = None
        for cell in row:
            cid = normalise_cid(cell)
            if cid:
                break

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
            picked = mineral_cell(cell)
            if picked:
                minerals |= picked
                continue
            if _looks_like_name(cell):
                name_candidates.append(cell)

        name = clean_name(max(name_candidates, key=len)) if name_candidates else None
        if name and not country_en:
            name, country_en, country_zh = _split_trailing_country(name)
        if not minerals:
            fallback = heading_mineral(index)
            if fallback:
                minerals.add(fallback)

        if cid:
            rows_with_cid += 1
            key, identifier = cid, "rmi-cid"
        elif name and country_en and minerals:
            # 无编号但形态完整（矿种 + 厂名 + 国别）的行照收，单独标记来源类型。
            # 英伟达 2026 年那份报告 279 行全是这个形状——只认编号会把它整个丢掉，
            # 而它恰恰是本板块最该有数据的公司之一。
            #
            # 代价写在标记里：名字不是全球统一标识，跨申报人合并只能按名字规范化，
            # 写法不同就会重复。因此这类条目在全局登记表里单独统计、单独说明，
            # 不与带编号的混在一起报成同一个数。
            key, identifier = "NAME:" + _slug(name), "name-only"
            name_only += 1
        else:
            # 收不了的行：看着像清单（有国名 + 有不是国名也不是矿种的名字），
            # 但缺矿种或缺国别，无法确认是冶炼厂行。计数让代价可见。
            # 「厂名」至少要两个词或带公司后缀。单个词多半是没登记进表的地名——
            # 把它算成漏收的冶炼厂，会虚报规则的代价，方向正好是自我夸大。
            if country_en and name and _looks_like_company(name):
                dropped_no_cid += 1
                if len(dropped_sample) < 12:
                    dropped_sample.append([c for c in row if c][:6])
                if len(dropped_headings) < 6:
                    # 这一行前面最近的一段表外文字。缺矿种的行到底是「不是名单」
                    # 还是「小标题没认出来」，只能看这个才知道，不能靠猜。
                    near = [t for at, t in parser.flow if at <= index]
                    dropped_headings.append(near[-1][:90] if near else "（前面没有表外文字）")
            continue

        existing = found.get(key)
        if existing:
            existing["minerals"] = sorted(set(existing["minerals"]) | minerals)
            existing["name"] = existing["name"] or name
            existing["countryEn"] = existing["countryEn"] or country_en
            existing["country"] = existing["country"] or country_zh
            continue
        found[key] = {
            "id": key,
            "cid": cid,
            "identifierType": identifier,
            "name": name,
            "countryEn": country_en,
            "country": country_zh,
            "minerals": sorted(minerals),
            "rowIndex": index,
        }

    smelters = sorted(found.values(), key=lambda s: (s["identifierType"], s["id"]))
    raw = html or ""
    return {
        # 表格行数为 0 时靠这个区分「文档真没有表格」与「解析器没读懂这份 HTML」
        "shape": {
            "bytes": len(raw),
            "tableTags": len(re.findall(r"<table[\s>]", raw, re.I)),
            "trTags": len(re.findall(r"<tr[\s>]", raw, re.I)),
            "cidTokens": len(CID_PATTERN.findall(raw)),
            "textHead": re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", raw[:6000]))[:260],
        },
        "smelters": smelters,
        "rowsScanned": len(parser.rows),
        "rowsWithCid": rows_with_cid,
        # 无编号但形态完整的条目数。不为零就说明这份名单的实体标识只有名字，
        # 跨申报人合并不可靠——页面与登记表都必须分开说。
        "nameOnly": name_only,
        # 看着像冶炼厂行、但没有 RMI 编号因而被丢弃的行数。不为零就说明这份申报
        # 的名单我们只收了一部分，页面上必须照实说，不能显示成完整名单。
        "droppedNoCid": dropped_no_cid,
        # 只给 dry-run 看：被丢弃的行长什么样，决定「没有编号」是不是该改规则。
        "droppedSample": dropped_sample,
        "droppedHeadings": dropped_headings,
        "unique": len(smelters),
        "namedRatio": (round(sum(1 for s in smelters if s["name"]) / len(smelters), 3)
                       if smelters else 0.0),
        "countryRatio": (round(sum(1 for s in smelters if s["countryEn"]) / len(smelters), 3)
                         if smelters else 0.0),
    }
