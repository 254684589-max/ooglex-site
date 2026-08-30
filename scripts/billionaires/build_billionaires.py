#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球亿万富豪身价」全榜数据：抓取 Forbes 实时富豪榜公开 JSON 接口，取前 TOP_N（3428，
即福布斯 2026 年度榜的亿万富豪总数），计算身价（十亿美元）与当日变动，写入
apps/billionaires/data.json，供静态页面读取渲染。

设计要点（与 asset-tracker 取数风格一致）：
- 数据源：Forbes 实时富豪榜（forbesapi/person/rtb），无需任何 API Key；
- 纯 requests + 硬超时，绝不挂起；整源失败则保留上次 data.json 不覆盖；
- 当日变动优先用 Forbes 的 estWorthPrev（上一参考时点估值），缺失时退回「今值 − 上次快照值」；
- 中文名 / 国家 / 行业做映射，未命中回退英文原文；国家附 emoji 国旗。中文名表外置于
  names_zh.json（约 2900 条，覆盖当前榜单约 84%），未收录者按设计显示英文原名，不做音译臆造；
- 截断按人数取 TOP_N，但边界落在并列排名中间时补齐整个并列组（福布斯榜尾并列组可达数十人）；
- 身价低于 MIN_WORTH_B 的一并滤除：实时榜尾部带着已跌出十亿门槛、福布斯仍在跟踪的前富豪；
- 输出「每人一行」的紧凑 JSON：体积较 indent=2 省约 20%，同时保留逐人可 diff 的可审阅性。
由 .github/workflows/billionaires.yml 每日定时运行，并把更新后的 data.json 提交回仓库。
"""
import json
import os
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "billionaires", "data.json")
TOP_N = 3428  # 福布斯 2026 年度榜亿万富豪总数；实时榜实际返回可能略少，以返回为准
# 身价下限（十亿美元）。实时榜尾部会带上「已经跌出十亿门槛、但福布斯仍在跟踪」的人
# （2026-08-30 实测 5 人：Kanye West $0.40B，Elizabeth Holmes / Gary Wang / Rene Benko /
# Sam Bankman-Fried 均为 $0.00B）。页面写的是「全部亿万富豪，净值 ≥ 10 亿美元」，
# 挂 $0.0B 的行出去自相矛盾，故在此按门槛过滤。
MIN_WORTH_B = 1.0

API = ("https://www.forbes.com/forbesapi/person/rtb/0/position/true.json"
       "?fields=rank,personName,finalWorth,estWorthPrev,source,"
       "countryOfCitizenship,industries,squareImage,birthDate,gender&limit=4500")
HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")}

# 中文名对照表。扩到全榜（3400+ 人）后条目达 2900 余条，内联进本文件将完全无法审阅，
# 因此外置为 names_zh.json，本文件只负责加载。
#
# 收录口径（很重要，改词典前先读）：
# - 非汉字圈姓名按《世界人名翻译大辞典》惯例音译——音译是同一个名字的另一种书写，不是编造；
# - 中国大陆/港澳台/日/韩/越等汉字圈人物的罗马化姓名，只在能确指其人时才写汉字。
#   "Wang Wei" 可能是王伟/王卫/王薇，猜错就是对一个真人断言假事实，宁可留空回退英文原名；
# - 同一英文名在榜上对应不同人物的（如两个 Zhang Jian）一律不收录，否则会张冠李戴。
NAMES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "names_zh.json")


def load_name_zh():
    """载入中文名对照表；文件缺失或损坏时退化为空表（全部显示英文原名），不让取数失败。"""
    try:
        with open(NAMES_PATH, encoding="utf-8") as f:
            return json.load(f)["names"]
    except Exception as e:
        print(f"中文名词典加载失败（{str(e)[:80]}），本轮全部回退英文原名")
        return {}


NAME_ZH = load_name_zh()

COUNTRY_ZH = {
    "United States": "美国", "France": "法国", "China": "中国", "India": "印度", "Mexico": "墨西哥",
    "Spain": "西班牙", "Japan": "日本", "Germany": "德国", "Hong Kong": "香港", "Canada": "加拿大",
    "Italy": "意大利", "United Kingdom": "英国", "Switzerland": "瑞士", "Russia": "俄罗斯",
    "Indonesia": "印度尼西亚", "Australia": "澳大利亚", "Brazil": "巴西", "Austria": "奥地利",
    "Singapore": "新加坡", "Sweden": "瑞典", "Thailand": "泰国", "Netherlands": "荷兰",
    "South Korea": "韩国", "Taiwan": "台湾", "Israel": "以色列", "Belgium": "比利时", "Chile": "智利",
    "Nigeria": "尼日利亚", "Philippines": "菲律宾", "Malaysia": "马来西亚", "Czechia": "捷克",
    "Cyprus": "塞浦路斯", "Denmark": "丹麦", "Norway": "挪威", "New Zealand": "新西兰",
    "Egypt": "埃及", "Turkey": "土耳其", "Greece": "希腊", "Ireland": "爱尔兰", "Finland": "芬兰",
    "Poland": "波兰", "Ukraine": "乌克兰", "South Africa": "南非", "United Arab Emirates": "阿联酋",
    "Saudi Arabia": "沙特阿拉伯", "Qatar": "卡塔尔", "Lebanon": "黎巴嫩", "Argentina": "阿根廷",
    "Colombia": "哥伦比亚", "Peru": "秘鲁", "Venezuela": "委内瑞拉", "Vietnam": "越南",
    "Monaco": "摩纳哥", "Georgia": "格鲁吉亚", "Kazakhstan": "哈萨克斯坦", "Romania": "罗马尼亚",
    "Hungary": "匈牙利", "Portugal": "葡萄牙", "Oman": "阿曼", "Morocco": "摩洛哥",
    "Algeria": "阿尔及利亚", "Iceland": "冰岛", "Luxembourg": "卢森堡", "Liechtenstein": "列支敦士登",
    "Guernsey": "根西", "Bermuda": "百慕大", "Belize": "伯利兹", "Eswatini": "斯威士兰",
    # —— 补充：扩到全榜后实测出现、原词典未覆盖的国家/地区（2026-08-30 共 16 个、35 人）——
    # Forbes 用 "Czech Republic" 而非 "Czechia"，"Eswatini (Swaziland)" 而非 "Eswatini"，两种写法都留着。
    "Czech Republic": "捷克", "Estonia": "爱沙尼亚", "St. Kitts and Nevis": "圣基茨和尼维斯",
    "Slovakia": "斯洛伐克", "Bulgaria": "保加利亚", "Uruguay": "乌拉圭",
    "Eswatini (Swaziland)": "斯威士兰", "Pakistan": "巴基斯坦", "Zimbabwe": "津巴布韦",
    "Croatia": "克罗地亚", "Tanzania": "坦桑尼亚", "Nepal": "尼泊尔", "Albania": "阿尔巴尼亚",
    "Afghanistan": "阿富汗", "Armenia": "亚美尼亚", "Barbados": "巴巴多斯",
}
COUNTRY_FLAG = {
    "United States": "🇺🇸", "France": "🇫🇷", "China": "🇨🇳", "India": "🇮🇳", "Mexico": "🇲🇽",
    "Spain": "🇪🇸", "Japan": "🇯🇵", "Germany": "🇩🇪", "Hong Kong": "🇭🇰", "Canada": "🇨🇦",
    "Italy": "🇮🇹", "United Kingdom": "🇬🇧", "Switzerland": "🇨🇭", "Russia": "🇷🇺",
    "Indonesia": "🇮🇩", "Australia": "🇦🇺", "Brazil": "🇧🇷", "Austria": "🇦🇹", "Singapore": "🇸🇬",
    "Sweden": "🇸🇪", "Thailand": "🇹🇭", "Netherlands": "🇳🇱", "South Korea": "🇰🇷", "Taiwan": "🇹🇼",
    "Israel": "🇮🇱", "Belgium": "🇧🇪", "Chile": "🇨🇱", "Nigeria": "🇳🇬", "Philippines": "🇵🇭",
    "Malaysia": "🇲🇾", "Czechia": "🇨🇿", "Cyprus": "🇨🇾", "Denmark": "🇩🇰", "Norway": "🇳🇴", "New Zealand": "🇳🇿",
    "Egypt": "🇪🇬", "Turkey": "🇹🇷", "Greece": "🇬🇷", "Ireland": "🇮🇪", "Finland": "🇫🇮",
    "Poland": "🇵🇱", "Ukraine": "🇺🇦", "South Africa": "🇿🇦", "United Arab Emirates": "🇦🇪",
    "Saudi Arabia": "🇸🇦", "Qatar": "🇶🇦", "Lebanon": "🇱🇧", "Argentina": "🇦🇷",
    "Colombia": "🇨🇴", "Peru": "🇵🇪", "Venezuela": "🇻🇪", "Vietnam": "🇻🇳",
    "Monaco": "🇲🇨", "Georgia": "🇬🇪", "Kazakhstan": "🇰🇿", "Romania": "🇷🇴",
    "Hungary": "🇭🇺", "Portugal": "🇵🇹", "Oman": "🇴🇲", "Morocco": "🇲🇦",
    "Algeria": "🇩🇿", "Iceland": "🇮🇸", "Luxembourg": "🇱🇺", "Liechtenstein": "🇱🇮",
    "Guernsey": "🇬🇬", "Bermuda": "🇧🇲", "Belize": "🇧🇿", "Eswatini": "🇸🇿",
    "Czech Republic": "🇨🇿", "Estonia": "🇪🇪", "St. Kitts and Nevis": "🇰🇳",
    "Slovakia": "🇸🇰", "Bulgaria": "🇧🇬", "Uruguay": "🇺🇾",
    "Eswatini (Swaziland)": "🇸🇿", "Pakistan": "🇵🇰", "Zimbabwe": "🇿🇼",
    "Croatia": "🇭🇷", "Tanzania": "🇹🇿", "Nepal": "🇳🇵", "Albania": "🇦🇱",
    "Afghanistan": "🇦🇫", "Armenia": "🇦🇲", "Barbados": "🇧🇧",
}
INDUSTRY_ZH = {
    "Technology": "科技", "Automotive": "汽车", "Fashion & Retail": "时尚零售",
    "Finance & Investments": "金融投资", "Food & Beverage": "食品饮料", "Media & Entertainment": "传媒娱乐",
    "Healthcare": "医疗健康", "Real Estate": "房地产", "Energy": "能源", "Manufacturing": "制造业",
    "Metals & Mining": "金属矿业", "Telecom": "电信", "Diversified": "多元化", "Logistics": "物流",
    "Gambling & Casinos": "博彩", "Sports": "体育", "Service": "服务业",
    "Construction & Engineering": "建筑工程", "Money Management": "资产管理",
}


def fetch_forbes():
    """抓取 Forbes 实时富豪榜，返回人物列表（按排名）。"""
    r = requests.get(API, headers=HEADERS, timeout=20)
    r.raise_for_status()
    return r.json()["personList"]["personsLists"]


def to_b(m):
    """百万美元 → 十亿美元（保留两位）。"""
    return round(m / 1000.0, 2) if isinstance(m, (int, float)) else None


def age_from(bd):
    """birthDate（毫秒时间戳）→ 年龄；失败返回 None。"""
    try:
        born = datetime.fromtimestamp(bd / 1000, tz=timezone.utc).year
        return datetime.now(timezone.utc).year - born
    except Exception:
        return None


def load_prev():
    """上次 data.json，按英文名建索引，用于当日变动兜底与整源失败保活。"""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            d = json.load(f)
        return {p.get("nameEn") or p.get("name"): p for p in d.get("people", [])}
    except Exception:
        return {}


def zh_name(en):
    """英文名→中文名：精确命中优先；命中去掉 \u201c& family/siblings\u201d 的基名则加\u201c及家族/及兄弟姐妹\u201d；都不中回退英文。"""
    if not en:
        return en
    if en in NAME_ZH:
        return NAME_ZH[en]
    import re as _re
    base = _re.sub(r"\s*&\s*(family|siblings|sibling)\s*$", "", en, flags=_re.I).strip()
    if base in NAME_ZH:
        if _re.search(r"&\s*sibling", en, _re.I):
            return NAME_ZH[base] + "及兄弟姐妹"
        if _re.search(r"&\s*family", en, _re.I):
            return NAME_ZH[base] + "及家族"
        return NAME_ZH[base]
    return en


def cut_at_top_n(rows):
    """截断到 TOP_N 人。边界若落在并列排名中间，则补齐整个并列组再截断。

    福布斯用竞赛式排名，越往榜尾并列组越大（当前前 250 里 rank 194 就并列 7 人，
    $1B 门槛附近可达数十人）。按人数硬切会把同一名次的人切掉一半，页面上表现为
    「并列第 N 名」只显示了其中几个，所以宁可多收几人也不切开并列组。
    """
    if len(rows) <= TOP_N:
        return rows
    cut = TOP_N
    edge = rows[TOP_N - 1].get("rank")
    while cut < len(rows) and rows[cut].get("rank") == edge:
        cut += 1
    if cut > TOP_N:
        print(f"第 {TOP_N} 位落在并列 #{edge} 组中间，补齐至 {cut} 人")
    return rows[:cut]


def dump_rowwise(data, f):
    """写出「人物数组每人一行」的 JSON。

    体积比 indent=2 省约 20%（全榜约 1.2MB vs 1.5MB，按天提交一年差 100MB 以上），
    同时每人单独一行，git diff 仍能逐人比对——纯紧凑写法会把全文压成一行，
    数据被写坏时无法在 diff 里看出来。
    """
    head = [(k, v) for k, v in data.items() if k != "people"]
    people = data["people"]
    f.write("{\n")
    for k, v in head:
        f.write(f"  {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)},\n")
    f.write('  "people": [\n')
    for i, p in enumerate(people):
        row = json.dumps(p, ensure_ascii=False, separators=(",", ":"))
        f.write(f"    {row}{',' if i < len(people) - 1 else ''}\n")
    f.write("  ]\n}\n")


def build():
    prev = load_prev()
    try:
        people = fetch_forbes()
    except Exception as e:
        print(f"Forbes 抓取失败：{str(e)[:120]}")
        if prev:
            print("保留上次的 data.json，不覆盖。")
            return
        people = []

    out, dropped = [], 0
    for p in people:
        worth = to_b(p.get("finalWorth"))
        if worth is None:
            continue
        if worth < MIN_WORTH_B:  # 已跌出十亿门槛的前富豪，不进榜
            dropped += 1
            continue
        name_en = p.get("personName") or ""
        prev_m = p.get("estWorthPrev")
        change = None
        if isinstance(prev_m, (int, float)) and prev_m > 0:
            change = round((p["finalWorth"] - prev_m) / 1000.0, 2)
        elif name_en in prev and isinstance(prev[name_en].get("worth"), (int, float)):
            change = round(worth - prev[name_en]["worth"], 2)
        base = worth - change if change is not None else None
        pct = round(change / base * 100, 2) if base else None

        inds = p.get("industries") or []
        ind = inds[0] if inds else ""
        country = p.get("countryOfCitizenship", "") or ""
        out.append({
            "rank": p.get("rank") or len(out) + 1,
            "name": zh_name(name_en),
            "nameEn": name_en,
            "worth": worth,
            "change": change,
            "changePct": pct,
            "country": COUNTRY_ZH.get(country, country),
            "flag": COUNTRY_FLAG.get(country, "🌐"),
            "source": p.get("source", "") or "",
            "industry": INDUSTRY_ZH.get(ind, ind),
            "image": p.get("squareImage") or "",
            "age": age_from(p.get("birthDate")),
        })

    out = cut_at_top_n(out)

    if not out:
        print("无数据且无历史快照，跳过（不覆盖）。")
        return

    zh_hit = sum(1 for r in out if r["name"] != r["nameEn"])
    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "Forbes Real-Time Billionaires",
        "frequency": "daily",
        "status": "ok",
        "count": len(out),
        "totalWorth": round(sum(r["worth"] for r in out), 1),
        "note": ("数据来自 Forbes 实时富豪榜，每日自动更新；身价单位为十亿美元（B），"
                 "当日变动为较上一参考时点的估算。榜单覆盖全部亿万富豪（净值 ≥ 10 亿美元），"
                 f"其中 {zh_hit} 人有中文名对照，其余显示福布斯英文原名。仅供参考，不构成任何建议。"),
        "people": out,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        dump_rowwise(data, f)
    print(f"写入 {OUT_PATH}：{len(out)} 人，榜首 {out[0]['nameEn']} ${out[0]['worth']}B，"
          f"榜尾 #{out[-1]['rank']} ${out[-1]['worth']}B，总财富 ${data['totalWorth']}B，"
          f"中文名命中 {zh_hit}（{zh_hit / len(out) * 100:.0f}%）"
          f"，另滤除身价低于 ${MIN_WORTH_B}B 的 {dropped} 人")


if __name__ == "__main__":
    build()
