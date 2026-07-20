#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全球大学排名取数脚本。

融合四大权威世界大学排名，按「多榜平均位次」排出全球前 300，写入
apps/university-rankings/data.json：
  1) QS World University Rankings       —— topuniversities.com 榜单页 AJAX 端点（JSON）
  2) THE World University Rankings      —— timeshighereducation.com 榜单页内嵌的整表 JSON 文件
  3) ARWU（软科 / 上海交大世界大学学术排名）—— shanghairanking.com 榜单 API（JSON）
  4) U.S. News Best Global Universities —— 官方 API（分页 JSON）

现状说明：QS / THE / ARWU / U.S. News 四大官网均封锁自动抓取（实测 403 / 超时 / JS 渲染），
因此本站该榜采用内置 SEED（四榜近一期公开位次的年度整理，标 seed=true）作为发布数据，
不进入每日调度。下方 fetch_* 为 best-effort：若日后某源接口对机房可达并解析成功，脚本会自动改用实时数据。

容错约定（与全站取数脚本一致）：
  - 四源相互独立，单源失败不影响其余；
  - 有效源过少（< 2）或全部失败 → 保留上次 data.json（无历史则用内置 SEED），绝不用空/脏数据覆盖。

排序口径：每所大学取其在各榜的位次，至少命中 2 个榜才计入「综合」；综合分 = 各榜位次的平均
（ARTU 式聚合排名，位次越小越靠前）。仅命中 1 个榜的长尾学校排在其后。取前 300。
"""
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "apps", "university-rankings", "data.json")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
TIMEOUT = 30
LIMIT = 300

# ---------------------------------------------------------------- 基础请求

def http_get(url, headers=None, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=dict({"User-Agent": UA, "Accept": "*/*"}, **(headers or {})))
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            print(f"  ! GET {url} 失败（{i + 1}/{tries}）：{e}")
            time.sleep(2 * (i + 1))
    return None

# ---------------------------------------------------------------- 名称归一 / 国别

# 合并键：小写、去掉常见前后缀与标点，把同一所学校的不同写法归到一起。
_STOP = re.compile(r"\b(the|university|univ|of|at|and|college|institute|for|school)\b")
def norm_name(raw):
    s = str(raw or "").lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[（(].*?[)）]", " ", s)
    s = re.sub(r"[^a-z0-9一-鿿]+", " ", s)
    s = _STOP.sub(" ", s)
    return re.sub(r"\s+", "", s).strip()

# 别名 → 规范英文名（把各源里同校不同写法对齐到 SEED 里的规范名）
ALIAS = {
    "massachusettstechnology": "Massachusetts Institute of Technology",
    "californiatechnology": "California Institute of Technology",
    "swissfederaltechnologyzurich": "ETH Zurich",
    "ethzurichswissfederaltechnology": "ETH Zurich",
    "imperiallondon": "Imperial College London",
    "londonucl": "University College London",
    "ucl": "University College London",
    "nationalsingapore": "National University of Singapore",
    "nus": "National University of Singapore",
    "nanyangtechnological": "Nanyang Technological University",
    "ntu": "Nanyang Technological University",
    "berkeleycalifornia": "University of California, Berkeley",
    "californiaberkeley": "University of California, Berkeley",
    "californialosangeles": "University of California, Los Angeles",
    "ucla": "University of California, Los Angeles",
    "hongkong": "University of Hong Kong",
    "hku": "University of Hong Kong",
    "hongkongscienceandtechnology": "Hong Kong University of Science and Technology",
    "hkust": "Hong Kong University of Science and Technology",
    "chinesehongkong": "Chinese University of Hong Kong",
    "tokyo": "University of Tokyo",
    "peking": "Peking University",
    "tsinghua": "Tsinghua University",
    "fudan": "Fudan University",
    "shanghaijiaotong": "Shanghai Jiao Tong University",
    "zhejiang": "Zhejiang University",
    "sciencetechnologychina": "University of Science and Technology of China",
    "epflecolepolytechniquefederalelausanne": "EPFL",
    "ecolepolytechniquefederalelausanne": "EPFL",
    "epfl": "EPFL",
    "mcgill": "McGill University",
    "torontoo": "University of Toronto",
    "britishcolumbia": "University of British Columbia",
    "psl": "PSL University",
    "parissciencesetlettres": "PSL University",
    "munichtechnical": "Technical University of Munich",
    "technicalmunich": "Technical University of Munich",
    "seoulnational": "Seoul National University",
    "snu": "Seoul National University",
}
def ukey(raw):
    """合并键：先归一，再走别名表把同校不同写法对齐到规范名的归一键。"""
    k = norm_name(raw)
    alias = ALIAS.get(k)
    return norm_name(alias) if alias else k

# 国别 → (中文, 旗帜)。SEED 覆盖主要国家；实时源用其自带 region/country 兜底。
COUNTRY = {
    "United States": ("美国", "🇺🇸"), "United Kingdom": ("英国", "🇬🇧"), "China": ("中国", "🇨🇳"),
    "Hong Kong SAR": ("中国香港", "🇭🇰"), "Hong Kong": ("中国香港", "🇭🇰"), "Taiwan": ("中国台湾", "🇹🇼"),
    "Singapore": ("新加坡", "🇸🇬"), "Japan": ("日本", "🇯🇵"), "South Korea": ("韩国", "🇰🇷"),
    "Switzerland": ("瑞士", "🇨🇭"), "Germany": ("德国", "🇩🇪"), "France": ("法国", "🇫🇷"),
    "Netherlands": ("荷兰", "🇳🇱"), "Canada": ("加拿大", "🇨🇦"), "Australia": ("澳大利亚", "🇦🇺"),
    "Sweden": ("瑞典", "🇸🇪"), "Belgium": ("比利时", "🇧🇪"), "Denmark": ("丹麦", "🇩🇰"),
    "Italy": ("意大利", "🇮🇹"), "Spain": ("西班牙", "🇪🇸"), "Finland": ("芬兰", "🇫🇮"),
    "Norway": ("挪威", "🇳🇴"), "Austria": ("奥地利", "🇦🇹"), "Ireland": ("爱尔兰", "🇮🇪"),
    "New Zealand": ("新西兰", "🇳🇿"), "Malaysia": ("马来西亚", "🇲🇾"), "Saudi Arabia": ("沙特", "🇸🇦"),
    "India": ("印度", "🇮🇳"), "Brazil": ("巴西", "🇧🇷"), "Russia": ("俄罗斯", "🇷🇺"),
    "Israel": ("以色列", "🇮🇱"), "Argentina": ("阿根廷", "🇦🇷"), "Mexico": ("墨西哥", "🇲🇽"),
    "South Africa": ("南非", "🇿🇦"), "Chile": ("智利", "🇨🇱"), "Qatar": ("卡塔尔", "🇶🇦"),
    "United Arab Emirates": ("阿联酋", "🇦🇪"), "Thailand": ("泰国", "🇹🇭"), "Portugal": ("葡萄牙", "🇵🇹"),
    "Czech Republic": ("捷克", "🇨🇿"), "Poland": ("波兰", "🇵🇱"), "Greece": ("希腊", "🇬🇷"),
    "Luxembourg": ("卢森堡", "🇱🇺"), "Estonia": ("爱沙尼亚", "🇪🇪"), "Turkey": ("土耳其", "🇹🇷"),
    "Iran": ("伊朗", "🇮🇷"), "Indonesia": ("印度尼西亚", "🇮🇩"),
}

# 规范英文名 → 官网域名（用于自托管 logo：fetch_logos.py 据此抓 favicon 存 logos/<slug>.png）
UNIV_DOMAIN = {
    "Massachusetts Institute of Technology": "mit.edu", "University of Oxford": "ox.ac.uk",
    "Stanford University": "stanford.edu", "University of Cambridge": "cam.ac.uk",
    "Harvard University": "harvard.edu", "California Institute of Technology": "caltech.edu",
    "Imperial College London": "imperial.ac.uk", "ETH Zurich": "ethz.ch",
    "University College London": "ucl.ac.uk", "Princeton University": "princeton.edu",
    "University of California, Berkeley": "berkeley.edu", "Yale University": "yale.edu",
    "University of Chicago": "uchicago.edu", "University of Pennsylvania": "upenn.edu",
    "National University of Singapore": "nus.edu.sg", "Cornell University": "cornell.edu",
    "Columbia University": "columbia.edu", "Johns Hopkins University": "jhu.edu",
    "University of California, Los Angeles": "ucla.edu", "University of Toronto": "utoronto.ca",
    "Tsinghua University": "tsinghua.edu.cn", "Peking University": "pku.edu.cn",
    "University of Michigan": "umich.edu", "Nanyang Technological University": "ntu.edu.sg",
    "University of Melbourne": "unimelb.edu.au", "EPFL": "epfl.ch", "University of Tokyo": "u-tokyo.ac.jp",
    "University of Hong Kong": "hku.hk", "New York University": "nyu.edu",
    "Northwestern University": "northwestern.edu", "University of Edinburgh": "ed.ac.uk",
    "King's College London": "kcl.ac.uk", "Duke University": "duke.edu",
    "University of California, San Diego": "ucsd.edu", "Carnegie Mellon University": "cmu.edu",
    "Fudan University": "fudan.edu.cn", "Shanghai Jiao Tong University": "sjtu.edu.cn",
    "Zhejiang University": "zju.edu.cn", "Australian National University": "anu.edu.au",
    "University of British Columbia": "ubc.ca", "McGill University": "mcgill.ca",
    "Kyoto University": "kyoto-u.ac.jp", "Seoul National University": "snu.ac.kr",
    "Technical University of Munich": "tum.de", "University of Manchester": "manchester.ac.uk",
    "PSL University": "psl.eu", "University of Washington": "washington.edu",
    "Chinese University of Hong Kong": "cuhk.edu.hk", "Hong Kong University of Science and Technology": "hkust.edu.hk",
    "University of Sydney": "sydney.edu.au", "University of New South Wales": "unsw.edu.au",
    "Monash University": "monash.edu", "University of Queensland": "uq.edu.au",
    "University of Amsterdam": "uva.nl", "Delft University of Technology": "tudelft.nl",
    "Ludwig Maximilian University of Munich": "lmu.de", "Heidelberg University": "uni-heidelberg.de",
    "KU Leuven": "kuleuven.be", "University of Copenhagen": "ku.dk", "Karolinska Institute": "ki.se",
    "University of Wisconsin-Madison": "wisc.edu", "University of Texas at Austin": "utexas.edu",
    "Georgia Institute of Technology": "gatech.edu", "University of Illinois Urbana-Champaign": "illinois.edu",
    "Brown University": "brown.edu", "University of Bristol": "bristol.ac.uk",
    "École Polytechnique": "polytechnique.edu", "Sorbonne University": "sorbonne-universite.fr",
    "Utrecht University": "uu.nl", "Lund University": "lu.se", "University of Zurich": "uzh.ch",
    "University of Warwick": "warwick.ac.uk", "London School of Economics and Political Science": "lse.ac.uk",
    "University of Glasgow": "gla.ac.uk", "Michigan State University": "msu.edu",
    "University of Southern California": "usc.edu", "University of North Carolina at Chapel Hill": "unc.edu",
    "University of California, Davis": "ucdavis.edu", "Purdue University": "purdue.edu",
    "University of Minnesota": "umn.edu", "Nanjing University": "nju.edu.cn",
    "University of Science and Technology of China": "ustc.edu.cn", "Wuhan University": "whu.edu.cn",
    "KAIST": "kaist.ac.kr", "Yonsei University": "yonsei.ac.kr", "Korea University": "korea.ac.kr",
    "Osaka University": "osaka-u.ac.jp", "Tohoku University": "tohoku.ac.jp",
    "Tokyo Institute of Technology": "titech.ac.jp", "National Taiwan University": "ntu.edu.tw",
    "University of Malaya": "um.edu.my", "Trinity College Dublin": "tcd.ie",
    "University of Auckland": "auckland.ac.nz", "Ghent University": "ugent.be",
    "University of Helsinki": "helsinki.fi", "Uppsala University": "uu.se",
    "KTH Royal Institute of Technology": "kth.se", "Leiden University": "universiteitleiden.nl",
    "Erasmus University Rotterdam": "eur.nl", "University of Geneva": "unige.ch",
    "Aarhus University": "au.dk", "University of Vienna": "univie.ac.at",
    "Humboldt University of Berlin": "hu-berlin.de", "RWTH Aachen University": "rwth-aachen.de",
    "University of Freiburg": "uni-freiburg.de", "University of Tübingen": "uni-tuebingen.de",
    "University of Bonn": "uni-bonn.de", "Charité - Berlin": "charite.de",
    "University of Barcelona": "ub.edu", "Autonomous University of Barcelona": "uab.cat",
    "Sapienza University of Rome": "uniroma1.it", "University of Bologna": "unibo.it",
    "Politecnico di Milano": "polimi.it", "University of Padua": "unipd.it",
    "Pohang University of Science and Technology": "postech.ac.kr", "Sungkyunkwan University": "skku.edu",
    "Indian Institute of Science": "iisc.ac.in", "Indian Institute of Technology Bombay": "iitb.ac.in",
    "Indian Institute of Technology Delhi": "iitd.ac.in", "King Abdulaziz University": "kau.edu.sa",
    "University of Sao Paulo": "usp.br", "Boston University": "bu.edu",
    "Ohio State University": "osu.edu", "University of Maryland, College Park": "umd.edu",
    "Pennsylvania State University": "psu.edu", "University of Pittsburgh": "pitt.edu",
    "University of California, Irvine": "uci.edu", "University of California, Santa Barbara": "ucsb.edu",
    "Rice University": "rice.edu", "Emory University": "emory.edu", "Vanderbilt University": "vanderbilt.edu",
    "University of Notre Dame": "nd.edu", "Washington University in St. Louis": "wustl.edu",
    "Rutgers University": "rutgers.edu", "University of Colorado Boulder": "colorado.edu",
    "Arizona State University": "asu.edu", "University of Florida": "ufl.edu",
    "Texas A&M University": "tamu.edu", "University of Virginia": "virginia.edu",
    "Dartmouth College": "dartmouth.edu", "University of Sheffield": "sheffield.ac.uk",
    "University of Nottingham": "nottingham.ac.uk", "University of Birmingham": "birmingham.ac.uk",
    "University of Leeds": "leeds.ac.uk", "University of Southampton": "southampton.ac.uk",
    "Durham University": "durham.ac.uk", "University of St Andrews": "st-andrews.ac.uk",
    "Queen Mary University of London": "qmul.ac.uk", "University of York": "york.ac.uk",
    "Lancaster University": "lancaster.ac.uk", "Cardiff University": "cardiff.ac.uk",
    "University of Liverpool": "liverpool.ac.uk", "University of Aberdeen": "abdn.ac.uk",
    "Newcastle University": "ncl.ac.uk", "University of Exeter": "exeter.ac.uk",
    "University of Bath": "bath.ac.uk", "Sun Yat-sen University": "sysu.edu.cn",
    "Huazhong University of Science and Technology": "hust.edu.cn", "Harbin Institute of Technology": "hit.edu.cn",
    "Xi'an Jiaotong University": "xjtu.edu.cn", "Tongji University": "tongji.edu.cn",
    "Beihang University": "buaa.edu.cn", "Wuhan University of Technology": "whut.edu.cn",
    "Southern University of Science and Technology": "sustech.edu.cn", "Beijing Normal University": "bnu.edu.cn",
    "Nankai University": "nankai.edu.cn", "Shandong University": "sdu.edu.cn",
    "Sichuan University": "scu.edu.cn", "Central South University": "csu.edu.cn",
    "City University of Hong Kong": "cityu.edu.hk", "Hong Kong Polytechnic University": "polyu.edu.hk",
    "Nagoya University": "nagoya-u.ac.jp", "Kyushu University": "kyushu-u.ac.jp",
    "Hokkaido University": "hokudai.ac.jp", "University of Basel": "unibas.ch",
    "University of Bern": "unibe.ch", "Wageningen University & Research": "wur.nl",
    "University of Groningen": "rug.nl", "Radboud University": "ru.nl",
    "Eindhoven University of Technology": "tue.nl", "University of Oslo": "uio.no",
    "University of Gothenburg": "gu.se", "Stockholm University": "su.se", "Aalto University": "aalto.fi",
    "Technical University of Denmark": "dtu.dk", "University of Cape Town": "uct.ac.za",
    "University of Buenos Aires": "uba.ar", "National Autonomous University of Mexico": "unam.mx",
    "Lomonosov Moscow State University": "msu.ru", "Tel Aviv University": "tau.ac.il",
    "Hebrew University of Jerusalem": "huji.ac.il", "Technion - Israel Institute of Technology": "technion.ac.il",
    "Chalmers University of Technology": "chalmers.se", "Norwegian University of Science and Technology": "ntnu.edu",
    "University of Adelaide": "adelaide.edu.au", "University of Western Australia": "uwa.edu.au",
    "University of Technology Sydney": "uts.edu.au", "Macquarie University": "mq.edu.au",
    "University of Waterloo": "uwaterloo.ca", "University of Alberta": "ualberta.ca",
    "McMaster University": "mcmaster.ca", "Université de Montréal": "umontreal.ca",
    "Western University": "uwo.ca", "University of Ottawa": "uottawa.ca", "University of Calgary": "ucalgary.ca",
    "Aristotle University of Thessaloniki": "auth.gr", "Charles University": "cuni.cz",
    "University of Warsaw": "uw.edu.pl", "University of Lisbon": "ulisboa.pt",
}


def logo_slug(domain):
    return re.sub(r"[^a-z0-9]+", "-", str(domain).lower()).strip("-")

# ---------------------------------------------------------------- 上线种子（权威榜单公开位次整理）
# 字段：规范英文名, 中文名, 国家, QS, THE, ARWU, USNews（位次，未上榜/不确定填 None）。
# 说明：这是「上线快照（近似值）」，用于首次自动更新前展示；数值取自四大榜单近一期公开位次的整理，
#      个别名次可能有小幅出入。工作流首次在 GitHub Actions 抓取成功后，本文件将被四榜实时数据覆盖。
SEED = [
    ("Massachusetts Institute of Technology", "麻省理工学院", "United States", 1, 2, 4, 2),
    ("University of Oxford", "牛津大学", "United Kingdom", 4, 1, 7, 5),
    ("Stanford University", "斯坦福大学", "United States", 6, 4, 2, 3),
    ("University of Cambridge", "剑桥大学", "United Kingdom", 6, 5, 4, 8),
    ("Harvard University", "哈佛大学", "United States", 5, 3, 1, 1),
    ("California Institute of Technology", "加州理工学院", "United States", 10, 7, 8, 9),
    ("Imperial College London", "帝国理工学院", "United Kingdom", 2, 9, 27, 13),
    ("ETH Zurich", "苏黎世联邦理工学院", "Switzerland", 7, 11, 20, 25),
    ("University College London", "伦敦大学学院", "United Kingdom", 9, 22, 17, 15),
    ("Princeton University", "普林斯顿大学", "United States", 22, 6, 6, 16),
    ("University of California, Berkeley", "加州大学伯克利分校", "United States", 12, 8, 5, 4),
    ("Yale University", "耶鲁大学", "United States", 23, 10, 11, 11),
    ("University of Chicago", "芝加哥大学", "United States", 21, 14, 10, 22),
    ("University of Pennsylvania", "宾夕法尼亚大学", "United States", 11, 15, 16, 14),
    ("National University of Singapore", "新加坡国立大学", "Singapore", 8, 17, 71, 26),
    ("Cornell University", "康奈尔大学", "United States", 16, 20, 12, 19),
    ("Columbia University", "哥伦比亚大学", "United States", 34, 19, 9, 7),
    ("Johns Hopkins University", "约翰斯·霍普金斯大学", "United States", 28, 16, 15, 10),
    ("University of California, Los Angeles", "加州大学洛杉矶分校", "United States", 42, 18, 13, 9),
    ("University of Toronto", "多伦多大学", "Canada", 25, 21, 24, 17),
    ("Tsinghua University", "清华大学", "China", 17, 12, 22, 23),
    ("Peking University", "北京大学", "China", 14, 13, 21, 39),
    ("University of Michigan", "密歇根大学安娜堡分校", "United States", 44, 23, 26, 18),
    ("Nanyang Technological University", "南洋理工大学", "Singapore", 12, 30, 82, 30),
    ("University of Melbourne", "墨尔本大学", "Australia", 19, 39, 32, 27),
    ("EPFL", "洛桑联邦理工学院", "Switzerland", 22, 33, 65, 46),
    ("University of Tokyo", "东京大学", "Japan", 32, 28, 27, 73),
    ("University of Hong Kong", "香港大学", "Hong Kong SAR", 11, 35, 90, 66),
    ("New York University", "纽约大学", "United States", 30, 29, 30, 29),
    ("Northwestern University", "西北大学", "United States", 50, 26, 34, 24),
    ("University of Edinburgh", "爱丁堡大学", "United Kingdom", 27, 29, 38, 34),
    ("King's College London", "伦敦国王学院", "United Kingdom", 31, 36, 47, 33),
    ("Duke University", "杜克大学", "United States", 51, 32, 31, 21),
    ("University of California, San Diego", "加州大学圣地亚哥分校", "United States", 72, 34, 18, 20),
    ("Carnegie Mellon University", "卡内基梅隆大学", "United States", 58, 24, 95, 28),
    ("Fudan University", "复旦大学", "China", 30, 36, 33, 61),
    ("Shanghai Jiao Tong University", "上海交通大学", "China", 45, 45, 25, 68),
    ("Zhejiang University", "浙江大学", "China", 45, 47, 30, 71),
    ("Australian National University", "澳大利亚国立大学", "Australia", 32, 73, 62, 62),
    ("University of British Columbia", "不列颠哥伦比亚大学", "Canada", 38, 41, 40, 35),
    ("McGill University", "麦吉尔大学", "Canada", 27, 45, 78, 51),
    ("Kyoto University", "京都大学", "Japan", 43, 55, 39, 121),
    ("Seoul National University", "首尔国立大学", "South Korea", 31, 62, 89, 130),
    ("Technical University of Munich", "慕尼黑工业大学", "Germany", 22, 26, 52, 78),
    ("University of Manchester", "曼彻斯特大学", "United Kingdom", 34, 53, 51, 65),
    ("PSL University", "巴黎文理研究大学", "France", 24, 41, 39, 44),
    ("University of Washington", "华盛顿大学", "United States", 63, 26, 3, 6),
    ("Chinese University of Hong Kong", "香港中文大学", "Hong Kong SAR", 32, 44, 101, 76),
    ("Hong Kong University of Science and Technology", "香港科技大学", "Hong Kong SAR", 44, 66, 151, 108),
    ("University of Sydney", "悉尼大学", "Australia", 18, 61, 60, 32),
    ("University of New South Wales", "新南威尔士大学", "Australia", 20, 70, 64, 40),
    ("Monash University", "莫纳什大学", "Australia", 36, 58, 78, 42),
    ("University of Queensland", "昆士兰大学", "Australia", 40, 77, 53, 36),
    ("University of Amsterdam", "阿姆斯特丹大学", "Netherlands", 55, 60, 101, 45),
    ("Delft University of Technology", "代尔夫特理工大学", "Netherlands", 49, 48, 151, 82),
    ("Ludwig Maximilian University of Munich", "慕尼黑大学", "Germany", 59, 38, 51, 43),
    ("Heidelberg University", "海德堡大学", "Germany", 87, 47, 57, 48),
    ("KU Leuven", "鲁汶大学", "Belgium", 68, 45, 87, 70),
    ("University of Copenhagen", "哥本哈根大学", "Denmark", 82, 105, 30, 31),
    ("Karolinska Institute", "卡罗林斯卡学院", "Sweden", None, 50, 42, 37),
    ("University of Wisconsin-Madison", "威斯康星大学麦迪逊分校", "United States", 91, 82, 34, 41),
    ("University of Texas at Austin", "得克萨斯大学奥斯汀分校", "United States", 66, 43, 41, 38),
    ("Georgia Institute of Technology", "佐治亚理工学院", "United States", 76, 39, 82, 60),
    ("University of Illinois Urbana-Champaign", "伊利诺伊大学香槟分校", "United States", 69, 51, 45, 53),
    ("Brown University", "布朗大学", "United States", 48, 64, 101, 111),
    ("University of Bristol", "布里斯托大学", "United Kingdom", 54, 78, 78, 84),
    ("École Polytechnique", "巴黎综合理工学院", "France", 57, 71, None, None),
    ("Sorbonne University", "索邦大学", "France", 72, 75, 41, 56),
    ("Utrecht University", "乌得勒支大学", "Netherlands", 105, 71, 49, 52),
    ("Lund University", "隆德大学", "Sweden", 75, 116, 101, 88),
    ("University of Zurich", "苏黎世大学", "Switzerland", 92, 91, 59, 54),
    ("University of Warwick", "华威大学", "United Kingdom", 69, 106, 151, 148),
    ("London School of Economics and Political Science", "伦敦政治经济学院", "United Kingdom", 56, 56, 151, 258),
    ("University of Glasgow", "格拉斯哥大学", "United Kingdom", 76, 87, 151, 129),
    ("Michigan State University", "密歇根州立大学", "United States", None, 118, 101, 132),
    ("University of Southern California", "南加州大学", "United States", 121, 70, 55, 47),
    ("University of North Carolina at Chapel Hill", "北卡罗来纳大学教堂山分校", "United States", None, 76, 44, 55),
    ("University of California, Davis", "加州大学戴维斯分校", "United States", 128, 59, 79, 63),
    ("Purdue University", "普渡大学", "United States", 89, 105, 68, 87),
    ("University of Minnesota", "明尼苏达大学", "United States", 155, 108, 46, 50),
    ("Nanjing University", "南京大学", "China", 89, 65, 51, 91),
    ("University of Science and Technology of China", "中国科学技术大学", "China", 133, 57, 62, 105),
    ("Wuhan University", "武汉大学", "China", 194, 178, 101, 133),
    ("KAIST", "韩国科学技术院", "South Korea", 53, 82, 201, 205),
    ("Yonsei University", "延世大学", "South Korea", 50, 106, 201, 264),
    ("Korea University", "高丽大学", "South Korea", 61, 104, 201, 297),
    ("Osaka University", "大阪大学", "Japan", 75, 175, 87, 175),
    ("Tohoku University", "东北大学", "Japan", 96, 130, 82, 174),
    ("Tokyo Institute of Technology", "东京工业大学", "Japan", 84, 191, 151, 246),
    ("National Taiwan University", "台湾大学", "Taiwan", 68, 172, 151, 187),
    ("University of Malaya", "马来亚大学", "Malaysia", 60, 251, 301, 356),
    ("Trinity College Dublin", "都柏林圣三一学院", "Ireland", 87, 171, 201, 244),
    ("University of Auckland", "奥克兰大学", "New Zealand", 65, 152, 201, 208),
    ("Ghent University", "根特大学", "Belgium", 142, 89, 71, 74),
    ("University of Helsinki", "赫尔辛基大学", "Finland", 115, 101, 74, 89),
    ("Uppsala University", "乌普萨拉大学", "Sweden", 105, 140, 79, 110),
    ("KTH Royal Institute of Technology", "皇家理工学院", "Sweden", 123, 155, 201, 179),
    ("Leiden University", "莱顿大学", "Netherlands", 136, 88, 88, 77),
    ("Erasmus University Rotterdam", "鹿特丹伊拉斯姆斯大学", "Netherlands", 176, 99, 79, 64),
    ("University of Geneva", "日内瓦大学", "Switzerland", 168, 160, 62, 96),
    ("Aarhus University", "奥胡斯大学", "Denmark", 152, 111, 73, 79),
    ("University of Vienna", "维也纳大学", "Austria", 130, 130, 101, 130),
    ("Humboldt University of Berlin", "柏林洪堡大学", "Germany", 126, 87, 101, 92),
    ("RWTH Aachen University", "亚琛工业大学", "Germany", 99, 90, 201, 214),
    ("University of Freiburg", "弗莱堡大学", "Germany", 190, 111, 101, 107),
    ("University of Tübingen", "图宾根大学", "Germany", 226, 95, 151, 122),
    ("University of Bonn", "波恩大学", "Germany", 239, 91, 70, 85),
    ("Charité - Berlin", "柏林夏里特医学院", "Germany", None, 130, None, None),
    ("University of Barcelona", "巴塞罗那大学", "Spain", 149, 152, 151, 90),
    ("Autonomous University of Barcelona", "巴塞罗那自治大学", "Spain", 154, 178, 201, 145),
    ("Sapienza University of Rome", "罗马大学", "Italy", 128, 132, 101, 98),
    ("University of Bologna", "博洛尼亚大学", "Italy", 133, 160, 151, 137),
    ("Politecnico di Milano", "米兰理工大学", "Italy", 98, 152, 201, None),
    ("University of Padua", "帕多瓦大学", "Italy", 219, 210, 101, 116),
    ("Pohang University of Science and Technology", "浦项科技大学", "South Korea", 98, 151, 301, 393),
    ("Sungkyunkwan University", "成均馆大学", "South Korea", 123, 106, 101, 187),
    ("Indian Institute of Science", "印度科学理学院", "India", 219, 251, 401, None),
    ("Indian Institute of Technology Bombay", "印度理工孟买分校", "India", 129, 301, None, None),
    ("Indian Institute of Technology Delhi", "印度理工德里分校", "India", 123, 351, None, None),
    ("King Abdulaziz University", "阿卜杜勒阿齐兹国王大学", "Saudi Arabia", 143, 101, 101, 62),
    ("University of Sao Paulo", "圣保罗大学", "Brazil", 92, 201, 101, 108),
    ("Boston University", "波士顿大学", "United States", 108, 60, 82, 57),
    ("Ohio State University", "俄亥俄州立大学", "United States", 156, 108, 68, 58),
    ("University of Maryland, College Park", "马里兰大学帕克分校", "United States", 169, 130, 55, 67),
    ("Pennsylvania State University", "宾夕法尼亚州立大学", "United States", 105, 118, 79, 72),
    ("University of Pittsburgh", "匹兹堡大学", "United States", 168, 130, 68, 59),
    ("University of California, Irvine", "加州大学欧文分校", "United States", 195, 105, 68, 69),
    ("University of California, Santa Barbara", "加州大学圣塔芭芭拉分校", "United States", 190, 105, 51, 87),
    ("Rice University", "莱斯大学", "United States", 141, 168, 101, 105),
    ("Emory University", "埃默里大学", "United States", 158, 168, 101, 75),
    ("Vanderbilt University", "范德堡大学", "United States", 154, 133, 101, 81),
    ("University of Notre Dame", "圣母大学", "United States", 269, 191, 201, 210),
    ("Washington University in St. Louis", "圣路易斯华盛顿大学", "United States", 116, 105, 34, 100),
    ("Rutgers University", "罗格斯大学", "United States", 351, 178, 78, 83),
    ("University of Colorado Boulder", "科罗拉多大学博尔德分校", "United States", 234, 175, 55, 82),
    ("Arizona State University", "亚利桑那州立大学", "United States", 179, 133, 101, 101),
    ("University of Florida", "佛罗里达大学", "United States", 173, 151, 68, 86),
    ("Texas A&M University", "得克萨斯农工大学", "United States", 154, 178, 101, 118),
    ("University of Virginia", "弗吉尼亚大学", "United States", 208, 151, 201, 130),
    ("Dartmouth College", "达特茅斯学院", "United States", 226, 133, 301, 246),
    ("University of Sheffield", "谢菲尔德大学", "United Kingdom", 105, 114, 101, 119),
    ("University of Nottingham", "诺丁汉大学", "United Kingdom", 108, 158, 151, 152),
    ("University of Birmingham", "伯明翰大学", "United Kingdom", 84, 105, 101, 120),
    ("University of Leeds", "利兹大学", "United Kingdom", 82, 128, 151, 154),
    ("University of Southampton", "南安普顿大学", "United Kingdom", 80, 108, 151, 121),
    ("Durham University", "杜伦大学", "United Kingdom", 89, 162, 301, 273),
    ("University of St Andrews", "圣安德鲁斯大学", "United Kingdom", 100, 105, 301, 375),
    ("Queen Mary University of London", "伦敦玛丽女王大学", "United Kingdom", 110, 110, 151, 155),
    ("University of York", "约克大学", "United Kingdom", 165, 147, 201, 264),
    ("Lancaster University", "兰卡斯特大学", "United Kingdom", 128, 158, 301, None),
    ("Cardiff University", "卡迪夫大学", "United Kingdom", 176, 178, 151, 158),
    ("University of Liverpool", "利物浦大学", "United Kingdom", 176, 178, 101, 141),
    ("University of Aberdeen", "阿伯丁大学", "United Kingdom", 236, 210, 301, None),
    ("Newcastle University", "纽卡斯尔大学", "United Kingdom", 129, 168, 201, 172),
    ("University of Exeter", "埃克塞特大学", "United Kingdom", 169, 143, 201, 189),
    ("University of Bath", "巴斯大学", "United Kingdom", 179, 201, 301, None),
    ("Sun Yat-sen University", "中山大学", "China", 267, 201, 68, 89),
    ("Huazhong University of Science and Technology", "华中科技大学", "China", 300, 251, 82, 96),
    ("Harbin Institute of Technology", "哈尔滨工业大学", "China", 252, 301, 101, 133),
    ("Xi'an Jiaotong University", "西安交通大学", "China", 288, 251, 101, 148),
    ("Tongji University", "同济大学", "China", 192, 301, 151, 158),
    ("Beihang University", "北京航空航天大学", "China", 331, 251, 151, 174),
    ("Wuhan University of Technology", "武汉理工大学", "China", None, 401, 201, 214),
    ("Southern University of Science and Technology", "南方科技大学", "China", 285, 148, 151, None),
    ("Beijing Normal University", "北京师范大学", "China", 271, 178, 201, 187),
    ("Nankai University", "南开大学", "China", 320, 251, 101, 145),
    ("Shandong University", "山东大学", "China", 344, 351, 151, 189),
    ("Sichuan University", "四川大学", "China", 435, 251, 101, 128),
    ("Central South University", "中南大学", "China", 400, 301, 151, 145),
    ("City University of Hong Kong", "香港城市大学", "Hong Kong SAR", 62, 82, 201, 138),
    ("Hong Kong Polytechnic University", "香港理工大学", "Hong Kong SAR", 54, 84, 201, 145),
    ("Nagoya University", "名古屋大学", "Japan", 152, 201, 101, 208),
    ("Kyushu University", "九州大学", "Japan", 133, 351, 151, 289),
    ("Hokkaido University", "北海道大学", "Japan", 173, 351, 201, 297),
    ("University of Basel", "巴塞尔大学", "Switzerland", 261, 130, 101, 90),
    ("University of Bern", "伯尔尼大学", "Switzerland", 142, 130, 151, 95),
    ("Wageningen University & Research", "瓦赫宁根大学", "Netherlands", 130, 66, 101, 111),
    ("University of Groningen", "格罗宁根大学", "Netherlands", 139, 79, 79, 94),
    ("Radboud University", "拉德堡德大学", "Netherlands", 233, 105, 101, 116),
    ("Eindhoven University of Technology", "埃因霍温理工大学", "Netherlands", 124, 201, None, None),
    ("University of Oslo", "奥斯陆大学", "Norway", 117, 130, 67, 89),
    ("University of Gothenburg", "哥德堡大学", "Sweden", 187, 191, 151, 130),
    ("Stockholm University", "斯德哥尔摩大学", "Sweden", 168, 176, 79, 105),
    ("Aalto University", "阿尔托大学", "Finland", 114, 251, 301, None),
    ("Technical University of Denmark", "丹麦技术大学", "Denmark", 108, 191, 151, 121),
    ("University of Cape Town", "开普敦大学", "South Africa", 171, 155, 201, 111),
    ("University of Buenos Aires", "布宜诺斯艾利斯大学", "Argentina", 84, 601, None, None),
    ("National Autonomous University of Mexico", "墨西哥国立自治大学", "Mexico", 94, 601, None, None),
    ("Lomonosov Moscow State University", "莫斯科国立大学", "Russia", 87, 401, 101, None),
    ("Tel Aviv University", "特拉维夫大学", "Israel", 218, 201, 151, 111),
    ("Hebrew University of Jerusalem", "希伯来大学", "Israel", 224, 251, 101, 121),
    ("Technion - Israel Institute of Technology", "以色列理工学院", "Israel", 265, 201, 101, 152),
    ("Chalmers University of Technology", "查尔姆斯理工大学", "Sweden", 129, 201, 301, None),
    ("Norwegian University of Science and Technology", "挪威科技大学", "Norway", 292, 201, 151, 189),
    ("University of Adelaide", "阿德莱德大学", "Australia", 82, 128, 151, 152),
    ("University of Western Australia", "西澳大学", "Australia", 77, 149, 101, 96),
    ("University of Technology Sydney", "悉尼科技大学", "Australia", 88, 154, 201, 172),
    ("Macquarie University", "麦考瑞大学", "Australia", 130, 178, 201, 235),
    ("University of Waterloo", "滑铁卢大学", "Canada", 115, 158, 151, 189),
    ("University of Alberta", "阿尔伯塔大学", "Canada", 96, 118, 101, 130),
    ("McMaster University", "麦克马斯特大学", "Canada", 176, 116, 101, 96),
    ("Université de Montréal", "蒙特利尔大学", "Canada", 141, 141, 151, 141),
    ("Western University", "西安大略大学", "Canada", 114, 201, 201, 214),
    ("University of Ottawa", "渥太华大学", "Canada", 189, 158, 201, 189),
    ("University of Calgary", "卡尔加里大学", "Canada", 182, 201, 201, 214),
    ("Aristotle University of Thessaloniki", "亚里士多德大学", "Greece", 411, 401, 301, None),
    ("Charles University", "查理大学", "Czech Republic", 246, 401, 201, 214),
    ("University of Warsaw", "华沙大学", "Poland", 262, 401, 301, None),
    ("University of Lisbon", "里斯本大学", "Portugal", 253, 201, 151, 189),
]

# ---------------------------------------------------------------- 实时数据源（GitHub Actions）

def fetch_qs():
    """QS：榜单页 AJAX 端点返回 JSON（含 rank_display / title / region / country / overall_score）。
    先从主榜单页发现最新一期的节点 id（nid），再翻页取满。任一步失败返回 None。"""
    page = http_get("https://www.topuniversities.com/world-university-rankings")
    if not page:
        return None
    m = re.search(r'"nid"\s*:\s*"?(\d{5,})"?', page) or re.search(r'nid=(\d{5,})', page)
    if not m:
        print("  QS：未发现榜单 nid")
        return None
    nid = m.group(1)
    found = {}
    for pg in range(0, 4):  # 每页 100，取前 ~400 足够覆盖前 300
        url = (f"https://www.topuniversities.com/rankings/endpoint?nid={nid}"
               f"&page={pg}&items_per_page=100&tab=indicators")
        txt = http_get(url)
        if not txt:
            break
        try:
            nodes = json.loads(txt).get("score_nodes") or []
        except Exception:
            break
        if not nodes:
            break
        for n in nodes:
            name = re.sub(r"<[^>]+>", "", str(n.get("title") or "")).strip()
            rk = _rank_num(n.get("rank_display") or n.get("rank"))
            country = str(n.get("country") or n.get("region") or "").strip()
            if name and rk:
                found.setdefault(ukey(name), {"name": name, "rank": rk, "country": country})
    if len(found) >= 100:
        print(f"  QS：解析到 {len(found)} 所")
        return found
    print(f"  QS：仅解析到 {len(found)} 所，判为失败")
    return None


def fetch_the():
    """THE：榜单页内嵌一个整表 JSON 文件（the_data_rankings/..._0__<hash>.json），一次拿全表。"""
    page = http_get("https://www.timeshighereducation.com/world-university-rankings/latest/world-ranking")
    if not page:
        page = http_get("https://www.timeshighereducation.com/world-university-rankings")
    if not page:
        return None
    m = re.search(r'(?:/sites/default/files/)?the_data_rankings/[A-Za-z0-9_./-]+\.json', page)
    if not m:
        print("  THE：未发现整表 JSON 地址")
        return None
    path = m.group(0)
    if not path.startswith("http"):
        path = "https://www.timeshighereducation.com/" + path.lstrip("/")
    txt = http_get(path)
    if not txt:
        return None
    try:
        rows = json.loads(txt).get("data") or []
    except Exception:
        return None
    found = {}
    for r in rows:
        name = str(r.get("name") or "").strip()
        rk = _rank_num(r.get("rank"))
        country = str(r.get("location") or "").strip()
        if name and rk:
            found.setdefault(ukey(name), {"name": name, "rank": rk, "country": country})
    if len(found) >= 100:
        print(f"  THE：解析到 {len(found)} 所")
        return found
    print(f"  THE：仅解析到 {len(found)} 所，判为失败")
    return None


def fetch_arwu():
    """ARWU（软科）：榜单 API 分页返回 JSON。站点为 Nuxt，接口相对稳定；失败返回 None。"""
    found = {}
    for pg in range(1, 5):  # 每页 100
        url = (f"https://www.shanghairanking.com/api/pub/v1/arwu/rank"
               f"?version=&page={pg}&pageSize=100")
        txt = http_get(url, headers={"Accept": "application/json"})
        if not txt:
            break
        try:
            rows = (json.loads(txt).get("data") or {}).get("rankings") or []
        except Exception:
            break
        if not rows:
            break
        for r in rows:
            name = str(r.get("univNameEn") or r.get("univNameZh") or "").strip()
            rk = _rank_num(r.get("ranking") or r.get("rank"))
            country = str(r.get("region") or r.get("country") or "").strip()
            if name and rk:
                found.setdefault(ukey(name), {"name": name, "rank": rk, "country": country})
    if len(found) >= 100:
        print(f"  ARWU：解析到 {len(found)} 所")
        return found
    print(f"  ARWU：仅解析到 {len(found)} 所，判为失败")
    return None


def fetch_usnews():
    """U.S. News Best Global Universities：官方 API 分页 JSON。失败返回 None。"""
    found = {}
    for pg in range(1, 4):
        url = (f"https://www.usnews.com/education/best-global-universities/api/search"
               f"?format=json&page={pg}")
        txt = http_get(url, headers={"Accept": "application/json"})
        if not txt:
            break
        try:
            data = json.loads(txt)
            rows = data.get("items") or data.get("data") or []
        except Exception:
            break
        if not rows:
            break
        for r in rows:
            name = str(r.get("name") or r.get("institution") or "").strip()
            rk = _rank_num(r.get("rank") or (r.get("ranks") or {}).get("Best Global Universities"))
            country = str(r.get("country") or "").strip()
            if name and rk:
                found.setdefault(ukey(name), {"name": name, "rank": rk, "country": country})
    if len(found) >= 80:
        print(f"  USNews：解析到 {len(found)} 所")
        return found
    print(f"  USNews：仅解析到 {len(found)} 所，判为失败")
    return None


def _rank_num(v):
    """'=12' / '15' / '201–250' / '601+' → 起始整数位次；无法解析返回 None。"""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return int(v) if v > 0 else None
    s = str(v).strip().lstrip("=#")
    m = re.match(r"(\d+)", s.replace(",", ""))
    return int(m.group(1)) if m else None

# ---------------------------------------------------------------- 合并与产出

def load_prev():
    try:
        with open(OUT, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def merge_live(qs, the, arwu, usn):
    """把命中的实时源按归一键合并；沿用 SEED 的中文名/国别信息。"""
    seed_by_key = {}
    for name, cn, country, *_ in SEED:
        if name:
            seed_by_key[ukey(name)] = (name, cn, country)

    keys = set()
    for src in (qs, the, arwu, usn):
        if src:
            keys |= set(src.keys())

    models = []
    for k in keys:
        parts = [(qs or {}).get(k), (the or {}).get(k), (arwu or {}).get(k), (usn or {}).get(k)]
        any_part = next((p for p in parts if p), None)
        if not any_part:
            continue
        seed = seed_by_key.get(k)
        name = seed[0] if seed else any_part["name"]
        cn = seed[1] if seed else ""
        country = seed[2] if seed else any_part["country"]
        cn_name, flag = COUNTRY.get(country, (cn or country, "🌐"))
        dom = UNIV_DOMAIN.get(name)
        models.append({
            "name": name, "cn": cn or cn_name, "country": country, "flag": flag,
            "slug": logo_slug(dom) if dom else None,
            "qs": parts[0]["rank"] if parts[0] else None,
            "the": parts[1]["rank"] if parts[1] else None,
            "arwu": parts[2]["rank"] if parts[2] else None,
            "usn": parts[3]["rank"] if parts[3] else None,
        })
    return models


def models_from_seed():
    out = []
    for name, cn, country, qs, the, arwu, usn in SEED:
        if not name or country not in COUNTRY:
            continue
        cn_name, flag = COUNTRY.get(country, (cn, "🌐"))
        dom = UNIV_DOMAIN.get(name)
        out.append({"name": name, "cn": cn, "country": country, "flag": flag,
                    "slug": logo_slug(dom) if dom else None,
                    "qs": qs, "the": the, "arwu": arwu, "usn": usn})
    return out


def rank_and_cut(models):
    """至少命中 2 个榜才计综合；综合 = 各榜位次均值。按均值升序取前 LIMIT。"""
    def avg_rank(m):
        rs = [m[k] for k in ("qs", "the", "arwu", "usn") if isinstance(m[k], (int, float))]
        return (sum(rs) / len(rs)) if len(rs) >= 2 else None

    scored, singles = [], []
    for m in models:
        a = avg_rank(m)
        if a is None:
            singles.append(m)
        else:
            m["_avg"] = round(a, 1)
            scored.append(m)
    scored.sort(key=lambda m: m["_avg"])
    out = scored + sorted(singles, key=lambda m: min(
        [m[k] for k in ("qs", "the", "arwu", "usn") if isinstance(m[k], (int, float))] or [9999]))
    out = out[:LIMIT]
    for m in out:
        m.pop("_avg", None)
    return out


SOURCES = [
    {"key": "qs", "name": "QS 世界大学排名", "url": "https://www.topuniversities.com/world-university-rankings",
     "desc": "Quacquarelli Symonds，侧重学术声誉、雇主声誉与国际化"},
    {"key": "the", "name": "THE 泰晤士高等教育世界大学排名", "url": "https://www.timeshighereducation.com/world-university-rankings",
     "desc": "18 项指标，覆盖教学、研究、引用、产业与国际展望"},
    {"key": "arwu", "name": "ARWU 软科世界大学学术排名", "url": "https://www.shanghairanking.com/rankings/arwu/",
     "desc": "上海交大发起，重科研产出与顶级奖项（诺奖/菲尔兹/高被引）"},
    {"key": "usn", "name": "U.S. News 全球最佳大学", "url": "https://www.usnews.com/education/best-global-universities",
     "desc": "以全球研究声誉与文献计量表现为主"},
]


def build():
    print("抓取 QS…"); qs = fetch_qs()
    print("抓取 THE…"); the = fetch_the()
    print("抓取 ARWU…"); arwu = fetch_arwu()
    print("抓取 U.S. News…"); usn = fetch_usnews()

    prev = load_prev()
    live_hits = sum(1 for x in (qs, the, arwu, usn) if x)

    if live_hits >= 2:
        models = merge_live(qs, the, arwu, usn)
        models = rank_and_cut(models)
        seed_flag = False
        note = "综合排名取自 QS / THE / ARWU / U.S. News 四大权威榜单，按各校在各榜位次的平均值排序（ARTU 式聚合），每日自动更新。各榜口径不同，位次仅供参考。"
    else:
        if prev and prev.get("universities"):
            print(f"实时有效源过少（{live_hits}）：保留上次 data.json 不覆盖")
            return 0
        print(f"实时有效源过少（{live_hits}）：使用内置 SEED 上线快照")
        models = rank_and_cut(models_from_seed())
        seed_flag = True
        note = "年度权威数据整理：综合 QS / THE / ARWU / U.S. News 四大权威世界大学排名近一期公开位次，按各校在各榜的平均位次（ARTU 式聚合）排序。各榜评价口径不同，数据以各榜官方公布为准，仅供参考。"

    if len(models) < 50:
        if prev and prev.get("universities"):
            print(f"有效学校过少（{len(models)}）：保留上次 data.json")
            return 0
        print(f"有效学校过少（{len(models)}）且无历史数据")
        return 1

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out = {
        "updatedAt": now, "asOf": now[:10], "seed": seed_flag,
        "count": len(models), "note": note,
        "axisStatus": {"qs": bool(qs), "the": bool(the), "arwu": bool(arwu), "usn": bool(usn)},
        "sources": SOURCES,
        "universities": models,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"完成：写入 {len(models)} 所大学 → {OUT}（seed={seed_flag}）")
    return 0


if __name__ == "__main__":
    sys.exit(build())
