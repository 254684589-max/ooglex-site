#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全球专业与就业前景榜取数脚本。

产出 apps/major-rankings/data.json，用一份「专业」数据集支撑四张榜单（前端按不同字段重排）：
  1) 专业薪资 Top 100        —— 按职业中期年薪（mid-career）排序
  2) 专业就业率 Top 100      —— 按毕业生就业率排序
  3) 毕业起薪 Top 100        —— 按应届起薪（early-career）排序
  4) AI 时代未来 10 年最有前景专业 —— 按本脚本计算的「前景综合分」排序

数据为**年度权威数据整理**（非每日实时；薪资/就业为年度调查值），字段口径：
  - start / mid：应届起薪、职业中期年薪（美元/年，以美国市场为基准，来源 PayScale 薪资报告、
    NACE 起薪调查、美国 BLS 职业工资）。
  - emp：毕业生就业率（%，综合各国毕业生去向调查，如 US NACE First-Destination、英国 HESA
    Graduate Outcomes、QS 毕业生就业力）。
  - growth：未来 10 年该领域岗位就业增长预测（%，来源 BLS 2023–2033 职业展望）。
  - aiRisk：受 AI/自动化替代的暴露度（0–100，数值越大越易被替代）。
  - aiBoost：AI 浪潮对该专业需求的放大度（0–100，数值越大越「乘 AI 而上」）。
  参考 世界经济论坛《Future of Jobs 2025》、OECD 自动化风险研究等公开报告整理，个别数值为区间近似。

「前景综合分」= 100 ×（0.40×增长归一 + 0.35×AI 放大度 + 0.25×(1−AI 替代度)）。
"""
import json
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "apps", "major-rankings", "data.json")
VINTAGE = "2024–2025"

# 学科大类 → (中文标签, 颜色, emoji)
CATS = {
    "cs":     ("计算机·AI", "#6c8cff", "💻"),
    "eng":    ("工程", "#39d3e0", "⚙️"),
    "health": ("医学·健康", "#5fd07a", "⚕️"),
    "sci":    ("自然科学", "#34e0c4", "🔬"),
    "biz":    ("商科·经济", "#f3c969", "📈"),
    "soc":    ("社科·人文", "#b48cff", "🌐"),
    "edu":    ("教育·法律", "#e8833a", "⚖️"),
    "art":    ("艺术·设计", "#f472b6", "🎨"),
}

# (英文名, 中文名, 大类, 起薪 start, 中期薪资 mid, 就业率 emp, 10年增长 growth, AI替代 aiRisk, AI放大 aiBoost)
MAJORS = [
    # 计算机 · AI
    ("Artificial Intelligence & Machine Learning", "人工智能与机器学习", "cs", 98000, 165000, 93, 40, 12, 100),
    ("Data Science", "数据科学", "cs", 88000, 145000, 92, 35, 15, 98),
    ("Computer Science", "计算机科学", "cs", 82000, 152000, 92, 22, 20, 95),
    ("Software Engineering", "软件工程", "cs", 84000, 150000, 92, 25, 22, 92),
    ("Cybersecurity", "网络安全", "cs", 80000, 135000, 93, 33, 18, 88),
    ("Robotics", "机器人工程", "cs", 86000, 142000, 90, 30, 22, 95),
    ("Cloud Computing", "云计算", "cs", 85000, 140000, 91, 26, 20, 88),
    ("Business Analytics", "商业分析", "cs", 74000, 120000, 90, 25, 25, 85),
    ("Information Systems (MIS)", "信息管理系统", "cs", 72000, 122000, 90, 15, 30, 80),
    ("Human-Computer Interaction", "人机交互", "cs", 78000, 125000, 88, 18, 30, 78),
    # 工程
    ("Petroleum Engineering", "石油工程", "eng", 94000, 187000, 88, 2, 25, 20),
    ("Computer Engineering", "计算机工程", "eng", 82000, 145000, 90, 15, 22, 85),
    ("Electrical Engineering", "电气工程", "eng", 78000, 140000, 90, 9, 28, 72),
    ("Chemical Engineering", "化学工程", "eng", 78000, 138000, 88, 8, 25, 45),
    ("Aerospace Engineering", "航空航天工程", "eng", 76000, 135000, 87, 6, 25, 58),
    ("Nuclear Engineering", "核工程", "eng", 80000, 135000, 85, 5, 25, 45),
    ("Mechatronics", "机电一体化", "eng", 76000, 128000, 88, 16, 25, 82),
    ("Mechanical Engineering", "机械工程", "eng", 72000, 122000, 89, 10, 32, 58),
    ("Renewable Energy Engineering", "可再生能源工程", "eng", 74000, 122000, 88, 24, 20, 80),
    ("Biomedical Engineering", "生物医学工程", "eng", 70000, 120000, 85, 7, 22, 78),
    ("Industrial Engineering", "工业工程", "eng", 72000, 120000, 88, 12, 32, 60),
    ("Materials Science & Engineering", "材料科学与工程", "eng", 70000, 118000, 85, 8, 25, 60),
    ("Civil Engineering", "土木工程", "eng", 68000, 110000, 88, 8, 25, 40),
    ("Environmental Engineering", "环境工程", "eng", 65000, 105000, 84, 8, 25, 55),
    ("Aviation & Piloting", "航空飞行", "eng", 62000, 130000, 86, 6, 20, 30),
    ("Construction Management", "建筑管理", "eng", 65000, 100000, 86, 9, 25, 40),
    # 医学 · 健康
    ("Medicine (pre-med)", "医学", "health", 70000, 220000, 95, 4, 10, 55),
    ("Dentistry (pre-dental)", "口腔医学", "health", 95000, 160000, 93, 5, 15, 30),
    ("Pharmacy (PharmD)", "药学", "health", 98000, 132000, 92, 3, 20, 45),
    ("Physician Assistant Studies", "医师助理", "health", 105000, 120000, 95, 27, 10, 45),
    ("Veterinary Medicine", "兽医学", "health", 70000, 110000, 90, 20, 12, 40),
    ("Physical Therapy (DPT)", "物理治疗", "health", 80000, 98000, 93, 15, 8, 35),
    ("Nursing (BSN)", "护理学", "health", 78000, 95000, 96, 6, 8, 40),
    ("Radiologic & Imaging Sciences", "医学影像", "health", 70000, 92000, 90, 6, 25, 60),
    ("Occupational Therapy", "职业治疗", "health", 72000, 90000, 92, 12, 10, 35),
    ("Speech-Language Pathology", "言语病理", "health", 68000, 88000, 92, 18, 10, 30),
    ("Public Health", "公共卫生", "health", 52000, 82000, 85, 7, 20, 55),
    ("Nutrition & Dietetics", "营养与膳食", "health", 50000, 72000, 86, 7, 20, 40),
    # 自然科学
    ("Actuarial Science", "精算学", "sci", 72000, 132000, 90, 22, 25, 55),
    ("Physics", "物理学", "sci", 66000, 122000, 82, 7, 25, 72),
    ("Statistics", "统计学", "sci", 70000, 120000, 88, 30, 20, 85),
    ("Mathematics", "数学", "sci", 66000, 116000, 85, 28, 20, 82),
    ("Biotechnology & Bioinformatics", "生物技术与生物信息", "sci", 66000, 112000, 84, 17, 20, 82),
    ("Genetics & Genomics", "遗传与基因组学", "sci", 64000, 108000, 82, 15, 18, 80),
    ("Astronomy & Astrophysics", "天文与天体物理", "sci", 60000, 105000, 78, 7, 20, 60),
    ("Earth Science & Geology", "地球科学与地质", "sci", 62000, 102000, 82, 5, 25, 45),
    ("Neuroscience", "神经科学", "sci", 56000, 96000, 80, 9, 20, 72),
    ("Chemistry", "化学", "sci", 56000, 95000, 82, 6, 30, 50),
    ("Food Science", "食品科学", "sci", 55000, 88000, 85, 9, 30, 45),
    ("Environmental Science", "环境科学", "sci", 52000, 85000, 82, 8, 25, 55),
    ("Biology", "生物学", "sci", 50000, 84000, 80, 5, 25, 55),
    ("Agricultural Science", "农业科学", "sci", 50000, 80000, 84, 6, 30, 45),
    # 商科 · 经济
    ("Quantitative Finance", "金融工程 / 量化金融", "biz", 90000, 160000, 90, 12, 25, 80),
    ("Economics", "经济学", "biz", 68000, 130000, 88, 6, 32, 60),
    ("Finance", "金融学", "biz", 70000, 125000, 88, 8, 35, 55),
    ("Entrepreneurship", "创业学", "biz", 55000, 100000, 80, 6, 25, 60),
    ("Real Estate", "房地产", "biz", 58000, 100000, 82, 5, 35, 35),
    ("Management", "管理学", "biz", 58000, 98000, 85, 6, 35, 45),
    ("Supply Chain Management", "供应链管理", "biz", 64000, 98000, 89, 18, 30, 62),
    ("Accounting", "会计学", "biz", 60000, 95000, 90, 4, 55, 32),
    ("International Business", "国际商务", "biz", 56000, 95000, 84, 7, 35, 45),
    ("Marketing", "市场营销", "biz", 56000, 92000, 85, 8, 45, 60),
    ("Human Resources", "人力资源", "biz", 54000, 82000, 86, 5, 45, 40),
    ("Hospitality Management", "酒店管理", "biz", 48000, 78000, 84, 8, 35, 30),
    # 社科 · 人文
    ("Political Science", "政治学", "soc", 52000, 95000, 84, 6, 35, 45),
    ("International Relations", "国际关系", "soc", 52000, 92000, 82, 5, 30, 45),
    ("Philosophy", "哲学", "soc", 48000, 86000, 76, 4, 35, 45),
    ("Communications", "传播学", "soc", 50000, 86000, 83, 8, 50, 55),
    ("Linguistics", "语言学", "soc", 50000, 82000, 78, 5, 40, 60),
    ("Geography", "地理学", "soc", 50000, 82000, 80, 5, 30, 50),
    ("History", "历史学", "soc", 48000, 80000, 76, 4, 40, 40),
    ("Psychology", "心理学", "soc", 46000, 80000, 80, 6, 30, 50),
    ("English & Literature", "英语与文学", "soc", 46000, 76000, 76, 3, 45, 45),
    ("Journalism", "新闻学", "soc", 45000, 75000, 78, -3, 60, 50),
    ("Sociology", "社会学", "soc", 45000, 72000, 78, 5, 35, 40),
    ("Anthropology", "人类学", "soc", 45000, 72000, 74, 4, 35, 35),
    ("Urban Planning", "城市规划", "soc", 56000, 88000, 82, 7, 25, 50),
    # 教育 · 法律
    ("Law (pre-law / legal studies)", "法学", "edu", 60000, 120000, 86, 5, 35, 50),
    ("Public Administration", "公共管理", "edu", 50000, 80000, 84, 5, 35, 40),
    ("Criminal Justice", "刑事司法", "edu", 48000, 72000, 84, 3, 35, 35),
    ("Library & Information Science", "图书情报", "edu", 50000, 72000, 82, 3, 40, 45),
    ("Education & Teaching", "教育与师范", "edu", 45000, 62000, 90, 4, 25, 35),
    ("Social Work", "社会工作", "edu", 48000, 62000, 88, 7, 15, 30),
    # 艺术 · 设计
    ("Architecture", "建筑学", "art", 56000, 95000, 80, 5, 30, 45),
    ("Game Design", "游戏设计", "art", 58000, 95000, 80, 10, 30, 65),
    ("Industrial & Product Design", "工业设计", "art", 56000, 90000, 80, 6, 35, 55),
    ("Film & Media Production", "影视制作", "art", 46000, 80000, 74, 5, 45, 55),
    ("Graphic Design", "平面设计", "art", 48000, 76000, 78, 3, 55, 45),
    ("Fashion Design", "服装设计", "art", 45000, 74000, 74, 3, 45, 35),
    ("Music & Performing Arts", "音乐与表演", "art", 42000, 70000, 72, 3, 40, 35),
    ("Fine Arts", "美术", "art", 42000, 70000, 70, 2, 45, 40),
]

SOURCES = [
    {"name": "PayScale College Salary Report", "url": "https://www.payscale.com/college-salary-report/",
     "desc": "按专业统计的应届起薪与职业中期薪资（美国）"},
    {"name": "NACE 起薪调查 & 毕业生去向", "url": "https://www.naceweb.org/",
     "desc": "美国全国高校与雇主协会的应届起薪 / First-Destination 就业率"},
    {"name": "U.S. BLS 职业展望手册", "url": "https://www.bls.gov/ooh/",
     "desc": "美国劳工统计局 2023–2033 各职业工资与十年就业增长预测"},
    {"name": "WEF《未来就业报告 2025》", "url": "https://www.weforum.org/publications/the-future-of-jobs-report-2025/",
     "desc": "世界经济论坛：AI 时代增长最快 / 萎缩最快的岗位与技能"},
    {"name": "英国 HESA Graduate Outcomes", "url": "https://www.hesa.ac.uk/data-and-analysis/graduates",
     "desc": "英国官方毕业生去向与就业率调查"},
    {"name": "QS 毕业生就业力排名", "url": "https://www.topuniversities.com/university-rankings/employability-rankings/",
     "desc": "以雇主声誉与毕业生就业成果为核心的国际参考"},
]


def build():
    gs = [m[6] for m in MAJORS]
    gmin, gmax = min(gs), max(gs)
    span = (gmax - gmin) or 1

    majors = []
    for en, cn, cat, start, mid, emp, growth, risk, boost in MAJORS:
        gN = (growth - gmin) / span
        future = round(100 * (0.40 * gN + 0.35 * boost / 100 + 0.25 * (1 - risk / 100)), 1)
        majors.append({
            "en": en, "cn": cn, "cat": cat,
            "start": start, "mid": mid, "emp": emp,
            "growth": growth, "aiRisk": risk, "aiBoost": boost,
            "future": future,
        })

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out = {
        "updatedAt": now, "asOf": now[:10], "vintage": VINTAGE,
        "count": len(majors),
        "note": "本榜为年度权威数据整理（非每日实时）：薪资来自 PayScale 薪资报告与 NACE 起薪调查、"
                "就业率综合各国毕业生去向调查、十年增长取自美国 BLS 职业展望、AI 前景参考 WEF《未来就业报告 2025》。"
                "薪资以美元/年、美国市场为基准，仅供参考，不构成升学或就业建议。",
        "cats": {k: {"label": v[0], "color": v[1], "emoji": v[2]} for k, v in CATS.items()},
        "sources": SOURCES,
        "majors": majors,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"完成：写入 {len(majors)} 个专业 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(build())
