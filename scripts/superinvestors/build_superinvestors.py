#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「超级投资者持仓 + AAII 投资者情绪」数据，写入 apps/superinvestors/data.json。

一、超级投资者持仓（SEC EDGAR 13F-HR，公开接口、无需 Key）：
  - 对每位投资者/机构（约 60 个 CIK，见 INVESTORS）：
    1) data.sec.gov/submissions 拿最近两期 13F-HR（同期有修正案 13F-HR/A 取最新）；
    2) 抓 filing 目录里的持仓明细 XML（infoTable），按 CUSIP 前 6 位聚合；
    3) 计算组合总市值、持仓数、前十大持仓与占比，并与上一期对比得出
       本季动向（新建/清仓/加仓/减持）。
  - 用 submissions 返回的机构名做关键词校验，CIK 不匹配直接跳过，防止串号；
  - 部分机构仍按旧格式以「千美元」申报：按隐含股价中位数（value/shares）
    判断，中位数 < $2 视为千美元申报并 ×1000 纠偏；
  - 最新报告期超过 400 天的投资者不再展示；
  - 公司名输出中英对照：CUSIP 精确映射优先，公司名关键词兜底，
    映射不到的只显示英文原名；
  - SEC 要求 UA 带联系方式，且限速（每请求间隔 0.25s）。

二、AAII 投资者情绪调查（美国个人投资者协会，每周四发布）：
  - 首选官方历史数据表 aaii.com/files/surveys/sentiment.xls（xlrd 解析）；
  - 失败则回退抓 sent_results 页面正则解析；再失败保留上次数据。

任何一节整体失败都不覆盖上次的对应数据；两节全失败则不写文件。
由 .github/workflows/superinvestors.yml 每周五定时运行并提交 data.json。
"""
import base64
import io
import json
import os
import re
import statistics
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "superinvestors", "data.json")

SEC_HEADERS = {
    "User-Agent": "Ooglex.com data bot (contact: zlq6600e@outlook.com)",
    "Accept-Encoding": "gzip, deflate",
}
WEB_HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/123.0 Safari/537.36"),
}
# 维基百科 API 政策要求带联系方式的描述性 User-Agent，否则数据中心 IP 会被
# 激进限流（429），导致整批头像丢失。此 UA 专用于 wikipedia.org 请求。
WIKI_HEADERS = {
    "User-Agent": "OoglexBot/1.0 (https://ooglex.com; contact: zlq6600e@outlook.com) requests/2",
    "Accept": "application/json",
}

# CIK(10位) / 机构名校验关键词 / 中文名 / 英文名 / 机构(英) / 机构(中) / 维基百科条目(头像)
# 关键词校验：EDGAR 返回的机构名必须包含该关键词，否则视为 CIK 串号并跳过。
# 维基条目留空则前端显示首字头像；条目名不存在时管线自动降级为空。
WIKI_TITLES = {
    "Warren Buffett": "Warren Buffett", "Bill Ackman": "Bill Ackman",
    "Seth Klarman": "Seth Klarman", "Li Lu": "Li Lu", "Michael Burry": "Michael Burry",
    "Mohnish Pabrai": "Mohnish Pabrai", "Daily Journal": "Charlie Munger",
    "Ray Dalio": "Ray Dalio", "Stanley Druckenmiller": "Stanley Druckenmiller",
    "David Einhorn": "David Einhorn", "Daniel Loeb": "Daniel S. Loeb",
    "Chase Coleman": "Chase Coleman III", "Cathie Wood": "Cathie Wood",
    "Gates Foundation": "Bill Gates", "David Tepper": "David Tepper",
    "Carl Icahn": "Carl Icahn", "George Soros": "George Soros",
    "Renaissance Tech": "Jim Simons", "Ken Griffin": "Kenneth C. Griffin",
    "Izzy Englander": "Israel Englander", "D.E. Shaw": "David E. Shaw",
    "Cliff Asness": "Cliff Asness", "Steve Cohen": "Steve Cohen (businessman)",
    "Paul Singer": "Paul Singer (businessman)", "Stephen Mandel": "Stephen Mandel (hedge fund manager)",
    "Philippe Laffont": "Philippe Laffont", "Andreas Halvorsen": "Ole Andreas Halvorsen",
    "Ken Fisher": "Ken Fisher", "Howard Marks": "Howard Marks (investor)",
    "Nelson Peltz": "Nelson Peltz", "Paul Tudor Jones": "Paul Tudor Jones",
    "Joel Greenblatt": "Joel Greenblatt", "Prem Watsa": "Prem Watsa",
    "Tom Gayner": "Tom Gayner", "Terry Smith": "Terry Smith (fund manager)",
    "John Rogers": "John W. Rogers Jr.", "Bruce Berkowitz": "Bruce Berkowitz",
    "John Paulson": "John Paulson", "Jeremy Grantham": "Jeremy Grantham",
    "David Abrams": "David Abrams (investor)", "Mason Hawkins": "Mason Hawkins",
    "Chris Hohn": "Chris Hohn", "Dan Sundheim": "Daniel Sundheim",
    "Leon Cooperman": "Leon Cooperman", "Brad Gerstner": "Brad Gerstner",
    "Bill Miller": "Bill Miller (investor)", "Kahn Brothers": "Irving Kahn",
    "Yacktman AM": "Donald Yacktman", "Chuck Royce": "Chuck Royce",
    "Guy Spier": "Guy Spier", "Richard Pzena": "Richard Pzena",
    "Marshall Wace": "Paul Marshall (financier)",
    "Norbert Lou": "Li Lu", "Chuck Akre": "Chuck Akre",
    "Tom Russo": "Thomas A. Russo", "Jeff Smith": "Jeffrey Smith (investor)",
    "Wally Weitz": "Wallace Weitz",
}

# 机构类兜底：无单一人物照片时，用公司维基页的题图（多为 logo）。
# 人物照片解析失败也会走这里。找不到公司页则保持首字头像。
FIRM_WIKI = {
    "D.E. Shaw": "D. E. Shaw & Co.", "CPP Investments": "CPP Investments",
    "Two Sigma": "Two Sigma", "Baillie Gifford": "Baillie Gifford",
    "Harris Associates": "Harris Associates", "Farallon Capital": "Farallon Capital Management",
    "Polen Capital": "Polen Capital", "Terry Smith": "Fundsmith",
    "Philippe Laffont": "Coatue Management", "Andreas Halvorsen": "Viking Global Investors",
    "Stephen Mandel": "Lone Pine Capital", "Tom Gayner": "Markel Group",
    "Dan Sundheim": "D1 Capital Partners", "Yacktman AM": "Yacktman Asset Management",
    "Chuck Akre": "Akre Capital Management", "Mason Morfit": "ValueAct Capital",
    "David Abrams": "Abrams Capital", "Jeff Smith": "Starboard Value",
    "Nelson Peltz": "Trian Partners", "Mason Hawkins": "Southeastern Asset Management",
    "Bruce Berkowitz": "Fairholme Capital Management", "Wally Weitz": "Weitz Investment Management",
    "Tweedy Browne": "Tweedy, Browne", "Kahn Brothers": "Kahn Brothers Group",
    "Izzy Englander": "Millennium Management, LLC", "Chase Coleman": "Tiger Global Management",
    "Joel Greenblatt": "Gotham Asset Management", "Richard Pzena": "Pzena Investment Management",
    "Bill Miller": "Miller Value Partners", "Ken Fisher": "Fisher Investments",
}

# 最终兜底：维基既无人物照片也无公司题图时，用公司官网的品牌图标
# （Google favicon 服务，始终返回、无需密钥）。机构显示 logo、个人显示
# 所属公司标识，避免纯首字。域名尽量用各家主站。
FIRM_DOMAIN = {
    "Warren Buffett": "berkshirehathaway.com", "Bill Ackman": "pershingsquareholdings.com",
    "Seth Klarman": "baupost.com", "Li Lu": "himalayacapital.com",
    "Michael Burry": "scionasset.com", "Mohnish Pabrai": "pabraifunds.com",
    "Ray Dalio": "bridgewater.com", "Stanley Druckenmiller": "duquesne.com",
    "David Einhorn": "greenlightcapital.com", "Daniel Loeb": "thirdpoint.com",
    "Chase Coleman": "tigerglobal.com", "Cathie Wood": "ark-invest.com",
    "David Tepper": "appaloosala.com", "Carl Icahn": "icahnenterprises.com",
    "George Soros": "soros.com", "Ken Griffin": "citadel.com",
    "Izzy Englander": "mlp.com", "D.E. Shaw": "deshaw.com",
    "Two Sigma": "twosigma.com", "Cliff Asness": "aqr.com",
    "Steve Cohen": "point72.com", "Paul Singer": "elliottmgmt.com",
    "Stephen Mandel": "lonepine.com", "Philippe Laffont": "coatue.com",
    "Andreas Halvorsen": "vikingglobal.com", "Ken Fisher": "fisherinvestments.com",
    "Howard Marks": "oaktreecapital.com", "Nelson Peltz": "trianpartners.com",
    "Paul Tudor Jones": "tudor.com", "Joel Greenblatt": "gothamfunds.com",
    "Prem Watsa": "fairfax.ca", "Tom Gayner": "markel.com",
    "Terry Smith": "fundsmith.co.uk", "John Rogers": "arielinvestments.com",
    "Bruce Berkowitz": "fairholmefunds.com", "John Paulson": "paulsonco.com",
    "David Abrams": "abramscapital.com", "Mason Hawkins": "southeasternasset.com",
    "Chris Hohn": "tcifund.com", "Dan Sundheim": "d1capital.com",
    "Brad Gerstner": "altimeter.com", "Bill Miller": "millervalue.com",
    "Yacktman AM": "yacktman.com", "Guy Spier": "aquamarinefund.com",
    "Richard Pzena": "pzena.com", "Marshall Wace": "mwam.com",
    "Norbert Lou": "punchcardmgmt.com", "Chuck Akre": "akrecapital.com",
    "Tom Russo": "gardnerrusso.com", "Jeff Smith": "starboardvalue.com",
    "Wally Weitz": "weitzinvestments.com", "CPP Investments": "cppinvestments.com",
    "Baillie Gifford": "bailliegifford.com", "Harris Associates": "oakmark.com",
    "Farallon Capital": "faralloncapital.com", "Polen Capital": "polencapital.com",
    "Mason Morfit": "valueact.com", "Tweedy Browne": "tweedyfunds.com",
    "Kahn Brothers": "kahnbrothers.com", "Gates Foundation": "gatesfoundation.org",
    "Daily Journal": "dailyjournal.com",
}


_ICON_CACHE = {}


def favicon_data_uri(domain):
    """构建期把公司图标抓下来、内联成 base64 data URI —— 运行时浏览器零外部
    请求，彻底规避 Google / DuckDuckGo / 官网 CDN 在中国大陆被墙（请求会「挂起」
    而非快速报错，导致白底 <img> 一直盖住首字母、露出空白圆圈）的问题。
    构建在 GitHub Actions（境外、可达全网）里跑，抓到的字节直接随 data.json 下发。
    依次尝试：Clearbit 品牌 logo → Google favicon(128) → DuckDuckGo → 官网 favicon。"""
    if not domain:
        return ""
    if domain in _ICON_CACHE:
        return _ICON_CACHE[domain]
    cands = [
        "https://logo.clearbit.com/" + domain,
        "https://www.google.com/s2/favicons?sz=128&domain=" + domain,
        "https://icons.duckduckgo.com/ip3/" + domain + ".ico",
        "https://" + domain + "/favicon.ico",
    ]
    out = ""
    for url in cands:
        try:
            r = requests.get(url, headers=WEB_HEADERS, timeout=12)
        except Exception:
            continue
        if not r or r.status_code != 200 or not r.content:
            continue
        blob = r.content
        if len(blob) < 70 or len(blob) > 60000:  # 过小=占位/1x1，过大=控体积跳过
            continue
        # 只认「魔术字节」判定的真图片；HTTP 头声称 image/* 但实为 HTML 错误页
        # （如某些站点 favicon.ico 返回 SPA 首页）一律拒收，换下一个源。
        if blob[:8] == b"\x89PNG\r\n\x1a\n":
            ctype = "image/png"
        elif blob[:3] == b"GIF":
            ctype = "image/gif"
        elif blob[:3] == b"\xff\xd8\xff":
            ctype = "image/jpeg"
        elif blob[:4] == b"\x00\x00\x01\x00":
            ctype = "image/x-icon"
        elif blob[:2] == b"BM":
            ctype = "image/bmp"
        elif blob[:4] == b"RIFF" and blob[8:12] == b"WEBP":
            ctype = "image/webp"
        elif b"<svg" in blob[:400].lower():
            ctype = "image/svg+xml"
        else:
            continue  # 非图片（HTML 等）→ 换下一个源
        out = "data:" + ctype + ";base64," + base64.b64encode(blob).decode()
        break
    _ICON_CACHE[domain] = out
    return out


INVESTORS = [
    ("0001067983", "BERKSHIRE",     "沃伦·巴菲特",        "Warren Buffett",      "Berkshire Hathaway",        "伯克希尔·哈撒韦"),
    ("0001336528", "PERSHING",      "比尔·阿克曼",        "Bill Ackman",         "Pershing Square",           "潘兴广场资本"),
    ("0001061768", "BAUPOST",       "赛斯·卡拉曼",        "Seth Klarman",        "Baupost Group",             "包普斯特集团"),
    ("0001709323", "HIMALAYA",      "李录",               "Li Lu",               "Himalaya Capital",          "喜马拉雅资本"),
    ("0001649339", "SCION",         "迈克尔·伯里",        "Michael Burry",       "Scion Asset Management",    "塞恩资产管理"),
    ("0001549575", "DALAL",         "莫尼什·帕伯莱",      "Mohnish Pabrai",      "Dalal Street",              "达拉尔街"),
    ("0000783412", "DAILY JOURNAL", "每日期刊(芒格遗产)",  "Daily Journal",       "Daily Journal Corp",        "每日期刊公司"),
    ("0001350694", "BRIDGEWATER",   "瑞·达利欧",          "Ray Dalio",           "Bridgewater Associates",    "桥水基金"),
    ("0001536411", "DUQUESNE",      "斯坦利·德鲁肯米勒",  "Stanley Druckenmiller","Duquesne Family Office",   "杜肯家族办公室"),
    ("0001079114", "GREENLIGHT",    "大卫·艾因霍恩",      "David Einhorn",       "Greenlight Capital",        "绿光资本"),
    ("0001040273", "THIRD POINT",   "丹尼尔·勒布",        "Daniel Loeb",         "Third Point",               "第三点资本"),
    ("0001167483", "TIGER GLOBAL",  "蔡斯·科尔曼",        "Chase Coleman",       "Tiger Global",              "老虎环球基金"),
    ("0001697748", "ARK",           "凯茜·伍德",          "Cathie Wood",         "ARK Invest",                "方舟投资"),
    ("0001166559", "GATES",         "盖茨基金会信托",      "Gates Foundation",    "B&M Gates Foundation Trust","盖茨基金会信托"),
    ("0001656456", "APPALOOSA",     "大卫·泰珀",          "David Tepper",        "Appaloosa",                 "阿帕卢萨管理"),
    ("0000921669", "ICAHN",         "卡尔·伊坎",          "Carl Icahn",          "Icahn Capital",             "伊坎资本"),
    ("0001029160", "SOROS",         "索罗斯家族办公室",    "George Soros",        "Soros Fund Management",     "索罗斯基金管理"),
    ("0001037389", "RENAISSANCE",   "文艺复兴科技",        "Renaissance Tech",    "Renaissance Technologies",  "文艺复兴科技(西蒙斯)"),
    ("0001423053", "CITADEL",       "肯·格里芬",          "Ken Griffin",         "Citadel Advisors",          "城堡投资"),
    ("0001273087", "MILLENNIUM",    "伊兹·英格兰德",      "Izzy Englander",      "Millennium Management",     "千禧管理"),
    ("0001009207", "SHAW",          "德劭基金",            "D.E. Shaw",           "D.E. Shaw & Co",            "德劭集团"),
    ("0001179392", "TWO SIGMA",     "双西格玛",            "Two Sigma",           "Two Sigma Investments",     "双西格玛投资"),
    ("0001167557", "AQR",           "克里夫·阿斯内斯",    "Cliff Asness",        "AQR Capital",               "AQR资本"),
    ("0001603466", "POINT72",       "史蒂夫·科恩",        "Steve Cohen",         "Point72",                   "Point72资产管理"),
    ("0001791786", "ELLIOTT",       "保罗·辛格",          "Paul Singer",         "Elliott Management",        "埃利奥特投资管理"),
    ("0001061165", "LONE PINE",     "斯蒂芬·曼德尔",      "Stephen Mandel",      "Lone Pine Capital",         "孤松资本"),
    ("0001135730", "COATUE",        "菲利普·拉丰",        "Philippe Laffont",    "Coatue Management",         "蔻图资本"),
    ("0001103804", "VIKING",        "安德烈亚斯·哈尔沃森","Andreas Halvorsen",   "Viking Global",             "维京环球"),
    ("0000850529", "FISHER",        "肯·费雪",            "Ken Fisher",          "Fisher Investments",        "费雪投资"),
    ("0000949509", "OAKTREE",       "霍华德·马克斯",      "Howard Marks",        "Oaktree Capital",           "橡树资本"),
    ("0001345471", "TRIAN",         "纳尔逊·佩尔茨",      "Nelson Peltz",        "Trian Fund Management",     "特里安基金"),
    ("0000923093", "TUDOR",         "保罗·都铎·琼斯",     "Paul Tudor Jones",    "Tudor Investment",          "都铎投资"),
    ("0001510387", "GOTHAM",        "乔尔·格林布拉特",    "Joel Greenblatt",     "Gotham Asset Management",   "高谭资产管理"),
    ("0000915191", "FAIRFAX",       "普雷姆·瓦特萨",      "Prem Watsa",          "Fairfax Financial",         "枫信金融"),
    ("0001096343", "MARKEL",        "汤姆·盖纳",          "Tom Gayner",          "Markel Group",              "马克尔集团"),
    ("0001569205", "FUNDSMITH",     "特里·史密斯",        "Terry Smith",         "Fundsmith",                 "芬德史密斯"),
    ("0001112520", "AKRE",          "查克·阿克瑞",        "Chuck Akre",          "Akre Capital",              "阿克瑞资本"),
    ("0000936753", "ARIEL",         "约翰·罗杰斯",        "John Rogers",         "Ariel Investments",         "爱瑞尔投资"),
    ("0000029440", "DODGE",         "道奇-考克斯基金",     "Dodge & Cox",         "Dodge & Cox",               "道奇-考克斯"),
    ("0001056831", "FAIRHOLME",     "布鲁斯·伯考维茨",    "Bruce Berkowitz",     "Fairholme Capital",         "费尔霍姆资本"),
    ("0001035674", "PAULSON",       "约翰·保尔森",        "John Paulson",        "Paulson & Co",              "保尔森公司"),
    ("0000772129", "GRANTHAM",      "杰里米·格兰瑟姆",    "Jeremy Grantham",     "GMO",                       "GMO资产管理"),
    ("0001358706", "ABRAMS",        "大卫·艾布拉姆斯",    "David Abrams",        "Abrams Capital",            "艾布拉姆斯资本"),
    ("0000807985", "SOUTHEASTERN",  "梅森·霍金斯",        "Mason Hawkins",       "Southeastern AM (Longleaf)","东南资产管理"),
    ("0000732905", "TWEEDY",        "特威迪·布朗",        "Tweedy Browne",       "Tweedy, Browne Co",         "特威迪·布朗"),
    ("0001517137", "STARBOARD",     "杰夫·史密斯",        "Jeff Smith",          "Starboard Value",           "星板价值"),
    ("0001418814", "VALUEACT",      "梅森·莫菲特",        "Mason Morfit",        "ValueAct Capital",          "价值行动资本"),
    ("0000909661", "FARALLON",      "法拉龙资本",          "Farallon Capital",    "Farallon Capital",          "法拉龙资本"),
    ("0001318757", "MARSHALL WACE", "马歇尔·韦斯",        "Marshall Wace",       "Marshall Wace",             "马歇尔·韦斯"),
    ("0001374519", "NORGES",        "挪威主权基金",        "Norges Bank IM",      "Norges Bank",               "挪威央行投资管理"),
    ("0000860643", "RUSSO",         "汤姆·鲁索",          "Tom Russo",           "Gardner Russo & Quinn",     "加德纳·鲁索"),
    ("0001647251", "TCI FUND",      "克里斯·霍恩",        "Chris Hohn",          "TCI Fund Management",       "英国儿童投资基金"),
    ("0001747057", "D1 CAPITAL",    "丹·桑德海姆",        "Dan Sundheim",        "D1 Capital",                "D1资本"),
    ("0001657335", "COOPERMAN",     "莱昂·库珀曼",        "Leon Cooperman",      "Omega Family Office",       "欧米茄家族办公室"),
    ("0001541617", "ALTIMETER",     "布拉德·格斯特纳",    "Brad Gerstner",       "Altimeter Capital",         "阿尔提米特资本"),
    ("0001135778", "MILLER VALUE",  "比尔·米勒",          "Bill Miller",         "Miller Value Partners",     "米勒价值合伙"),
    ("0001039565", "KAHN BROTHERS", "卡恩兄弟",            "Kahn Brothers",       "Kahn Brothers Group",       "卡恩兄弟集团"),
    ("0000905567", "YACKTMAN",      "雅克曼资产管理",      "Yacktman AM",         "Yacktman Asset Management", "雅克曼资产管理"),
    ("0001034524", "POLEN",         "波伦资本",            "Polen Capital",       "Polen Capital",             "波伦资本"),
    ("0000860585", "ROYCE",         "查克·罗伊斯",        "Chuck Royce",         "Royce Investment",          "罗伊斯投资"),
    ("0001631664", "PUNCH CARD",    "诺伯特·卢",          "Norbert Lou",         "Punch Card Management",     "打孔卡资本管理"),
    ("0000883965", "WEITZ",         "华莱士·魏茨",        "Wally Weitz",         "Weitz Investment",          "魏茨投资管理"),
    ("0001027796", "PZENA",         "理查德·普泽纳",      "Richard Pzena",       "Pzena Investment",          "普泽纳投资管理"),
    ("0000813917", "HARRIS ASSOC",  "哈里斯联合(奥克马克)","Harris Associates",   "Harris Associates (Oakmark)","哈里斯联合"),
    ("0001088875", "BAILLIE",       "柏基投资",            "Baillie Gifford",     "Baillie Gifford & Co",      "柏基投资"),
]

# 主权财富基金（只有向 SEC 提交 13F 的才拿得到美股持仓）。
# CIK / 机构名校验关键词 / 中文名 / 英文名 / 国家(中) / 旗帜 / 官网域名(图标)
# 关键词校验不通过者自动跳过——CIK 不确定的靠此保护，不会写入错误数据。
# 说明：ADIA(阿布扎比)、CIC(中投)、KIA(科威特)、QIA(卡塔尔)、HKMA(香港)等
# 不提交 13F 或通过外部管理人持有，免费公开渠道无持仓明细，故不在可抓取之列。
# 仅收录「当前仍按季向 SEC 提交 13F-HR（含完整美股持仓明细）」的主权/公共基金。
# CIK 均已比对 EDGAR 归档确认为对应实体本尊（关键词校验再兜底防串号）。
# GIC 仅报 13G、阿拉斯加/新西兰/澳洲未来基金不申报 13F，故不列卡片（见下方规模榜）。
SWF_FUNDS = [
    ("0001374170", "NORGES",            "挪威主权基金",     "Norges Bank",           "挪威",   "🇳🇴", "nbim.no"),
    ("0001767640", "PUBLIC INVESTMENT", "沙特公共投资基金", "Saudi PIF",             "沙特",   "🇸🇦", "pif.gov.sa"),
    ("0001283718", "CANADA PENSION",    "加拿大养老基金",   "CPP Investments",       "加拿大", "🇨🇦", "cppinvestments.com"),
    ("0001021944", "TEMASEK",           "淡马锡",           "Temasek Holdings",      "新加坡", "🇸🇬", "temasek.com.sg"),
    ("0001704268", "MUBADALA",          "穆巴达拉",         "Mubadala",              "阿联酋", "🇦🇪", "mubadala.com"),
    ("0001441689", "KOREA INVEST",      "韩国投资公司",     "Korea Investment Corp", "韩国",   "🇰🇷", "kic.kr"),
    ("0001223779", "TEXAS PERM",        "德州永久学校基金", "Texas Permanent School","美国",   "🇺🇸", "texaspsf.org"),
]

# 前 20 大主权基金参考榜（按规模，AUM 为近似值，$十亿）。会披露 13F 的在上表；
# 不披露的仅在此列出规模，供页面展示"全景 + 数据边界"。
SWF_TOP20 = [
    {"zh": "挪威主权基金", "en": "Norway GPFG (NBIM)", "flag": "🇳🇴", "aum": 1780, "disc": True},
    {"zh": "中投公司", "en": "China CIC", "flag": "🇨🇳", "aum": 1350, "disc": False},
    {"zh": "阿布扎比投资局", "en": "Abu Dhabi ADIA", "flag": "🇦🇪", "aum": 1110, "disc": False},
    {"zh": "沙特公共投资基金", "en": "Saudi PIF", "flag": "🇸🇦", "aum": 940, "disc": True},
    {"zh": "科威特投资局", "en": "Kuwait KIA", "flag": "🇰🇼", "aum": 920, "disc": False},
    {"zh": "新加坡 GIC", "en": "Singapore GIC", "flag": "🇸🇬", "aum": 800, "disc": False},
    {"zh": "香港金管局", "en": "Hong Kong HKMA", "flag": "🇭🇰", "aum": 700, "disc": False},
    {"zh": "卡塔尔投资局", "en": "Qatar QIA", "flag": "🇶🇦", "aum": 530, "disc": False},
    {"zh": "淡马锡", "en": "Singapore Temasek", "flag": "🇸🇬", "aum": 490, "disc": True},
    {"zh": "加拿大养老基金", "en": "Canada CPP", "flag": "🇨🇦", "aum": 480, "disc": True},
    {"zh": "阿布扎比穆巴达拉", "en": "Mubadala", "flag": "🇦🇪", "aum": 330, "disc": True},
    {"zh": "韩国投资公司", "en": "Korea KIC", "flag": "🇰🇷", "aum": 200, "disc": True},
    {"zh": "澳大利亚未来基金", "en": "Australia Future Fund", "flag": "🇦🇺", "aum": 180, "disc": False},
    {"zh": "土耳其财富基金", "en": "Turkey TWF", "flag": "🇹🇷", "aum": 160, "disc": False},
    {"zh": "伊朗国家发展基金", "en": "Iran NDF", "flag": "🇮🇷", "aum": 150, "disc": False},
    {"zh": "阿布扎比 ADQ", "en": "Abu Dhabi ADQ", "flag": "🇦🇪", "aum": 150, "disc": False},
    {"zh": "阿拉斯加永久基金", "en": "Alaska Permanent", "flag": "🇺🇸", "aum": 80, "disc": False},
    {"zh": "新西兰超级基金", "en": "NZ Super Fund", "flag": "🇳🇿", "aum": 55, "disc": False},
    {"zh": "德州永久学校基金", "en": "Texas PSF", "flag": "🇺🇸", "aum": 55, "disc": True},
    {"zh": "俄罗斯国家财富基金", "en": "Russia NWF", "flag": "🇷🇺", "aum": 130, "disc": False},
]

# 常见 CUSIP(前6位) → (股票代码, 中文名)；映射不到再用 NAME_ZH 关键词兜底
CUSIP_INFO = {
    "037833": ("AAPL", "苹果"), "594918": ("MSFT", "微软"), "023135": ("AMZN", "亚马逊"),
    "02079K": ("GOOG", "谷歌"), "30303M": ("META", "Meta平台"), "88160R": ("TSLA", "特斯拉"),
    "67066G": ("NVDA", "英伟达"), "11135F": ("AVGO", "博通"), "874039": ("TSM", "台积电"),
    "092857": ("BRK.B", "伯克希尔·哈撒韦"), "084670": ("BRK.B", "伯克希尔·哈撒韦"),
    "060505": ("BAC", "美国银行"), "025816": ("AXP", "美国运通"), "191216": ("KO", "可口可乐"),
    "166764": ("CVX", "雪佛龙"), "674599": ("OXY", "西方石油"), "30231G": ("XOM", "埃克森美孚"),
    "20825C": ("COP", "康菲石油"), "718546": ("PSX", "菲利普斯66"), "806857": ("SLB", "斯伦贝谢"),
    "406216": ("HAL", "哈里伯顿"), "718172": ("PM", "菲利普莫里斯"), "02209S": ("MO", "奥驰亚"),
    "580135": ("MCD", "麦当劳"), "855244": ("SBUX", "星巴克"), "169656": ("CMG", "墨式烧烤"),
    "988498": ("YUM", "百胜餐饮"), "98850P": ("YUMC", "百胜中国"), "742718": ("PG", "宝洁"),
    "478160": ("JNJ", "强生"), "931142": ("WMT", "沃尔玛"), "22160K": ("COST", "开市客"),
    "87612E": ("TGT", "塔吉特"), "437076": ("HD", "家得宝"), "548661": ("LOW", "劳氏"),
    "654106": ("NKE", "耐克"), "550021": ("LULU", "露露乐蒙"), "29786A": ("EL", "雅诗兰黛"),
    "92826C": ("V", "维萨"), "57636Q": ("MA", "万事达"), "70450Y": ("PYPL", "贝宝"),
    "46625H": ("JPM", "摩根大通"), "172967": ("C", "花旗集团"), "949746": ("WFC", "富国银行"),
    "902973": ("USB", "美国合众银行"), "38141G": ("GS", "高盛"), "617446": ("MS", "摩根士丹利"),
    "064058": ("BK", "纽约梅隆银行"), "857477": ("STT", "道富"), "808513": ("SCHW", "嘉信理财"),
    "09247X": ("BLK", "贝莱德"), "09260D": ("BX", "黑石"), "037604": ("APO", "阿波罗全球"),
    "27579R": ("EWBC", "华美银行"), "254687": ("DIS", "迪士尼"), "64110L": ("NFLX", "奈飞"),
    "20030N": ("CMCSA", "康卡斯特"), "92343V": ("VZ", "威瑞森"), "00206R": ("T", "AT&T"),
    "16119P": ("CHTR", "特许通讯"), "82968B": ("SIRI", "天狼星XM"), "716973": ("PFE", "辉瑞"),
    "58933Y": ("MRK", "默沙东"), "002824": ("ABT", "雅培"), "532457": ("LLY", "礼来"),
    "00287Y": ("ABBV", "艾伯维"), "110122": ("BMY", "百时美施贵宝"), "031162": ("AMGN", "安进"),
    "375558": ("GILD", "吉利德"), "60770K": ("MRNA", "莫德纳"), "75886F": ("REGN", "再生元"),
    "92532F": ("VRTX", "福泰制药"), "91324P": ("UNH", "联合健康"), "126650": ("CVS", "CVS健康"),
    "125523": ("CI", "信诺"), "444859": ("HUM", "哈门那"), "40412C": ("HCA", "HCA医疗"),
    "883556": ("TMO", "赛默飞世尔"), "235851": ("DHR", "丹纳赫"), "585055": ("MDT", "美敦力"),
    "46120E": ("ISRG", "直觉外科"), "097023": ("BA", "波音"), "539830": ("LMT", "洛克希德·马丁"),
    "75513E": ("RTX", "雷神技术"), "666807": ("NOC", "诺斯罗普"), "369550": ("GD", "通用动力"),
    "369604": ("GE", "通用电气"), "149123": ("CAT", "卡特彼勒"), "244199": ("DE", "迪尔"),
    "438516": ("HON", "霍尼韦尔"), "88579Y": ("MMM", "3M"), "907818": ("UNP", "联合太平洋"),
    "136375": ("CNI", "加拿大国家铁路"), "13646K": ("CP", "加拿大太平洋堪萨斯城"),
    "126408": ("CSX", "CSX运输"), "655844": ("NSC", "诺福克南方"), "31428X": ("FDX", "联邦快递"),
    "911312": ("UPS", "联合包裹"), "247361": ("DAL", "达美航空"), "910047": ("UAL", "美联航"),
    "02376R": ("AAL", "美国航空"), "844741": ("LUV", "西南航空"), "90353T": ("UBER", "优步"),
    "009066": ("ABNB", "爱彼迎"), "09857L": ("BKNG", "缤客"), "30212P": ("EXPE", "亿客行"),
    "571903": ("MAR", "万豪"), "43300A": ("HLT", "希尔顿"), "517834": ("LVS", "金沙集团"),
    "552953": ("MGM", "美高梅"), "983134": ("WYNN", "永利度假村"), "89677Q": ("TCOM", "携程"),
    "458140": ("INTC", "英特尔"), "007903": ("AMD", "超威半导体"), "747525": ("QCOM", "高通"),
    "595112": ("MU", "美光科技"), "882508": ("TXN", "德州仪器"), "038222": ("AMAT", "应用材料"),
    "512807": ("LRCX", "泛林集团"), "N07059": ("ASML", "阿斯麦"), "459200": ("IBM", "IBM"),
    "68389X": ("ORCL", "甲骨文"), "79466L": ("CRM", "赛富时"), "00724F": ("ADBE", "奥多比"),
    "17275R": ("CSCO", "思科"), "40434L": ("HPQ", "惠普"), "G5960L": ("STX", "希捷"),
    "98980L": ("ZM", "Zoom"), "70614W": ("PLTR", "帕兰提尔"), "82509L": ("SHOP", "Shopify"),
    "615369": ("MCO", "穆迪"), "78409V": ("SPGI", "标普全球"), "55354G": ("MSCI", "MSCI明晟"),
    "45866F": ("ICE", "洲际交易所"), "12572Q": ("CME", "芝商所"),
    "500754": ("KHC", "卡夫亨氏"), "501044": ("KR", "克罗格"), "609207": ("MDLZ", "亿滋国际"),
    "370334": ("GIS", "通用磨坊"), "427866": ("HSY", "好时"), "713448": ("PEP", "百事"),
    "863667": ("STZ", "星座品牌"), "01609W": ("BABA", "阿里巴巴"), "47215P": ("JD", "京东"),
    "722304": ("PDD", "拼多多"), "056752": ("BIDU", "百度"), "64110W": ("NTES", "网易"),
    "88034P": ("TME", "腾讯音乐"), "81141R": ("SE", "冬海集团"), "58733R": ("MELI", "美客多"),
    "62914V": ("NIO", "蔚来"), "50202M": ("LI", "理想汽车"), "98422D": ("XPEV", "小鹏汽车"),
    "65339F": ("NEE", "新纪元能源"), "26441C": ("DUK", "杜克能源"), "842587": ("SO", "南方电力"),
    "35671D": ("FCX", "自由港"), "651639": ("NEM", "纽蒙特"), "067901": ("GOLD", "巴里克黄金"),
    "013872": ("AA", "美国铝业"), "670346": ("NUE", "纽柯钢铁"), "260543": ("DOW", "陶氏"),
    "26614N": ("DD", "杜邦"), "009158": ("APD", "空气产品"), "824348": ("SHW", "宣伟"),
    "278865": ("ECL", "艺康集团"), "94106L": ("WM", "废物管理"), "94106B": ("WCN", "废物连接"),
    "760759": ("RSG", "共和服务"), "03027X": ("AMT", "美国铁塔"), "74340W": ("PLD", "普洛斯"),
    "29444U": ("EQIX", "易昆尼克斯"), "828806": ("SPG", "西蒙地产"),
    "78462F": ("SPY", "标普500 ETF"), "46090E": ("QQQ", "纳指100 ETF"),
    "464287": ("IVV", "安硕ETF"), "78463V": ("GLD", "黄金ETF"), "922908": ("VOO", "先锋标普500 ETF"),
    "22788C": ("CROX", "卡骆驰"), "18915M": ("CLF", "克利夫兰-克利夫斯"),
    "05464C": ("AXON", "艾克森企业"), "68622V": ("ORLY", "奥莱利汽配"), "285512": ("EA", "艺电"),
    "532806": ("LEN", "莱纳建筑"), "486668": ("KHC", "卡夫亨氏"), "902494": ("TJX", "TJX折扣百货"),
}

# 公司名关键词 → 中文（CUSIP 映射不到时兜底；顺序敏感：更具体的放前面）
NAME_ZH = [
    ("INTUITIVE SURGICAL", "直觉外科"), ("COCA COLA FEMSA|COCA-COLA FEMSA", "可口可乐FEMSA"),
    ("COCA COLA|COCA-COLA", "可口可乐"), ("YUM CHINA", "百胜中国"), ("YUM BRANDS", "百胜餐饮"),
    ("GE VERNOVA", "GE维诺瓦(能源)"), ("GE HEALTHCARE", "GE医疗"), ("GENERAL ELEC", "通用电气"),
    ("BERKSHIRE", "伯克希尔·哈撒韦"), ("APPLE INC", "苹果"), ("MICROSOFT", "微软"),
    ("ALPHABET", "谷歌"), ("AMAZON", "亚马逊"), ("META PLATFORMS", "Meta平台"),
    ("NVIDIA", "英伟达"), ("TESLA", "特斯拉"), ("TAIWAN SEMI", "台积电"), ("BROADCOM", "博通"),
    ("ALIBABA", "阿里巴巴"), ("JD.COM|JD COM", "京东"), ("PINDUODUO|PDD HLDGS|PDD HOLDINGS", "拼多多"),
    ("BAIDU", "百度"), ("NETEASE", "网易"), ("SEA LTD", "冬海集团"), ("MERCADOLIBRE", "美客多"),
    ("PEPSI", "百事"), ("MCDONALD", "麦当劳"), ("STARBUCKS", "星巴克"), ("CHIPOTLE", "墨式烧烤"),
    ("RESTAURANT BRANDS", "餐饮品牌国际"), ("DOMINO", "达美乐比萨"),
    ("WALMART|WAL MART", "沃尔玛"), ("COSTCO", "开市客"), ("TARGET CORP", "塔吉特"),
    ("HOME DEPOT", "家得宝"), ("NIKE", "耐克"), ("LULULEMON", "露露乐蒙"), ("ULTA", "Ulta美妆"),
    ("WALT DISNEY|DISNEY", "迪士尼"), ("NETFLIX", "奈飞"), ("SPOTIFY", "声田"),
    ("VISA INC", "维萨"), ("MASTERCARD", "万事达"), ("PAYPAL", "贝宝"),
    ("AMERICAN EXPRESS", "美国运通"), ("JPMORGAN", "摩根大通"), ("BANK AMER|BANK OF AMER", "美国银行"),
    ("WELLS FARGO", "富国银行"), ("CITIGROUP", "花旗集团"), ("GOLDMAN", "高盛"),
    ("MORGAN STANLEY", "摩根士丹利"), ("BLACKROCK", "贝莱德"), ("BLACKSTONE", "黑石"),
    ("BROOKFIELD", "布鲁克菲尔德"), ("APOLLO GLOBAL", "阿波罗全球"), ("KKR", "KKR"),
    ("CHEVRON", "雪佛龙"), ("EXXON", "埃克森美孚"), ("OCCIDENTAL", "西方石油"),
    ("CONOCOPHILLIPS", "康菲石油"), ("CHENIERE", "切尼尔能源"), ("VISTRA", "Vistra能源"),
    ("JOHNSON & JOHNSON|JOHNSON JOHNSON", "强生"), ("PFIZER", "辉瑞"), ("MERCK", "默沙东"),
    ("ELI LILLY|LILLY ELI", "礼来"), ("UNITEDHEALTH", "联合健康"), ("NOVO NORDISK", "诺和诺德"),
    ("ASTRAZENECA", "阿斯利康"), ("TEVA PHARM", "梯瓦制药"),
    ("BOEING", "波音"), ("LOCKHEED", "洛克希德·马丁"), ("RTX CORP|RAYTHEON", "雷神技术"),
    ("CATERPILLAR", "卡特彼勒"), ("DEERE", "迪尔"), ("HONEYWELL", "霍尼韦尔"),
    ("UBER", "优步"), ("LYFT", "来福车"), ("AIRBNB", "爱彼迎"), ("BOOKING", "缤客"),
    ("MARRIOTT", "万豪"), ("HILTON", "希尔顿"), ("DELTA AIR", "达美航空"),
    ("UNITED AIRLS|UNITED AIRLINES", "美联航"), ("FEDEX", "联邦快递"), ("UNITED PARCEL", "联合包裹"),
    ("INTEL CORP", "英特尔"), ("MICRON", "美光科技"), ("QUALCOMM", "高通"),
    ("ADVANCED MICRO", "超威半导体"), ("TEXAS INSTR", "德州仪器"), ("APPLIED MATL|APPLIED MATERIALS", "应用材料"),
    ("LAM RESEARCH", "泛林集团"), ("ASML", "阿斯麦"), ("ARM HOLDINGS", "安谋"),
    ("ORACLE", "甲骨文"), ("SALESFORCE", "赛富时"), ("ADOBE", "奥多比"), ("CISCO", "思科"),
    ("INTL BUSINESS MACH", "IBM"), ("SERVICENOW", "ServiceNow"), ("INTUIT INC", "财捷"),
    ("PALANTIR", "帕兰提尔"), ("SNOWFLAKE", "雪花公司"), ("CROWDSTRIKE", "CrowdStrike"),
    ("PALO ALTO", "派拓网络"), ("ARISTA", "阿里斯塔网络"), ("DELL TECH", "戴尔"),
    ("HP INC", "惠普"), ("SEAGATE", "希捷"), ("WESTERN DIGITAL", "西部数据"),
    ("KRAFT HEINZ", "卡夫亨氏"), ("KROGER", "克罗格"), ("MONDELEZ", "亿滋国际"),
    ("PROCTER", "宝洁"), ("UNILEVER", "联合利华"), ("COLGATE", "高露洁"),
    ("ESTEE LAUDER", "雅诗兰黛"), ("PHILIP MORRIS", "菲利普莫里斯"), ("ALTRIA", "奥驰亚"),
    ("BRITISH AMERN TOB|BRITISH AMERICAN TOB", "英美烟草"), ("CONSTELLATION BRANDS", "星座品牌"),
    ("CONSTELLATION ENERGY", "星座能源"), ("MOODY", "穆迪"), ("S&P GLOBAL", "标普全球"),
    ("CHUBB", "安达保险"), ("PROGRESSIVE", "前进保险"), ("ALLSTATE", "好事达"),
    ("TRAVELERS", "旅行者保险"), ("METLIFE", "大都会人寿"), ("AMERICAN INTL GROUP", "美国国际集团"),
    ("MARSH & MC|MARSH MC", "威达信"), ("AON PLC", "怡安"),
    ("WASTE MGMT|WASTE MANAGEMENT", "废物管理"), ("WASTE CONNECTIONS", "废物连接"),
    ("REPUBLIC SVCS|REPUBLIC SERVICES", "共和服务"), ("CANADIAN NATL", "加拿大国家铁路"),
    ("CANADIAN PAC", "加拿大太平洋"), ("UNION PAC", "联合太平洋"), ("NORFOLK SOUTHERN", "诺福克南方"),
    ("CSX CORP", "CSX运输"), ("ECOLAB", "艺康集团"), ("SHERWIN", "宣伟"), ("LINDE", "林德"),
    ("AIR PRODS", "空气产品"), ("FREEPORT", "自由港"), ("NEWMONT", "纽蒙特"),
    ("BARRICK", "巴里克黄金"), ("NUCOR", "纽柯钢铁"), ("ALCOA", "美国铝业"),
    ("CHARTER COMMN|CHARTER COMMUNICATIONS", "特许通讯"), ("LIBERTY MEDIA", "自由媒体"),
    ("LIBERTY BROADBAND", "自由宽带"), ("SIRIUS XM", "天狼星XM"), ("WARNER BROS", "华纳兄弟探索"),
    ("PARAMOUNT", "派拉蒙"), ("FOX CORP", "福克斯"), ("NEWS CORP", "新闻集团"),
    ("T-MOBILE|T MOBILE", "T-Mobile美国"), ("VERIZON", "威瑞森"), ("AT&T", "AT&T"),
    ("COMCAST", "康卡斯特"), ("EAST WEST BANCORP", "华美银行"), ("SHOPIFY", "Shopify"),
    ("COINBASE", "Coinbase"), ("MICROSTRATEGY|STRATEGY INC", "微策略"), ("ROBINHOOD", "罗宾侠"),
    ("NU HLDGS|NU HOLDINGS", "Nu控股"), ("COUPANG", "酷澎"), ("GRAB HLDGS|GRAB HOLDINGS", "Grab控股"),
    ("GENERAL MTRS|GENERAL MOTORS", "通用汽车"), ("FORD MTR|FORD MOTOR", "福特汽车"),
    ("FERRARI", "法拉利"), ("RIVIAN", "Rivian"), ("SPDR S&P 500", "标普500 ETF"),
    ("SPDR GOLD", "黄金ETF"), ("ISHARES", "安硕ETF"), ("VANGUARD", "先锋ETF"),
    ("INVESCO QQQ", "纳指100 ETF"), ("HOWARD HUGHES", "霍华德·休斯"), ("SEAPORT", "海港娱乐"),
    ("DAVITA", "德维特"), ("VERISIGN", "威瑞信"), ("AKAMAI", "阿卡迈"),
    ("STATE STR", "道富"), ("BANK OF NEW YORK|BANK NEW YORK", "纽约梅隆银行"),
    ("CHARLES SCHWAB|SCHWAB CHARLES", "嘉信理财"),
]
NAME_ZH_COMPILED = [(re.compile("|".join(re.escape(k) for k in kw.split("|"))), zh)
                    for kw, zh in NAME_ZH]
TICKER_ZH = {v[0]: v[1] for v in CUSIP_INFO.values()}

# 政治人物（国会 STOCK Act 披露）：bioguide ID / 姓氏校验 / 中文 / 英文 / 党派 / 职务 / 州
# 头像优先维基百科（见 POL_WIKI），失败回退国会官方照片库（theunitedstates.io）。
# 注：特朗普属行政分支，交易走 OGE 财产申报（无免费结构化数据源），故不在此列；
#     万斯收录的是其 2023–2025 参议员任期的披露。
POLITICIANS = [
    ("P000197", "PELOSI",     "南希·佩洛西",       "Nancy Pelosi",          "D", "众议院",          "加利福尼亚"),
    ("V000137", "VANCE",      "JD·万斯",           "J.D. Vance",            "R", "副总统(前参议员)", "俄亥俄"),
    ("K000389", "KHANNA",     "罗·卡纳",           "Ro Khanna",             "D", "众议院",          "加利福尼亚"),
    ("M001157", "MCCAUL",     "迈克尔·麦考尔",     "Michael McCaul",        "R", "众议院",          "得克萨斯"),
    ("G000596", "GREENE",     "玛乔丽·泰勒·格林",  "Marjorie Taylor Greene", "R", "众议院",          "佐治亚"),
    ("C001120", "CRENSHAW",   "丹·克伦肖",         "Dan Crenshaw",          "R", "众议院",          "得克萨斯"),
    ("G000583", "GOTTHEIMER", "乔什·戈特海默",     "Josh Gottheimer",       "D", "众议院",          "新泽西"),
    ("T000278", "TUBERVILLE", "汤米·塔伯维尔",     "Tommy Tuberville",      "R", "参议院",          "阿拉巴马"),
    ("M001190", "MULLIN",     "马克韦恩·穆林",     "Markwayne Mullin",      "R", "参议院",          "俄克拉荷马"),
    ("S001217", "SCOTT",      "里克·斯科特",       "Rick Scott",            "R", "参议院",          "佛罗里达"),
    ("B001299", "BANKS",      "吉姆·班克斯",       "Jim Banks",             "R", "参议院",          "印第安纳"),
    ("F000110", "FIELDS",     "克莱奥·菲尔兹",     "Cleo Fields",           "D", "众议院",          "路易斯安那"),
    ("M001243", "MCCORMICK",  "戴夫·麦考密克",     "Dave McCormick",        "R", "参议院",          "宾夕法尼亚"),
    ("M001206", "MACE",       "南希·梅斯",         "Nancy Mace",            "R", "众议院",          "南卡罗来纳"),
    ("M001136", "MCCLAIN",    "丽莎·麦克莱恩",     "Lisa McClain",          "R", "众议院",          "密歇根"),
    ("D000617", "DELBENE",    "苏珊·德尔贝内",     "Suzan DelBene",         "D", "众议院",          "华盛顿州"),
    ("C001123", "CISNEROS",   "吉尔伯特·西斯内罗斯","Gilbert Cisneros",      "D", "众议院",          "加利福尼亚"),
    ("W000829", "WIED",       "托尼·维德",         "Tony Wied",             "R", "众议院",          "威斯康星"),
]

# 政治人物头像优先用维基百科（与投资者同源，浏览器可直连 upload.wikimedia.org）；
# 维基无照片时回退国会官方照片库。bioguide → 维基条目名。
POL_WIKI = {
    "P000197": "Nancy Pelosi", "V000137": "JD Vance", "K000389": "Ro Khanna",
    "M001157": "Michael McCaul", "G000596": "Marjorie Taylor Greene", "C001120": "Dan Crenshaw",
    "G000583": "Josh Gottheimer", "T000278": "Tommy Tuberville", "M001190": "Markwayne Mullin",
    "S001217": "Rick Scott", "B001299": "Jim Banks (Indiana politician)", "F000110": "Cleo Fields",
    "M001243": "Dave McCormick", "M001206": "Nancy Mace", "M001136": "Lisa McClain",
    "D000617": "Suzan DelBene", "C001123": "Gil Cisneros", "W000829": "Tony Wied",
}

STOP = time.time() + 40 * 60  # 全局硬止损，避免 Actions 卡死


def zh_of(cusip6, raw_name):
    """公司中文名：CUSIP 精确映射优先，公司名关键词兜底，找不到返回空串。"""
    info = CUSIP_INFO.get(cusip6)
    if info:
        return info[1]
    up = re.sub(r"\s+", " ", str(raw_name or "").upper())
    for pat, zh in NAME_ZH_COMPILED:
        if pat.search(up):
            return zh
    return ""


def ticker_of(cusip6):
    info = CUSIP_INFO.get(cusip6)
    return info[0] if info else ""


def get(url, headers, timeout=30, tries=3):
    for i in range(tries):
        if time.time() > STOP:
            return None
        try:
            r = requests.get(url, headers=headers, timeout=timeout)
            if r.status_code == 200:
                return r
            print(f"  HTTP {r.status_code}: {url[:90]}")
        except Exception as e:
            print(f"  请求失败({i + 1}/{tries}): {str(e)[:90]}")
        time.sleep(1.2 * (i + 1))
    return None


def sec_get(url, **kw):
    time.sleep(0.25)  # SEC 公平使用限速
    return get(url, SEC_HEADERS, **kw)


# ---------------------------------------------------------------- 头像
_wiki_cache = {}


def wiki_imgs_batch(titles):
    """维基百科批量取条目缩略图：action API + pageimages。
    关键：pageimages 批量查询必须带 pilimit=max，否则默认只对前若干页返回
    缩略图、其余走 continue 分页——不处理会漏掉大部分人。分页续拉直到取完。
    每批 ≤50 标题，避免逐个请求触发共享出口 IP 的 429 限速。"""
    todo = [t for t in dict.fromkeys(titles) if t and t not in _wiki_cache]
    # 每批 20 个标题：pageimages 单请求返回的缩略图有内部上限，50 个会漏掉大半，
    # 20 个可一次全拿到（叠加 pilimit=max + picontinue 分页兜底）。
    for i in range(0, len(todo), 20):
        chunk = todo[i:i + 20]
        # pilicense=any：默认只返回「自由许可」的 page image，很多传记信息框照片
        # 因此被过滤（李录/伯里/佩尔茨等），加 any 后覆盖大幅提升。
        base = ("https://en.wikipedia.org/w/api.php?action=query&format=json"
                "&prop=pageimages&piprop=thumbnail&pithumbsize=200&pilimit=max&pilicense=any"
                "&redirects=1&titles=" + requests.utils.quote("|".join(chunk)))
        cont, guard = "", 0
        back = {}
        while guard < 8:
            guard += 1
            r = get(base + cont, WIKI_HEADERS, timeout=30, tries=3)
            if not r:
                break
            try:
                data = r.json()
            except Exception:
                break
            q = data.get("query") or {}
            # normalized/redirects：{from: 请求名, to: 结果名}，反向映射回请求标题
            for m in (q.get("normalized") or []) + (q.get("redirects") or []):
                if m.get("to") and m.get("from"):
                    back[m["to"]] = m["from"]
            for pg in (q.get("pages") or {}).values():
                src = ((pg.get("thumbnail") or {}).get("source")) or ""
                if not src:
                    continue
                t, seen = pg.get("title"), set()
                while t in back and t not in seen:
                    seen.add(t)
                    t = back[t]
                if t:
                    _wiki_cache[t] = src
            nxt = (data.get("continue") or {}).get("picontinue")
            if not nxt:
                break
            cont = "&picontinue=" + requests.utils.quote(str(nxt))
            time.sleep(.4)
        time.sleep(.8)
    # pageimages 只对被标记「page image」的条目返回缩略图，李录/伯里/佩尔茨等
    # 页面虽有信息框照片却未被标记，会漏。对批量没拿到的标题，逐个用 REST
    # summary 接口兜底——它对几乎所有带信息框照片的传记页都返回缩略图。
    rest_hit = 0
    for t in todo:
        if _wiki_cache.get(t):
            continue
        url = ("https://en.wikipedia.org/api/rest_v1/page/summary/" +
               requests.utils.quote(t.replace(" ", "_")) + "?redirect=true")
        r = get(url, WIKI_HEADERS, timeout=20, tries=2)
        img = ""
        if r:
            try:
                d = r.json()
                if d.get("type") != "disambiguation":
                    img = ((d.get("thumbnail") or {}).get("source")) or ""
            except Exception:
                pass
        _wiki_cache[t] = img
        if img:
            rest_hit += 1
        time.sleep(.5)
    print(f"  头像批量解析：pageimages {sum(1 for t in todo if _wiki_cache.get(t)) - rest_hit}"
          f" + REST 兜底 {rest_hit} = {sum(1 for t in todo if _wiki_cache.get(t))}/{len(todo)}")


def wiki_img(title):
    """维基百科条目缩略图 URL（自由许可图片），失败返回空串。"""
    if not title:
        return ""
    if title in _wiki_cache:
        return _wiki_cache[title]
    time.sleep(1.2)  # 维基 REST API 对共享出口 IP 限速较严，逐个慢取
    url = ("https://en.wikipedia.org/api/rest_v1/page/summary/" +
           requests.utils.quote(title.replace(" ", "_")) + "?redirect=true")
    r = get(url, WIKI_HEADERS, timeout=20, tries=3)
    img = ""
    if r:
        try:
            d = r.json()
            if d.get("type") != "disambiguation":
                img = ((d.get("thumbnail") or {}).get("source")) or ""
        except Exception:
            pass
    _wiki_cache[title] = img
    return img


def congress_img(bioguide):
    """国会官方照片库（公有领域，按 bioguide ID 直链）。"""
    return f"https://theunitedstates.io/images/congress/225x275/{bioguide}.jpg"


# ---------------------------------------------------------------- 国会交易
def _mid(lo, hi, val):
    if isinstance(val, (int, float)) and val > 0:
        return float(val)
    try:
        return (float(lo) + float(hi)) / 2
    except (TypeError, ValueError):
        return 0.0


_AMOUNT_RE = re.compile(r"\$([\d,]+)\s*(?:-\s*\$([\d,]+))?")

# 议员交易数据源：Financial Modeling Prep 国会披露接口（免费 API Key，
# 由仓库 Secret FMP_API_KEY 注入）。无 Key 或失败时保留上次数据。
FMP_KEY = os.environ.get("FMP_API_KEY", "").strip()


def parse_fmp_rows(rows, bioguide, first_en, kw):
    """把 FMP 国会披露行转成内部交易格式，并做身份校验（防重名/串号）。"""
    out, seen = [], set()
    for t in rows if isinstance(rows, list) else []:
        if not isinstance(t, dict):
            continue
        bid = str(t.get("senateID") or t.get("bioguideId") or "").strip()
        last = str(t.get("lastName") or "").upper()
        first = str(t.get("firstName") or "").upper()
        office = str(t.get("office") or "").upper()
        if bid:
            if bid != bioguide:
                continue
        elif not ((kw in last or kw in office) and (not first or first_en in first)):
            continue
        amount = str(t.get("amount") or "")
        m = _AMOUNT_RE.search(amount)
        lo = int(m.group(1).replace(",", "")) if m else None
        hi = int(m.group(2).replace(",", "")) if m and m.group(2) else lo
        tx = str(t.get("type") or "").lower()
        typ = "buy" if "purchase" in tx or "buy" in tx else ("sell" if "sale" in tx or "sell" in tx else "other")
        ticker = str(t.get("symbol") or "").strip()
        if ticker.upper() in ("--", "N/A", "NONE"):
            ticker = ""
        name = re.sub(r"\s+", " ", str(t.get("assetDescription") or "")).strip()[:70]
        date = str(t.get("transactionDate") or "")[:10]
        key = (date, ticker, name[:20], typ, amount, str(t.get("owner") or ""))
        if key in seen:
            continue
        seen.add(key)
        out.append({
            "date": date,
            "filed": str(t.get("disclosureDate") or t.get("dateRecieved") or "")[:10],
            "type": typ, "ticker": ticker, "name": name,
            "zh": TICKER_ZH.get(ticker, "") or zh_of("", name),
            "lo": lo, "hi": hi, "mid": round(_mid(lo, hi, None)),
        })
    return out


def fmp_trades_by_name(chamber, last_name):
    """chamber: 'house' | 'senate'。尝试 stable 与 v4 两代接口路径。"""
    if not FMP_KEY:
        return None
    name_q = requests.utils.quote(last_name)
    v4 = "senate-trading" if chamber == "senate" else "senate-disclosure"
    urls = [
        f"https://financialmodelingprep.com/stable/{chamber}-trades-by-name?name={name_q}&apikey={FMP_KEY}",
        f"https://financialmodelingprep.com/api/v4/{v4}-by-name?name={name_q}&apikey={FMP_KEY}",
    ]
    for url in urls:
        r = get(url, WEB_HEADERS, timeout=30, tries=2)
        if not r:
            continue
        try:
            d = r.json()
        except Exception:
            continue
        if isinstance(d, list):
            return d
    return None


def build_politicians():
    if not FMP_KEY:
        print("  未配置 FMP_API_KEY，跳过国会交易抓取（保留上次数据）")
        return []
    pols = []
    for bioguide, kw, zh, en, party, role_zh, state_zh in POLITICIANS:
        if time.time() > STOP:
            break
        last_name = en.split()[-1]
        first_en = en.split()[0].upper()
        trades = []
        for chamber in ("house", "senate"):
            try:
                rows = fmp_trades_by_name(chamber, last_name)
                if rows:
                    trades += parse_fmp_rows(rows, bioguide, first_en, kw)
            except Exception as e:
                print(f"  ✗ {en}({chamber}): {str(e)[:90]}")
            time.sleep(0.3)
        if not trades:
            print(f"  ✗ {en}: 无披露记录")
            continue
        trades.sort(key=lambda x: x["date"] or "", reverse=True)
        vol = sum(t["mid"] for t in trades[:30])
        pols.append({
            "zh": zh, "en": en, "party": party,
            "partyZh": "民主党" if party == "D" else "共和党",
            "roleZh": role_zh, "stateZh": state_zh,
            "img": wiki_img(POL_WIKI.get(bioguide, "")) or congress_img(bioguide),
            "bioguide": bioguide,
            "count": len(trades), "volume": round(vol),
            "lastTrade": trades[0]["date"],
            "trades": trades[:10],
        })
        print(f"  ✓ {en}: {len(trades)} 笔，最近 {trades[0]['date']}")
    pols.sort(key=lambda p: -(p["volume"] or 0))
    return pols


# ---------------------------------------------------------------- SEC 13F
def latest_13f_filings(cik):
    """返回 (机构名, [(报告期, 提交日, accession), ...] 最新两期)。"""
    r = sec_get(f"https://data.sec.gov/submissions/CIK{cik}.json")
    if not r:
        return None, []
    d = r.json()
    rec = (d.get("filings") or {}).get("recent") or {}
    by_period = {}
    for form, acc, rdate, fdate in zip(rec.get("form", []), rec.get("accessionNumber", []),
                                       rec.get("reportDate", []), rec.get("filingDate", [])):
        if form in ("13F-HR", "13F-HR/A") and rdate:
            if rdate not in by_period or fdate > by_period[rdate][0]:
                by_period[rdate] = (fdate, acc)
    periods = sorted(by_period.keys(), reverse=True)[:2]
    return d.get("name", ""), [(p, by_period[p][0], by_period[p][1]) for p in periods]


def parse_infotable(content):
    """解析 13F 持仓明细 XML → [{name,cusip,value,shares,putCall,shType}]。
    用 iterparse 增量解析：挪威主权基金这类上万行的超大明细表内存可控，且末尾
    即便被截断也能抢救已解析部分；并先跳过 XML 声明前的 BOM/空白，否则 ET 会报
    “declaration not at start of entity”，让整份文件解析失败。"""
    if isinstance(content, str):
        content = content.encode("utf-8", "ignore")
    i = content.find(b"<")
    if i > 0:
        content = content[i:]

    def local(tag):
        return tag.rsplit("}", 1)[-1]

    out = []
    try:
        for _ev, el in ET.iterparse(io.BytesIO(content), events=("end",)):
            if local(el.tag) != "infoTable":
                continue
            rec = {"name": "", "cusip": "", "value": 0.0, "shares": 0.0, "putCall": "", "shType": ""}
            for ch in el.iter():
                t, tx = local(ch.tag), (ch.text or "").strip()
                if not tx:
                    continue
                if t == "nameOfIssuer":
                    rec["name"] = tx
                elif t == "cusip":
                    rec["cusip"] = tx.upper()
                elif t == "value":
                    try:
                        rec["value"] = float(tx.replace(",", ""))
                    except ValueError:
                        pass
                elif t == "sshPrnamt":
                    try:
                        rec["shares"] = float(tx.replace(",", ""))
                    except ValueError:
                        pass
                elif t == "sshPrnamtType":
                    rec["shType"] = tx.upper()
                elif t == "putCall":
                    rec["putCall"] = tx.lower()
            if rec["cusip"] and rec["value"] > 0:
                out.append(rec)
            el.clear()  # 增量释放，界定超大明细表的内存占用
    except Exception:
        return out or None  # 截断/畸形也抢救已解析部分
    return out or None


def fetch_holdings(cik, acc):
    """抓某次 13F filing 的持仓，按 (CUSIP前6位, put/call) 聚合。"""
    cik_int = str(int(cik))
    accn = acc.replace("-", "")
    r = sec_get(f"https://www.sec.gov/Archives/edgar/data/{cik_int}/{accn}/index.json")
    if not r:
        return None
    try:
        items = r.json()["directory"]["item"]
    except Exception:
        return None
    xmls = [it["name"] for it in items if str(it.get("name", "")).lower().endswith(".xml")]
    # 明细表通常不叫 primary_doc.xml，把它排到最后再试
    xmls.sort(key=lambda n: ("primary" in n.lower(), n))
    raw = None
    for name in xmls:
        rr = sec_get(f"https://www.sec.gov/Archives/edgar/data/{cik_int}/{accn}/{name}", timeout=240)
        if rr:
            raw = parse_infotable(rr.content)
            if raw:
                break
    if not raw:
        # 兜底：个别申报人（如挪威主权基金 Norges Bank）的持仓明细未作为独立
        # .xml 单独列在目录里，改从完整提交文本 {accession}.txt 内联抽取
        # informationTable 段（含命名空间前缀）再解析。该文件同样只有几 MB。
        rr = sec_get(f"https://www.sec.gov/Archives/edgar/data/{cik_int}/{accn}/{acc}.txt", timeout=300)
        if rr:
            m = re.search(rb"<(?:\w+:)?informationTable[\s>].*</(?:\w+:)?informationTable>",
                          rr.content, re.DOTALL)
            if m:
                raw = parse_infotable(m.group(0))
    if not raw:
        return None
    agg = {}
    for rec in raw:
        key = (rec["cusip"][:6], rec["putCall"])
        a = agg.setdefault(key, {"name": rec["name"], "cusip6": rec["cusip"][:6],
                                 "putCall": rec["putCall"], "value": 0.0, "shares": 0.0})
        a["value"] += rec["value"]
        a["shares"] += rec["shares"]
        if len(rec["name"]) > len(a["name"]):
            a["name"] = rec["name"]
    # 单位纠偏：2023 年起 13F 要求以「美元」申报，但仍有机构按旧格式报「千美元」。
    # 判断条件（两条都满足才 ×1000，防止误伤）：
    # 1) 普通股（SH 类型，剔除债券本金 PRN 与期权）的隐含股价中位数 < $2 ——
    #    正常美股中位股价远高于此，而千美元申报会让隐含价缩小一千倍；
    # 2) 原始总值 < $20 亿 —— 真正的千美元申报总值只有几百万量级；
    #    信用类机构（如橡树）大量按债券本金申报，隐含"价"天然 < $2，
    #    但其总值以十亿计，靠这一条兜底不会被误乘。
    total_raw = sum(h["value"] for h in agg.values())
    prices = [r["value"] / r["shares"] for r in raw
              if r["shares"] > 0 and not r["putCall"] and r["shType"] == "SH"]
    if len(prices) >= 3 and statistics.median(prices) < 2 and total_raw < 2e9:
        for h in agg.values():
            h["value"] *= 1000
    return agg


def pretty_name(raw, put_call):
    name = re.sub(r"\s+", " ", str(raw or "")).strip().title()
    fixes = {"Inc": "Inc", "Corp": "Corp", "Ltd": "Ltd", "Plc": "PLC", "Sa": "SA",
             "Llc": "LLC", "Lp": "LP", "Etf": "ETF", "Adr": "ADR", "Reit": "REIT",
             "Com": "", "Cl A": "A类", "Cl B": "B类", "Cl C": "C类", "New": "",
             "Del": "", "Sponsored": "", "Class A": "A类", "Class B": "B类"}
    for k, v in fixes.items():
        name = re.sub(r"\b" + k + r"\b", v, name)
    name = re.sub(r"\s+", " ", name).strip(" -,")
    if put_call == "put":
        name += "（看跌期权）"
    elif put_call == "call":
        name += "（看涨期权）"
    return name


def zh_pretty(cusip6, raw, put_call):
    zh = zh_of(cusip6, raw)
    if not zh:
        return ""
    if put_call == "put":
        zh += "（看跌期权）"
    elif put_call == "call":
        zh += "（看涨期权）"
    return zh


def build_investor(cik, kw, zh, en, firm, firm_zh):
    name, filings = latest_13f_filings(cik)
    if name is None or not filings:
        print(f"  ✗ {en}: 无 13F 记录")
        return None
    if kw not in name.upper():
        print(f"  ✗ {en}: CIK 校验失败（EDGAR 名称 {name!r} 不含 {kw!r}），跳过")
        return None
    # 最新报告期太陈旧（>400 天，约 5 个季度未再申报）就不再展示
    try:
        age = (datetime.now(timezone.utc) - datetime.strptime(filings[0][0], "%Y-%m-%d")
               .replace(tzinfo=timezone.utc)).days
        if age > 400:
            print(f"  ✗ {en}: 最新 13F 报告期 {filings[0][0]} 已过期（{age} 天），跳过")
            return None
    except ValueError:
        pass
    cur = fetch_holdings(cik, filings[0][2])
    if not cur:
        print(f"  ✗ {en}: 持仓明细解析失败")
        return None
    prev = fetch_holdings(cik, filings[1][2]) if len(filings) > 1 else None

    total = sum(h["value"] for h in cur.values())
    if total <= 0:
        return None
    rows = sorted(cur.values(), key=lambda h: -h["value"])

    def chg_of(key, h):
        if not prev:
            return None, None
        p = prev.get(key)
        if not p:
            return "new", None
        if p["shares"] > 0 and h["shares"] > 0:
            delta = (h["shares"] - p["shares"]) / p["shares"] * 100
            if delta > 3:
                return "add", round(delta, 1)
            if delta < -3:
                return "trim", round(delta, 1)
        return "hold", None

    holdings = []
    for h in rows[:10]:
        key = (h["cusip6"], h["putCall"])
        chg, chg_pct = chg_of(key, h)
        holdings.append({
            "name": pretty_name(h["name"], h["putCall"]),
            "zh": zh_pretty(h["cusip6"], h["name"], h["putCall"]),
            "ticker": ticker_of(h["cusip6"]),
            "value": round(h["value"]),
            "pct": round(h["value"] / total * 100, 2),
            "chg": chg, "chgPct": chg_pct,
        })

    moves = []
    if prev:
        for key, h in cur.items():
            p = prev.get(key)
            if not p:
                moves.append({"type": "new", "name": pretty_name(h["name"], h["putCall"]),
                              "zh": zh_pretty(h["cusip6"], h["name"], h["putCall"]),
                              "ticker": ticker_of(h["cusip6"]),
                              "value": round(h["value"]), "delta": None})
            elif p["shares"] > 0 and h["shares"] > 0:
                d = (h["shares"] - p["shares"]) / p["shares"] * 100
                if abs(d) >= 3:
                    moves.append({"type": "add" if d > 0 else "trim",
                                  "name": pretty_name(h["name"], h["putCall"]),
                                  "zh": zh_pretty(h["cusip6"], h["name"], h["putCall"]),
                                  "ticker": ticker_of(h["cusip6"]),
                                  "value": round(abs(h["value"] - p["value"])), "delta": round(d, 1)})
        for key, p in prev.items():
            if key not in cur:
                moves.append({"type": "exit", "name": pretty_name(p["name"], p["putCall"]),
                              "zh": zh_pretty(p["cusip6"], p["name"], p["putCall"]),
                              "ticker": ticker_of(p["cusip6"]),
                              "value": round(p["value"]), "delta": None})
        moves.sort(key=lambda m: -m["value"])
        moves = moves[:8]

    photo = wiki_img(WIKI_TITLES.get(en, "")) or wiki_img(FIRM_WIKI.get(en, ""))
    inv = {
        "zh": zh, "en": en, "firm": firm, "firmZh": firm_zh, "cik": cik,
        "img": photo or favicon_data_uri(FIRM_DOMAIN.get(en, "")),
        "imgAlt": "",  # 图标已内联为 data URI，无需运行时二级源
        "imgLogo": not photo,
        "period": filings[0][0], "filed": filings[0][1],
        "value": round(total), "stocks": len(rows),
        "top10pct": round(sum(h["value"] for h in rows[:10]) / total * 100, 1),
        "holdings": holdings, "moves": moves,
        "_full": [{"cusip6": h["cusip6"], "putCall": h["putCall"], "name": h["name"],
                   "value": h["value"]} for h in rows],  # 用于跨投资者聚合，输出前删除
    }
    print(f"  ✓ {en}: {filings[0][0]} 持仓 {len(rows)} 只，市值 ${total/1e9:.1f}B，动向 {len(moves)} 条")
    return inv


# 手动录入快照：挪威主权基金（全球第一大）向 SEC 提交的 13F 明细体量极大、
# 打包方式特殊，实时抓取管线暂时解析不出（见 fetch_holdings 兜底仍失败）。
# 为不让「全球最大」缺席，这里按其最新一期（2025-12-31，SEC 13F-HR
# accession 0001374170-26-000012：1577 只持仓、组合市值约 $935B）手动录入
# 前十大美股持仓。前 5 大与礼来为 13F 披露值，其余为按公开数据的近似值，
# 卡片上以「手动快照」标注、且不随每周实时刷新（实时管线一旦可解析即自动接管）。
NORGES_SNAPSHOT = {
    "zh": "挪威主权基金", "en": "Norges Bank", "firm": "Norges Bank",
    "firmZh": "挪威主权基金", "cik": "0001374170",
    "period": "2025-12-31", "filed": "2026-02-10",
    "value": 935_000_000_000, "stocks": 1577, "top10pct": 28.9,
    "manual": True,
    "holdings": [
        {"name": "NVIDIA Corp",     "zh": "英伟达",   "ticker": "NVDA",  "value": 51_400_000_000, "pct": 5.50, "chg": None, "chgPct": None},
        {"name": "Microsoft Corp",  "zh": "微软",     "ticker": "MSFT",  "value": 50_500_000_000, "pct": 5.40, "chg": None, "chgPct": None},
        {"name": "Apple Inc",       "zh": "苹果",     "ticker": "AAPL",  "value": 38_900_000_000, "pct": 4.16, "chg": None, "chgPct": None},
        {"name": "Amazon.com Inc",  "zh": "亚马逊",   "ticker": "AMZN",  "value": 27_400_000_000, "pct": 2.93, "chg": None, "chgPct": None},
        {"name": "Meta Platforms",  "zh": "Meta平台", "ticker": "META",  "value": 23_200_000_000, "pct": 2.48, "chg": None, "chgPct": None},
        {"name": "Alphabet Inc A",  "zh": "谷歌-A",   "ticker": "GOOGL", "value": 20_000_000_000, "pct": 2.14, "chg": None, "chgPct": None},
        {"name": "Broadcom Inc",    "zh": "博通",     "ticker": "AVGO",  "value": 19_000_000_000, "pct": 2.03, "chg": None, "chgPct": None},
        {"name": "Alphabet Inc C",  "zh": "谷歌-C",   "ticker": "GOOG",  "value": 16_000_000_000, "pct": 1.71, "chg": None, "chgPct": None},
        {"name": "Eli Lilly & Co",  "zh": "礼来",     "ticker": "LLY",   "value": 13_000_000_000, "pct": 1.39, "chg": None, "chgPct": None},
        {"name": "JPMorgan Chase",  "zh": "摩根大通", "ticker": "JPM",   "value": 11_000_000_000, "pct": 1.18, "chg": None, "chgPct": None},
    ],
    "moves": [],
}
SWF_SNAPSHOTS = {"Norges Bank": NORGES_SNAPSHOT}


def build_swfs():
    """主权财富基金：复用 13F 抓取逻辑，附加国家/旗帜/官网图标。
    实时抓取失败且备有手动快照者（如挪威）回退到快照，保证「全球最大」不缺席。"""
    out = []
    for cik, kw, zh, en, country_zh, flag, domain in SWF_FUNDS:
        if time.time() > STOP:
            break
        try:
            inv = build_investor(cik, kw, zh, en, en, zh)
        except Exception as e:
            print(f"  ✗ SWF {en}: {str(e)[:100]}")
            inv = None
        if not inv:
            snap = SWF_SNAPSHOTS.get(en)
            if not snap:
                continue
            inv = json.loads(json.dumps(snap))  # 深拷贝，避免多次运行互相污染
            print(f"  ↺ {en}: 实时抓取失败，采用手动快照 {snap['period']}")
        inv.pop("_full", None)
        inv["countryZh"] = country_zh
        inv["flag"] = flag
        inv["img"] = favicon_data_uri(domain)
        inv["imgAlt"] = ""
        inv["imgLogo"] = True
        out.append(inv)
    out.sort(key=lambda x: -x["value"])
    print(f"  主权基金成功 {len(out)}/{len(SWF_FUNDS)} 个")
    return out


def cross_stats(investors):
    """大佬共识：最多人持有 Top10 + 最大单笔持仓 Top10（剔除期权）。"""
    owned = {}
    for inv in investors:
        seen = set()
        for h in inv["_full"]:
            if h["putCall"] or h["cusip6"] in seen:
                continue
            seen.add(h["cusip6"])
            o = owned.setdefault(h["cusip6"], {"name": h["name"], "gurus": 0, "value": 0.0})
            o["gurus"] += 1
            o["value"] += h["value"]
            if len(h["name"]) > len(o["name"]):
                o["name"] = h["name"]
    top_owned = sorted(owned.items(), key=lambda kv: (-kv[1]["gurus"], -kv[1]["value"]))[:10]
    top_owned = [{"name": pretty_name(v["name"], ""), "zh": zh_of(k, v["name"]),
                  "ticker": ticker_of(k), "gurus": v["gurus"], "value": round(v["value"])}
                 for k, v in top_owned]

    biggest = []
    for inv in investors:
        for h in inv["_full"][:5]:
            if h["putCall"]:
                continue
            biggest.append({"name": pretty_name(h["name"], ""), "zh": zh_of(h["cusip6"], h["name"]),
                            "ticker": ticker_of(h["cusip6"]),
                            "investor": inv["zh"], "value": round(h["value"])})
    biggest.sort(key=lambda b: -b["value"])
    return top_owned, biggest[:10]


# ---------------------------------------------------------------- AAII
def fetch_aaii():
    # 首选：官方历史数据 Excel
    r = get("https://www.aaii.com/files/surveys/sentiment.xls", WEB_HEADERS, timeout=40)
    if r and len(r.content) > 20000:
        try:
            import xlrd
            wb = xlrd.open_workbook(file_contents=r.content)
            sh = wb.sheet_by_index(0)
            rows = []
            for i in range(sh.nrows):
                try:
                    c = sh.row_values(i)
                    if not isinstance(c[0], float):
                        continue
                    b, n, be = float(c[1]), float(c[2]), float(c[3])
                    if not (0 <= b <= 1 and 0 <= n <= 1 and 0 <= be <= 1 and 0.97 < b + n + be < 1.03):
                        continue
                    date = xlrd.xldate.xldate_as_datetime(c[0], wb.datemode).strftime("%Y-%m-%d")
                    rows.append({"date": date, "bull": round(b * 100, 1),
                                 "neutral": round(n * 100, 1), "bear": round(be * 100, 1)})
                except Exception:
                    continue
            if len(rows) >= 10:
                avg = {
                    "bull": round(sum(x["bull"] for x in rows) / len(rows), 1),
                    "neutral": round(sum(x["neutral"] for x in rows) / len(rows), 1),
                    "bear": round(sum(x["bear"] for x in rows) / len(rows), 1),
                }
                yr = rows[-52:]
                hi = max(yr, key=lambda x: x["bull"])
                lo = min(yr, key=lambda x: x["bull"])
                weeks = rows[-12:][::-1]  # 最新在前
                print(f"  ✓ AAII(xls): 共 {len(rows)} 周，最新 {weeks[0]['date']} "
                      f"看涨 {weeks[0]['bull']}%")
                return {"asOf": weeks[0]["date"], "weeks": weeks, "avg": avg,
                        "spread": round(weeks[0]["bull"] - weeks[0]["bear"], 1),
                        "hi52": {"bull": hi["bull"], "date": hi["date"]},
                        "lo52": {"bull": lo["bull"], "date": lo["date"]}}
        except Exception as e:
            print(f"  AAII xls 解析失败：{str(e)[:100]}")

    # 回退：官网结果页正则
    r = get("https://www.aaii.com/sentimentsurvey/sent_results", WEB_HEADERS, timeout=40)
    if r:
        txt = re.sub(r"\s+", " ", r.text)
        pat = re.findall(
            r"(\w+ \d{1,2})\s*:?\s*</t[dh]>\s*<td[^>]*>\s*([\d.]+)%?\s*</td>\s*"
            r"<td[^>]*>\s*([\d.]+)%?\s*</td>\s*<td[^>]*>\s*([\d.]+)%?", txt)
        rows = []
        year = datetime.now(timezone.utc).year
        for dt, b, n, be in pat[:12]:
            try:
                d = datetime.strptime(f"{dt} {year}", "%B %d %Y")
                if d > datetime.now(timezone.utc):
                    d = d.replace(year=year - 1)
                rows.append({"date": d.strftime("%Y-%m-%d"), "bull": float(b),
                             "neutral": float(n), "bear": float(be)})
            except Exception:
                continue
        if rows:
            print(f"  ✓ AAII(html): {len(rows)} 周，最新 {rows[0]['date']}")
            return {"asOf": rows[0]["date"], "weeks": rows,
                    "avg": {"bull": 37.5, "neutral": 31.5, "bear": 31.0},  # 官方长期均值
                    "spread": round(rows[0]["bull"] - rows[0]["bear"], 1),
                    "hi52": None, "lo52": None}
    print("  ✗ AAII 两个来源均失败")
    return None


# ---------------------------------------------------------------- 主流程
def load_prev():
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def build():
    prev = load_prev() or {}

    print("== 头像 ==")
    try:
        wiki_imgs_batch(list(WIKI_TITLES.values()) + list(FIRM_WIKI.values()) +
                        list(POL_WIKI.values()))
    except Exception as e:
        print(f"  头像批量解析失败：{str(e)[:100]}")

    print("== SEC 13F ==")
    investors = []
    for cik, kw, zh, en, firm, firm_zh in INVESTORS:
        if time.time() > STOP:
            print("  超时止损，停止抓取剩余投资者")
            break
        try:
            inv = build_investor(cik, kw, zh, en, firm, firm_zh)
            if inv:
                investors.append(inv)
        except Exception as e:
            print(f"  ✗ {en}: {str(e)[:120]}")

    if len(investors) >= 10:
        top_owned, biggest = cross_stats(investors)
        for inv in investors:
            inv.pop("_full", None)
        investors.sort(key=lambda i: -i["value"])
    else:
        print(f"仅成功 {len(investors)} 位，保留上次投资者数据")
        investors = prev.get("investors") or []
        top_owned = prev.get("topOwned") or []
        biggest = prev.get("biggest") or []

    print("== 主权财富基金 ==")
    swfs = []
    try:
        swfs = build_swfs()
    except Exception as e:
        print(f"  主权基金抓取异常：{str(e)[:120]}")
    if len(swfs) < 2:
        print(f"  仅成功 {len(swfs)} 个，保留上次主权基金数据")
        swfs = prev.get("swfs") or swfs

    print("== 国会交易 ==")
    politicians = []
    try:
        politicians = build_politicians()
    except Exception as e:
        print(f"  国会交易抓取异常：{str(e)[:120]}")
    if len(politicians) < 4:
        print(f"  仅成功 {len(politicians)} 位，保留上次政治人物交易数据（仅刷新头像）")
        politicians = prev.get("politicians") or politicians
        # 交易数据源（FMP）暂不可用时，至少把头像刷新为维基照片（浏览器可直连）
        for p in politicians:
            img = wiki_img(POL_WIKI.get(p.get("bioguide", ""), ""))
            if img:
                p["img"] = img

    print("== AAII ==")
    aaii = fetch_aaii() or prev.get("aaii")

    if not investors and not aaii and not politicians:
        print("各节均无数据，不写文件。")
        return

    out = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "SEC EDGAR 13F-HR · AAII Investor Sentiment Survey",
        "investors": investors,
        "topOwned": top_owned,
        "biggest": biggest,
        "swfs": swfs,
        "swfTop20": SWF_TOP20,
        "politicians": politicians,
        "aaii": aaii,
        "note": ("13F 为机构按季度向 SEC 披露的美股多头持仓，最长滞后 45 天，且不含"
                 "空头、债券与海外持仓；主权财富基金仅收录向 SEC 提交 13F 者（挪威、"
                 "新加坡、加拿大等），ADIA、沙特 PIF、中投等不申报或经外部管理人持有，"
                 "无公开美股持仓明细；国会议员交易来自 STOCK Act 披露（金额为区间估算，"
                 "披露最长滞后 45 天）；AAII 情绪调查每周四发布。公司中文名为常用译名，"
                 "以英文原名为准。人物头像来自维基百科与美国国会官方照片库。"
                 "仅供参考，不构成投资建议。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"写入 {OUT_PATH}：投资者 {len(investors)} 位，AAII {'有' if aaii else '无'}")


if __name__ == "__main__":
    build()
