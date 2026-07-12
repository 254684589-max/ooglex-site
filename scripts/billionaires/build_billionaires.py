#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球前 250 富豪身价」数据：抓取 Forbes 实时富豪榜公开 JSON 接口，取前 250，
计算身价（十亿美元）与当日变动，写入 apps/billionaires/data.json，供静态页面读取渲染。

设计要点（与 asset-tracker 取数风格一致）：
- 数据源：Forbes 实时富豪榜（forbesapi/person/rtb），无需任何 API Key；
- 纯 requests + 硬超时，绝不挂起；整源失败则保留上次 data.json 不覆盖；
- 当日变动优先用 Forbes 的 estWorthPrev（上一参考时点估值），缺失时退回「今值 − 上次快照值」；
- 中文名 / 国家 / 行业做常见词映射，未命中回退英文原文；国家附 emoji 国旗。
由 .github/workflows/billionaires.yml 每日定时运行，并把更新后的 data.json 提交回仓库。
"""
import json
import os
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "billionaires", "data.json")
TOP_N = 250

API = ("https://www.forbes.com/forbesapi/person/rtb/0/position/true.json"
       "?fields=rank,personName,finalWorth,estWorthPrev,source,"
       "countryOfCitizenship,industries,squareImage,birthDate,gender&limit=320")
HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")}

# 常见富豪中文名（未命中则回退英文）。榜单头部稳定，覆盖常驻前列者即可。
NAME_ZH = {
    "Elon Musk": "埃隆·马斯克", "Jeff Bezos": "杰夫·贝佐斯", "Mark Zuckerberg": "马克·扎克伯格",
    "Larry Ellison": "拉里·埃里森", "Bernard Arnault": "贝尔纳·阿尔诺", "Bernard Arnault & family": "贝尔纳·阿尔诺及家族",
    "Larry Page": "拉里·佩奇", "Sergey Brin": "谢尔盖·布林", "Warren Buffett": "沃伦·巴菲特",
    "Bill Gates": "比尔·盖茨", "Steve Ballmer": "史蒂夫·鲍尔默", "Michael Bloomberg": "迈克尔·布隆伯格",
    "Jensen Huang": "黄仁勋", "Michael Dell": "迈克尔·戴尔", "Amancio Ortega": "阿曼西奥·奥特加",
    "Mukesh Ambani": "穆克什·安巴尼", "Gautam Adani": "高塔姆·阿达尼", "Rob Walton": "罗布·沃尔顿",
    "Jim Walton": "吉姆·沃尔顿", "Alice Walton": "爱丽丝·沃尔顿", "Carlos Slim Helu": "卡洛斯·斯利姆",
    "Carlos Slim Helu & family": "卡洛斯·斯利姆及家族", "Francoise Bettencourt Meyers": "弗朗索瓦丝·贝当古·迈耶斯",
    "Francoise Bettencourt Meyers & family": "弗朗索瓦丝·贝当古·迈耶斯及家族",
    "Zhong Shanshan": "钟睒睒", "Ma Huateng": "马化腾", "Zhang Yiming": "张一鸣", "Colin Huang": "黄峥",
    "Jack Ma": "马云", "William Lei Ding": "丁磊", "Li Ka-shing": "李嘉诚", "Zeng Yuqun": "曾毓群",
    "Masayoshi Son": "孙正义", "Tadashi Yanai": "柳井正", "Giovanni Ferrero": "乔瓦尼·费列罗",
    "Dieter Schwarz": "迪特尔·施瓦茨", "Klaus-Michael Kuehne": "克劳斯-米夏埃尔·库内", "Phil Knight": "菲尔·奈特",
    "Prajogo Pangestu": "普拉约戈·班格斯图", "Thomas Peterffy": "托马斯·彼得菲", "Charles Koch": "查尔斯·科赫",
    "Julia Koch": "朱莉娅·科赫", "Julia Koch & family": "朱莉娅·科赫及家族", "David Thomson": "戴维·汤姆森",
    "Rupert Murdoch": "鲁伯特·默多克", "MacKenzie Scott": "麦肯齐·斯科特", "Ken Griffin": "肯·格里芬",
    "Stephen Schwarzman": "苏世民", "Jim Simons": "詹姆斯·西蒙斯", "Robin Zeng": "曾毓群",
    "Low Tuck Kwong": "黄约翰", "Alain Wertheimer": "阿兰·韦特海默", "Gerard Wertheimer": "热拉尔·韦特海默",
}
# —— 扩充：覆盖当前榜单全部人物（华人真名优先，其余按惯例音译）——
ADD_NAME_ZH = {'Changpeng Zhao': '赵长鹏', 'Giancarlo Devasini': '吉安卡洛·德瓦西尼', 'Jeff Yass': '杰夫·亚斯', 'Germán Larrea Mota Velasco': '赫尔曼·拉雷亚·莫塔·维拉斯科', 'Iris Fontbona': '伊里斯·丰特沃纳', 'Lukas Walton': '卢卡斯·沃尔顿', 'Mark Mateschitz': '马克·马特希茨', 'Gianluigi Aponte': '詹路易吉·阿庞特', 'Rafaela Aponte-Diamant': '拉法埃拉·阿庞特-迪亚曼特', 'Jacqueline Mars': '杰奎琳·玛氏', 'John Mars': '约翰·玛氏', 'William Ding': '丁磊', 'Andrea Pignataro': '安德烈亚·皮尼亚塔罗', 'Abigail Johnson': '阿比盖尔·约翰逊', 'Eric Schmidt': '埃里克·施密特', 'Chen Tianshi': '陈天石', 'Savitri Jindal': '萨维特里·金达尔', 'Jean-Louis van der Velde': '让-路易·范德维尔德', 'Paolo Ardoino': '保罗·阿尔多伊诺', 'Alexey Mordashov': '阿列克谢·莫尔达绍夫', 'Jay Y. Lee': '李在镕', 'Henry Samueli': '亨利·萨穆埃利', 'Andreas von Bechtolsheim': '安德烈亚斯·冯·贝希托尔斯海姆', 'Eyal Ofer': '埃亚勒·奥弗', 'Pham Nhat Vuong': '范日旺', 'Miriam Adelson': '米里亚姆·阿德尔森', 'He Xiangjian': '何享健', 'Marilyn Simons': '玛丽莲·西蒙斯', 'Idan Ofer': '伊丹·奥弗', 'John Tu': '杜纪川', 'David Sun': '孙大卫', 'Robert Pera': '罗伯特·佩拉', 'Thomas Frist Jr': '小托马斯·弗里斯特', 'Eduardo Saverin': '爱德华多·萨维林', 'Liu Debing': '刘德兵', 'Len Blavatnik': '伦·布拉瓦特尼克', 'Elaine Marshall': '伊莱恩·马歇尔', 'Lyndal Stephens Greth': '林达尔·斯蒂芬斯·格雷思', 'Wang Weixiu': '王威秀', 'Melinda French Gates': '梅琳达·弗伦奇·盖茨', 'Vladimir Potanin': '弗拉基米尔·波塔宁', 'Vagit Alekperov': '瓦吉特·阿列克佩罗夫', 'Aliko Dangote': '阿里科·丹格特', 'Vinod Adani': '维诺德·阿达尼', 'Lakshmi Mittal': '拉克希米·米塔尔', 'Leonid Mikhelson': '列昂尼德·米赫尔松', 'Cyrus Poonawalla': '赛勒斯·普纳瓦拉', 'Huang Shilin': '黄世霖', 'François Pinault': '弗朗索瓦·皮诺', 'Reinhold Wuerth': '莱因霍尔德·维尔特', 'Pierre Chen': '陈泰铭', 'Dilip Shanghvi': '迪利普·桑哈维', 'Peter Thiel': '彼得·蒂尔', 'Emmanuel Besnier': '埃马纽埃尔·贝尼耶', 'Israel Englander': '伊斯雷尔·英格兰德', 'Suleiman Kerimov': '苏莱曼·克里莫夫', 'Vladimir Lisin': '弗拉基米尔·利辛', 'Vicky Safra': '维琪·萨夫拉', 'Shiv Nadar': '希夫·纳达尔', 'Daniel Gilbert': '丹尼尔·吉尔伯特', 'Torstein Hagen': '托尔斯泰因·哈根', 'Zhou Qunfei': '周群飞', 'Stuart Hoegner': '斯图尔特·赫格纳', 'Gina Rinehart': '吉娜·莱因哈特', 'Stanley Kroenke': '斯坦利·克伦克', 'Prince Alwaleed Bin Talal Alsaud': '阿尔瓦利德·本·塔拉勒亲王', 'Gennady Timchenko': '根纳季·季姆琴科', 'Susanne Klatten': '苏珊娜·克拉滕', 'David Tepper': '大卫·泰珀', 'Stefan Quandt': '斯特凡·宽特', 'Henry Nicholas III': '亨利·尼古拉斯三世', 'Steve Cohen': '史蒂夫·科恩', 'Takemitsu Takizaki': '泷崎武光', 'Harry Triguboff': '哈里·特里古博夫', 'John Doerr': '约翰·杜尔', 'Christy Walton': '克里斯蒂·沃尔顿', 'Todd Graves': '托德·格雷夫斯', 'Diane Hendricks': '黛安·亨德里克斯', 'Kumar Birla': '库马尔·比尔拉', 'Zheng Shuliang': '郑淑良', 'Rick Cohen': '里克·科恩', 'Yu Yong': '于泳', 'Yuan Fugen': '袁富根', 'Jason Chang': '张虔生', 'Stefan Persson': '斯特凡·佩尔松', 'Michael Platt': '迈克尔·普拉特', 'Ernest Garcia II': '欧内斯特·加西亚二世', 'Andrey Melnichenko': '安德烈·梅尔尼琴科', 'John Fredriksen': '约翰·弗雷德里克森', 'Jorge Paulo Lemann': '若热·保罗·莱曼', 'Enrique Razon Jr.': '小恩里克·拉松', 'Harold Hamm': '哈罗德·哈姆', 'Wang Chuanfu': '王传福', 'Renata Kellnerova': '蕾娜塔·凯尔纳罗娃', 'Philip Anschutz': '菲利普·安舒茨', 'Donald Bren': '唐纳德·布伦', 'Jerry Jones': '杰里·琼斯', 'Nathan Kirsh': '内森·基尔什', 'Brett Adcock': '布雷特·阿德科克', 'Nik Storonsky': '尼克·斯托龙斯基', 'Andrew Forrest': '安德鲁·福里斯特', 'Dang Yanbao': '党彦宝', 'Chen Jianhua': '陈建华', 'Nancy Walton Laurie': '南希·沃尔顿·劳里', 'Adam Foroughi': '亚当·福鲁吉', 'Edwin Chen': '埃德温·陈', 'Zou Zhinong': '邹志农', 'Eric Smidt': '埃里克·斯米特', 'James Ratcliffe': '詹姆斯·拉特克利夫', 'Lei Jun': '雷军', 'Johann Rupert': '约翰·鲁珀特', 'John Collison': '约翰·科里森', 'Patrick Collison': '帕特里克·科里森', 'Cai Huabo': '蔡华波', 'Kwong Siu-hing': '邝肖卿', 'Pei Zhenhua': '裴振华', 'John Menard Jr': '小约翰·梅纳德', 'Stephen Ross': '斯蒂芬·罗斯', 'Radhakishan Damani': '拉达基尚·达马尼', 'Arthur Dantchik': '阿瑟·丹奇克', 'Georg Schaeffler': '格奥尔格·舍夫勒', 'Beate Heister': '贝亚特·海斯特', 'Karl Albrecht Jr.': '小卡尔·阿尔布雷希特', 'Jan Koum': '扬·库姆', 'Sarath Ratanavadi': '萨拉·拉塔纳瓦迪', 'Anders Holch Povlsen': '安诺斯·霍尔希·波夫尔森', 'Qin Yinglin': '秦英林', 'George Kaiser': '乔治·凯泽', 'Barry Lam': '林百里', 'Zhong Huijuan': '钟慧娟', 'Mikhail Fridman': '米哈伊尔·弗里德曼', 'Ludwig Merckle': '路德维希·默克勒', 'Charlene de Carvalho-Heineken': '沙琳·德卡瓦略-海尼根', 'Dhanin Chearavanont': '谢国民', 'Peter Mallouk': '彼得·马卢克', 'Jaime Gilinski Bacal': '海梅·吉林斯基·巴卡尔', 'Wang Xin': '王欣', 'Lu Xiangyang': '吕向阳', 'Theo Albrecht Jr': '小特奥·阿尔布雷希特', 'Edward Johnson IV': '爱德华·约翰逊四世', 'Alejandro Baillères Gual': '亚历杭德罗·巴耶雷斯', 'Christopher Olah': '克里斯托弗·奥拉', 'Daniela Amodei': '丹妮拉·阿莫迪', 'Dario Amodei': '达里奥·阿莫迪', 'Jack Clark': '杰克·克拉克', 'Jared Kaplan': '贾里德·卡普兰', 'Sam McCandlish': '萨姆·麦坎德利什', 'Tom Brown': '汤姆·布朗', 'Xavier Niel': '泽维尔·尼尔', 'Ray Dalio': '瑞·达利欧', 'Hussain Sajwani': '侯赛因·萨杰瓦尼', 'Terry Gou': '郭台铭', 'Shahid Khan': '沙希德·汗', 'Eric Li': '埃里克·李', 'Friedhelm Loh': '弗里德黑尔姆·洛', 'Ralph Lauren': '拉尔夫·劳伦', 'R. Budi Hartono': '布迪·哈托诺', 'Wang Liping': '王丽萍', 'James Dyson': '詹姆斯·戴森', 'Cao Renxian': '曹仁贤', 'Brad Jacobs': '布拉德·雅各布斯', 'Jack Dangermond': '杰克·丹杰蒙德', 'Wang Wei': '王卫', 'Wang Laisheng': '王来胜', 'Laurene Powell Jobs': '劳伦·鲍威尔·乔布斯', 'Joseph Lau': '刘銮雄', 'Wang Laichun': '王来春', 'Charles Ergen': '查尔斯·埃根', 'Vinod Khosla': '维诺德·科斯拉', 'Elizabeth Johnson': '伊丽莎白·约翰逊', 'Robert Kraft': '罗伯特·克拉夫特', 'Ann Walton Kroenke': '安·沃尔顿·克伦克', 'Alisher Usmanov': '阿利舍尔·乌斯马诺夫', 'Lee Boo-jin': '李富真', 'Dmitri Bukhman': '德米特里·布赫曼', 'Igor Bukhman': '伊戈尔·布赫曼', 'Zhang Zhidong': '张志东', 'Bubba Cathy': '巴巴·卡西', 'Dan Cathy': '丹·卡西', 'Trudy Cathy White': '特鲁迪·卡西·怀特', 'Uday Kotak': '乌代·科塔克', 'Antonia Ax:son Johnson': '安东尼娅·阿克松·约翰逊', 'Sunil Mittal': '苏尼尔·米塔尔', 'Ken Fisher': '肯·费雪', 'J. Christopher Reyes': '克里斯托弗·雷耶斯', 'Jude Reyes': '裘德·雷耶斯', 'Zhu Yi': '朱义', 'Bruce Cheng': '郑崇华', 'Li Shuirong': '李水荣', 'David Reuben': '大卫·鲁本', 'Simon Reuben': '西蒙·鲁本', 'Richard Kinder': '理查德·金德', 'Abdulsamad Rabiu': '阿卜杜勒萨马德·拉比乌', 'Ivan Glasenberg': '伊万·格拉森伯格', 'David Velez': '大卫·贝莱斯', 'Robert Kuok': '郭鹤年', 'Orlando Bravo': '奥兰多·布拉沃', 'Lee Seo-hyun': '李叙显', 'Wang Ning': '王宁', 'James Goodnight': '詹姆斯·古德奈特', 'Leon Black': '利昂·布莱克', 'Andrew Beal': '安德鲁·比尔', 'Hamdi Ulukaya': '哈姆迪·乌卢卡亚', 'Charles Schwab': '查尔斯·施瓦布', 'George Roberts': '乔治·罗伯茨'}
NAME_ZH.update(ADD_NAME_ZH)

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

    out = []
    for p in people:
        worth = to_b(p.get("finalWorth"))
        if worth is None:
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
        if len(out) >= TOP_N:
            break

    if not out:
        print("无数据且无历史快照，跳过（不覆盖）。")
        return

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "Forbes Real-Time Billionaires",
        "count": len(out),
        "totalWorth": round(sum(r["worth"] for r in out), 1),
        "note": ("数据来自 Forbes 实时富豪榜，每日自动更新；身价单位为十亿美元（B），"
                 "当日变动为较上一参考时点的估算。仅供参考，不构成任何建议。"),
        "people": out,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(out)} 人，榜首 {out[0]['nameEn']} ${out[0]['worth']}B，"
          f"前{len(out)}总财富 ${data['totalWorth']}B")


if __name__ == "__main__":
    build()
