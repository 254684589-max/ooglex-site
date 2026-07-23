#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球电影榜」数据：从 TMDB（The Movie Database）公开 API 取「高分电影 Top 250」与「全球最新上映」，
含中文片名、海报、评分，写入 apps/movies/data.json。

站内播放（全部走合法渠道，不碰任何盗版片源）：
- 每部片额外取 TMDB 详情（append_to_response=videos,watch/providers），把官方预告片的 YouTube key
  与正版观看渠道（TMDB × JustWatch，取 HK/TW/US 三地）写进 data.json，前端点海报弹窗即播；
- 另建「公版经典」榜单：美国公有领域电影，正片由 Internet Archive 官方 embed 提供，
  构建时逐条校验条目可播（metadata API），失效则按片名搜索高下载量替代条目，找不到就剔除。

高分榜排序：从 TMDB top_rated 取候选池，按 IMDb 同款「贝叶斯加权评分」排序——
  WR = v/(v+m)·R + m/(v+m)·C   （R=该片均分，v=票数，m=票数基准，C=候选池平均分）
于是「经典优先」：高分且票数多的经典片排在前面，挡掉刚上映、票数极少却虚高的新片。

为什么用 TMDB：IMDb 官方禁止服务器抓取（实测对机房 IP 返回空页，连免密钥代理也取不到），
而 TMDB 提供稳定的官方 API（含海报、中文本地化、最新上映），是从 GitHub Actions 可靠取数的正路。

需要一个免费的 TMDB API Key，放在 GitHub Secret `TMDB_KEY` 里（themoviedb.org 注册即可免费申请）。
未配置 key 时本脚本不动数据（保留上次 data.json）。失败同样保留上次数据，绝不用空数据覆盖。
由 .github/workflows/movies.yml 每日定时运行。
"""
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "movies", "data.json")
TMDB_KEY = os.environ.get("TMDB_KEY", "").strip()
API = "https://api.themoviedb.org/3"
IMG = "https://image.tmdb.org/t/p/w342"      # 海报尺寸（浏览器直接从 TMDB 图床加载）
HEADERS = {"User-Agent": "personal-site-movies/1.0"}

MIN_VOTES = 3000      # 贝叶斯加权的票数基准 m（IMDb Top 250 同款公式）
FLOOR_VOTES = 1000    # 入选最低票数：挡掉刚上映、票数极少却虚高的新片
POOL_PAGES = 40       # 高分候选池页数（每页 20 → 约 800 部，加权后取前 250）

WATCH_REGIONS = ["HK", "TW", "US"]   # JustWatch 无中国大陆数据，取就近华语区 + 美国

CLASSICS_MAX = 365    # 公版榜上限：候选校验通过者按加权评分排序取前 365 部

# 公版经典候选池（约 380 部）：(中文名, 原名, 年份, Internet Archive 条目标识)。
# 选片口径（避开权利争议）：
#   - 1930 年（含）以前的影片：不论国别，美国版权均已因年限届满进入公有领域；
#   - 1931-1963 美国片：仅收未续期 / 版权声明瑕疵的知名公版片（如 D.O.A.、活死人之夜）；
#   - 1931 年以后的外国片一律不收（URAA 恢复了其美国版权，如 M、罗生门、偷自行车的人）；
#   - 华语片仅收 1945 年（含）以前（1996 年前中国 50 年保护期已届满、未被 URAA 恢复）；
#   - 明确避开：生活多美好、第三人等虽常被误列公版但权利有争议的片子。
# 标识为空表示交给构建时搜索解析（有片长/年份/排除 trailer 三重防护）；
# 已解析成功的标识会通过上次 data.json 自动沿用（见 read_prev_classics）。
CLASSICS_RAW = [
    # —— 影史默片（美国，≤1930）——
    ("月球旅行记", "A Trip to the Moon", 1902, "Levoyagedanslalune"),
    ("灰姑娘", "Cinderella", 1914, ""),
    ("爱丽丝梦游仙境", "Alice in Wonderland", 1915, ""),
    ("党同伐异", "Intolerance", 1916, ""),
    ("残花泪", "Broken Blossoms", 1919, ""),
    ("赖婚", "Way Down East", 1920, ""),
    ("化身博士", "Dr. Jekyll and Mr. Hyde", 1920, ""),
    ("佐罗的标记", "The Mark of Zorro", 1920, ""),
    ("刑罚", "The Penalty", 1920, ""),
    ("暴风雨中的孤儿", "Orphans of the Storm", 1921, ""),
    ("启示录四骑士", "The Four Horsemen of the Apocalypse", 1921, ""),
    ("酋长", "The Sheik", 1921, ""),
    ("三剑客", "The Three Musketeers", 1921, ""),
    ("茶花女", "Camille", 1921, ""),
    ("北方的纳努克", "Nanook of the North", 1922, ""),
    ("罗宾汉", "Robin Hood", 1922, ""),
    ("血与沙", "Blood and Sand", 1922, ""),
    ("莎乐美", "Salomé", 1922, ""),
    ("巴黎圣母院", "The Hunchback of Notre Dame", 1923, ""),
    ("十诫", "The Ten Commandments", 1923, ""),
    ("篷车队", "The Covered Wagon", 1923, ""),
    ("月宫宝盒", "The Thief of Bagdad", 1924, ""),
    ("贪婪", "Greed", 1924, ""),
    ("铁马", "The Iron Horse", 1924, ""),
    ("被打耳光的人", "He Who Gets Slapped", 1924, ""),
    ("彼得潘", "Peter Pan", 1924, ""),
    ("宾虚", "Ben-Hur: A Tale of the Christ", 1925, ""),
    ("歌剧魅影", "The Phantom of the Opera", 1925, ""),
    ("失落的世界", "The Lost World", 1925, ""),
    ("大阅兵", "The Big Parade", 1925, ""),
    ("雄鹰", "The Eagle", 1925, ""),
    ("小安妮·鲁尼", "Little Annie Rooney", 1925, ""),
    ("风滚草", "Tumbleweeds", 1925, ""),
    ("绿野仙踪", "The Wizard of Oz", 1925, ""),
    ("麻雀", "Sparrows", 1926, ""),
    ("酋长之子", "The Son of the Sheik", 1926, ""),
    ("黑海盗", "The Black Pirate", 1926, ""),
    ("唐璜", "Don Juan", 1926, ""),
    ("蝙蝠", "The Bat", 1926, ""),
    ("万王之王", "The King of Kings", 1927, ""),
    ("日出", "Sunrise", 1927, ""),
    ("爵士歌王", "The Jazz Singer", 1927, ""),
    ("翼", "Wings", 1927, ""),
    ("地下世界", "Underworld", 1927, ""),
    ("七重天", "7th Heaven", 1927, ""),
    ("它", "It", 1927, ""),
    ("猫和金丝雀", "The Cat and the Canary", 1927, ""),
    ("群众", "The Crowd", 1928, ""),
    ("笑面人", "The Man Who Laughs", 1928, ""),
    ("风", "The Wind", 1928, ""),
    ("最后命令", "The Last Command", 1928, ""),
    ("纽约船坞", "The Docks of New York", 1928, ""),
    ("挪亚方舟", "Noah's Ark", 1928, ""),
    ("厄舍古厦的倒塌", "The Fall of the House of Usher", 1928, ""),
    ("铁面人", "The Iron Mask", 1929, ""),
    ("掌声", "Applause", 1929, ""),
    ("哈利路亚", "Hallelujah", 1929, ""),
    ("百老汇旋律", "The Broadway Melody", 1929, ""),
    # —— 默片喜剧大师（卓别林 / 基顿 / 劳埃德 / 朗东）——
    ("寻子遇仙记", "The Kid", 1921, ""),
    ("朝圣者", "The Pilgrim", 1923, ""),
    ("巴黎一妇人", "A Woman of Paris", 1923, ""),
    ("淘金记", "The Gold Rush", 1925, "the-gold-rush-film-1925"),
    ("马戏团", "The Circus", 1928, ""),
    ("三个时代", "Three Ages", 1923, ""),
    ("待客之道", "Our Hospitality", 1923, ""),
    ("福尔摩斯二世", "Sherlock Jr.", 1924, ""),
    ("航海家", "The Navigator", 1924, ""),
    ("七次机会", "Seven Chances", 1925, ""),
    ("西行", "Go West", 1925, ""),
    ("战斗的巴特勒", "Battling Butler", 1926, ""),
    ("将军号", "The General", 1926, "TheGeneral"),
    ("大学", "College", 1927, ""),
    ("船长二世", "Steamboat Bill, Jr.", 1928, ""),
    ("摄影师", "The Cameraman", 1928, ""),
    ("祖母的孩子", "Grandma's Boy", 1922, ""),
    ("医生杰克", "Dr. Jack", 1922, ""),
    ("安全至下", "Safety Last!", 1923, ""),
    ("为什么担心", "Why Worry?", 1923, ""),
    ("热水", "Hot Water", 1924, ""),
    ("怕羞小生", "Girl Shy", 1924, ""),
    ("大学新生", "The Freshman", 1925, ""),
    ("小兄弟", "The Kid Brother", 1927, ""),
    ("速度", "Speedy", 1928, ""),
    ("步步登高", "Feet First", 1930, ""),
    ("壮汉", "The Strong Man", 1926, ""),
    # —— 欧洲与苏联默片（≤1930，美国版权已届满）——
    ("卡里加里博士的小屋", "The Cabinet of Dr. Caligari", 1920, "DasKabinettdesDoktorCaligariTheCabinetofDrCaligari"),
    ("泥人哥连出世记", "The Golem: How He Came into the World", 1920, ""),
    ("幽灵马车", "The Phantom Carriage", 1921, ""),
    ("命运", "Destiny", 1921, ""),
    ("诺斯费拉图", "Nosferatu", 1922, "Nosferatu_most_complete_version_93_mins."),
    ("赌徒马布斯博士", "Dr. Mabuse, the Gambler", 1922, ""),
    ("女巫", "Häxan", 1922, ""),
    ("奥赛罗", "Othello", 1922, ""),
    ("尼伯龙根之西格弗里德", "Die Nibelungen: Siegfried", 1924, ""),
    ("最后一笑", "The Last Laugh", 1924, ""),
    ("蜡像馆", "Waxworks", 1924, ""),
    ("火星女王艾莉塔", "Aelita: Queen of Mars", 1924, ""),
    ("戈斯塔·柏林的传说", "The Saga of Gösta Berling", 1924, ""),
    ("西方先生历险记", "The Extraordinary Adventures of Mr. West in the Land of the Bolsheviks", 1924, ""),
    ("战舰波将金号", "Battleship Potemkin", 1925, "BattleshipPotemkin"),
    ("罢工", "Strike", 1925, ""),
    ("杂耍场", "Variety", 1925, ""),
    ("一家之主", "Master of the House", 1925, ""),
    ("母亲", "Mother", 1926, ""),
    ("浮士德", "Faust", 1926, ""),
    ("疯狂的一页", "A Page of Madness", 1926, ""),
    ("大都会", "Metropolis", 1927, "Metropolis1927EnglishVersion"),
    ("柏林：大都市交响曲", "Berlin: Symphony of a Great City", 1927, ""),
    ("圣彼得堡的末日", "The End of St. Petersburg", 1927, ""),
    ("拿破仑", "Napoleon", 1927, ""),
    ("床与沙发", "Bed and Sofa", 1927, ""),
    ("圣女贞德蒙难记", "The Passion of Joan of Arc", 1928, "the-passion-of-joan-of-arc"),
    ("十月", "October (Ten Days that Shook the World)", 1928, ""),
    ("亚洲风暴", "Storm Over Asia", 1928, ""),
    ("意大利草帽", "The Italian Straw Hat", 1928, ""),
    ("间谍", "Spies", 1928, ""),
    ("兵工厂", "Arsenal", 1929, ""),
    ("新巴比伦", "The New Babylon", 1929, ""),
    ("潘多拉的魔盒", "Pandora's Box", 1929, ""),
    ("持摄影机的人", "Man with a Movie Camera", 1929, ""),
    ("堕落少女日记", "Diary of a Lost Girl", 1929, ""),
    ("月里嫦娥", "Woman in the Moon", 1929, ""),
    ("皮兹帕鲁的白色地狱", "The White Hell of Pitz Palu", 1929, ""),
    ("蓝天使", "The Blue Angel", 1930, ""),
    ("大地", "Earth", 1930, ""),
    ("黄金时代", "L'Age d'Or", 1930, ""),
    ("星期天的人们", "People on Sunday", 1930, ""),
    ("卡比利亚", "Cabiria", 1914, ""),
    ("雄吕血", "Orochi", 1925, ""),
    ("房客", "The Lodger", 1927, ""),
    ("拳击场", "The Ring", 1927, ""),
    ("农家妇", "The Farmer's Wife", 1928, ""),
    ("水性杨花", "Easy Virtue", 1928, ""),
    ("孟克斯人", "The Manxman", 1929, ""),
    ("讹诈", "Blackmail", 1929, ""),
    ("青草", "Grass: A Nation's Battle for Life", 1925, ""),
    ("象群", "Chang: A Drama of the Wilderness", 1927, ""),
    ("莫阿纳", "Moana", 1926, ""),
    # —— 华语老片（≤1945，中国 50 年保护期已届满且未被 URAA 恢复）——
    ("桃花泣血记", "Peach Blossom Weeps Tears of Blood", 1931, ""),
    ("恋爱与义务", "Love and Duty", 1931, ""),
    ("小玩意", "Little Toys", 1933, ""),
    ("神女", "The Goddess", 1934, ""),
    ("大路", "The Big Road", 1934, ""),
    ("渔光曲", "Song of the Fishermen", 1934, ""),
    ("体育皇后", "Queen of Sports", 1934, ""),
    ("姊妹花", "Twin Sisters", 1934, ""),
    ("新女性", "New Women", 1935, ""),
    ("迷途的羔羊", "Lost Lambs", 1936, ""),
    ("马路天使", "Street Angel", 1937, ""),
    ("十字街头", "Crossroads", 1937, ""),
    ("夜半歌声", "Song at Midnight", 1937, ""),
    ("铁扇公主", "Princess Iron Fan", 1941, ""),
    # —— 1930 年代好莱坞（未续期公版片）——
    ("西线无战事", "All Quiet on the Western Front", 1930, ""),
    ("摩洛哥", "Morocco", 1930, ""),
    ("地狱天使", "Hell's Angels", 1930, ""),
    ("大追踪", "The Big Trail", 1930, ""),
    ("动物饼干", "Animal Crackers", 1930, ""),
    ("城市女孩", "City Girl", 1930, ""),
    ("蝙蝠密语", "The Bat Whispers", 1930, ""),
    ("亚伯拉罕·林肯", "Abraham Lincoln", 1930, ""),
    ("爵士之王", "King of Jazz", 1930, ""),
    ("头版", "The Front Page", 1931, ""),
    ("斯文加利", "Svengali", 1931, ""),
    ("养夫记", "Kept Husbands", 1931, ""),
    ("米莉", "Millie", 1931, ""),
    ("最危险的游戏", "The Most Dangerous Game", 1932, ""),
    ("战地春梦", "A Farewell to Arms", 1932, ""),
    ("雨", "Rain", 1932, ""),
    ("肯内尔谋杀案", "The Kennel Murder Case", 1933, ""),
    ("血字的研究", "A Study in Scarlet", 1933, ""),
    ("无畏泰山", "Tarzan the Fearless", 1933, ""),
    ("他的私人秘书", "His Private Secretary", 1933, ""),
    ("人性枷锁", "Of Human Bondage", 1934, ""),
    ("简爱", "Jane Eyre", 1934, ""),
    ("帕鲁卡", "Palooka", 1934, ""),
    ("蓓姬·夏普", "Becky Sharp", 1935, ""),
    ("一个惊恐之夜", "One Frightened Night", 1935, ""),
    ("疯狂大麻", "Reefer Madness", 1936, ""),
    ("我的戈弗雷", "My Man Godfrey", 1936, ""),
    ("牛奶之路", "The Milky Way", 1936, ""),
    ("大好人", "Great Guy", 1936, ""),
    ("一个明星的诞生", "A Star Is Born", 1937, ""),
    ("毫不神圣", "Nothing Sacred", 1937, ""),
    ("载歌载舞", "Something to Sing About", 1937, ""),
    ("泰山复仇", "Tarzan's Revenge", 1938, ""),
    ("泰山与绿色女神", "Tarzan and the Green Goddess", 1938, ""),
    ("小公主", "The Little Princess", 1939, ""),
    ("爱情事件", "Love Affair", 1939, ""),
    ("天作之合", "Made for Each Other", 1939, ""),
    ("格列佛游记", "Gulliver's Travels", 1939, ""),
    ("飞行双雄", "The Flying Deuces", 1939, ""),
    # —— 1940 年代 ——
    ("女友礼拜五", "His Girl Friday", 1940, "his_girl_friday"),
    ("第二合唱", "Second Chorus", 1940, ""),
    ("超越明天", "Beyond Tomorrow", 1940, ""),
    ("约翰·多伊", "Meet John Doe", 1941, ""),
    ("一分钱小夜曲", "Penny Serenade", 1941, ""),
    ("一罐金子", "Pot o' Gold", 1941, ""),
    ("托珀归来", "Topper Returns", 1941, ""),
    ("患得患失", "That Uncertain Feeling", 1941, ""),
    ("小虫都市", "Mr. Bug Goes to Town", 1941, ""),
    ("上海风光", "The Shanghai Gesture", 1941, ""),
    ("月亮与六便士", "The Moon and Sixpence", 1942, ""),
    ("舞台门俱乐部", "Stage Door Canteen", 1943, ""),
    ("工合", "Gung Ho!", 1943, ""),
    ("亡命之徒", "The Outlaw", 1943, ""),
    ("血洒太阳", "Blood on the Sun", 1945, ""),
    ("南方人", "The Southerner", 1945, ""),
    ("大兵乔的故事", "The Story of G.I. Joe", 1945, ""),
    ("太阳下的散步", "A Walk in the Sun", 1945, ""),
    ("布鲁斯特的百万横财", "Brewster's Millions", 1945, ""),
    ("天伦乐", "Life with Father", 1947, ""),
    ("我最爱的黑发女郎", "My Favorite Brunette", 1947, ""),
    ("多尔西兄弟", "The Fabulous Dorseys", 1947, ""),
    ("我亲爱的秘书", "My Dear Secretary", 1948, ""),
    ("圣女贞德", "Joan of Arc", 1948, ""),
    ("钦差大臣", "The Inspector General", 1949, ""),
    ("非洲尖叫", "Africa Screams", 1949, ""),
    ("云霄曲", "Till the Clouds Roll By", 1946, ""),
    # —— 黑色电影 ——
    ("绕道", "Detour", 1945, "Detour"),
    ("血红街道", "Scarlet Street", 1945, ""),
    ("奇异幻觉", "Strange Illusion", 1945, ""),
    ("大弗拉马里翁", "The Great Flamarion", 1945, ""),
    ("玛莎·艾佛丝的奇爱", "The Strange Love of Martha Ivers", 1946, ""),
    ("追逐", "The Chase", 1946, ""),
    ("奇异女子", "The Strange Woman", 1946, ""),
    ("惠斯尔小站", "Whistle Stop", 1946, ""),
    ("红房子", "The Red House", 1947, ""),
    ("夜惊魂", "Fear in the Night", 1947, ""),
    ("铁路蒙冤", "Railroaded!", 1947, ""),
    ("联邦密探", "T-Men", 1947, ""),
    ("神奇的X先生", "The Amazing Mr. X", 1948, ""),
    ("夜行者", "He Walked by Night", 1948, ""),
    ("无情", "Ruthless", 1948, ""),
    ("疤面疑云", "Hollow Triumph", 1948, ""),
    ("卑劣交易", "Raw Deal", 1948, ""),
    ("金发冰人", "Blonde Ice", 1948, ""),
    ("金钱疯狂", "Money Madness", 1948, ""),
    ("公开的秘密", "Open Secret", 1948, ""),
    ("假释公司", "Parole, Inc.", 1948, ""),
    ("内心圣所", "Inner Sanctum", 1948, ""),
    ("拼图疑云", "Jigsaw", 1949, ""),
    ("冲击", "Impact", 1949, ""),
    ("泪已太迟", "Too Late for Tears", 1949, ""),
    ("落网", "Trapped", 1949, ""),
    ("纽约港", "Port of New York", 1949, ""),
    ("死亡漩涡", "D.O.A.", 1950, ""),
    ("逃亡女", "Woman on the Run", 1950, ""),
    ("流沙", "Quicksand", 1950, ""),
    ("徘徊者", "The Prowler", 1951, ""),
    ("惊惧骤起", "Cause for Alarm!", 1951, ""),
    ("堪萨斯城机密", "Kansas City Confidential", 1952, ""),
    ("搭车客", "The Hitch-Hiker", 1953, ""),
    ("重婚者", "The Bigamist", 1953, ""),
    ("邪恶女人", "Wicked Woman", 1953, ""),
    ("步步惊魂", "Shield for Murder", 1954, ""),
    ("大枭雄", "The Big Combo", 1955, ""),
    ("纽约机密", "New York Confidential", 1955, ""),
    ("请杀了我", "Please Murder Me", 1956, ""),
    # —— 威尔斯与 50-60 年代名作 ——
    ("陌生人", "The Stranger", 1946, ""),
    ("麦克白", "Macbeth", 1948, ""),
    ("奥赛罗", "Othello", 1951, ""),
    ("阿卡丁先生", "Mr. Arkadin", 1955, ""),
    ("审判", "The Trial", 1962, ""),
    ("大鼻子情圣", "Cyrano de Bergerac", 1950, ""),
    ("杰基·罗宾逊传", "The Jackie Robinson Story", 1950, ""),
    ("从军乐", "At War with the Army", 1950, ""),
    ("皇家婚礼", "Royal Wedding", 1951, ""),
    ("父亲的小红利", "Father's Little Dividend", 1951, ""),
    ("画山", "The Painted Hills", 1951, ""),
    ("巴厘之路", "Road to Bali", 1952, ""),
    ("乞力马扎罗的雪", "The Snows of Kilimanjaro", 1952, ""),
    ("杰克与豆茎", "Jack and the Beanstalk", 1952, ""),
    ("击败魔鬼", "Beat the Devil", 1953, ""),
    ("大地之盐", "Salt of the Earth", 1954, ""),
    ("突然", "Suddenly", 1954, ""),
    ("亡命飞车", "The Fast and the Furious", 1954, ""),
    ("魂断巴黎", "The Last Time I Saw Paris", 1954, ""),
    ("独眼龙", "One-Eyed Jacks", 1961, ""),
    ("谜中谜", "Charade", 1963, "charade-stanley-donen-1963-cary-grant-audrey-hepburn-comedie-policiere"),
    ("麦克林托克", "McLintock!", 1963, ""),
    # —— 系列侦探（福尔摩斯 / 陈查理 / 黄先生）——
    ("福尔摩斯与秘密武器", "Sherlock Holmes and the Secret Weapon", 1942, ""),
    ("绿衣女子", "The Woman in Green", 1945, ""),
    ("恐怖之夜", "Terror by Night", 1946, ""),
    ("盛装杀人", "Dressed to Kill", 1946, ""),
    ("中国猫", "The Chinese Cat", 1944, ""),
    ("红龙", "The Red Dragon", 1945, ""),
    ("上海眼镜蛇", "The Shanghai Cobra", 1945, ""),
    ("猩红线索", "The Scarlet Clue", 1945, ""),
    ("黄先生探案", "Mr. Wong, Detective", 1938, ""),
    ("黄先生之谜", "The Mystery of Mr. Wong", 1939, ""),
    ("唐人街的黄先生", "Mr. Wong in Chinatown", 1939, ""),
    ("致命时刻", "The Fatal Hour", 1940, ""),
    # —— 恐怖 / 科幻 ——
    ("白僵尸", "White Zombie", 1932, ""),
    ("吸血蝙蝠", "The Vampire Bat", 1933, ""),
    ("夜半尖叫", "A Shriek in the Night", 1933, ""),
    ("鬼魅行走", "The Ghost Walks", 1934, ""),
    ("神秘之屋", "House of Mystery", 1934, ""),
    ("判处活命", "Condemned to Live", 1935, ""),
    ("僵尸的反叛", "Revolt of the Zombies", 1936, ""),
    ("无赖酒馆", "The Rogues Tavern", 1936, ""),
    ("魔鬼蝙蝠", "The Devil Bat", 1940, ""),
    ("猿人", "The Ape", 1940, ""),
    ("隐形鬼", "Invisible Ghost", 1941, ""),
    ("僵尸之王", "King of the Zombies", 1941, ""),
    ("黑龙", "Black Dragons", 1942, ""),
    ("尸体失踪案", "The Corpse Vanishes", 1942, ""),
    ("午夜鲍厄里", "Bowery at Midnight", 1942, ""),
    ("疯狂怪物", "The Mad Monster", 1942, ""),
    ("死人行走", "Dead Men Walk", 1943, ""),
    ("蓝胡子", "Bluebeard", 1944, ""),
    ("巫毒人", "Voodoo Man", 1944, ""),
    ("怪物制造者", "The Monster Maker", 1944, ""),
    ("雾岛", "Fog Island", 1945, ""),
    ("沼泽扼杀者", "Strangler of the Swamp", 1946, ""),
    ("吓死人", "Scared to Death", 1947, ""),
    ("火箭飞船X-M", "Rocketship X-M", 1950, ""),
    ("未知世界", "Unknown World", 1951, ""),
    ("失陷大陆", "Lost Continent", 1951, ""),
    ("月球基地计划", "Project Moonbase", 1953, ""),
    ("机器怪兽", "Robot Monster", 1953, ""),
    ("月球猫女", "Cat-Women of the Moon", 1953, ""),
    ("太空杀手", "Killers from Space", 1954, ""),
    ("不灭人魔", "Indestructible Man", 1956, ""),
    ("尖叫头骨", "The Screaming Skull", 1958, ""),
    ("日魔", "The Hideous Sun Demon", 1958, ""),
    ("导弹飞月", "Missile to the Moon", 1958, ""),
    ("闹鬼屋惊魂", "Terror in the Haunted House", 1958, ""),
    ("猛鬼屋", "House on Haunted Hill", 1959, ""),
    ("蝙蝠", "The Bat", 1959, ""),
    ("杀人鼩", "The Killer Shrews", 1959, ""),
    ("巨型吉拉怪兽", "The Giant Gila Monster", 1959, ""),
    ("太空少年", "Teenagers from Outer Space", 1959, ""),
    ("外太空九号计划", "Plan 9 from Outer Space", 1959, "774-plan-9-from-outer-space"),
    ("一桶血", "A Bucket of Blood", 1959, ""),
    ("黄蜂女", "The Wasp Woman", 1959, ""),
    ("巨蛭之袭", "Attack of the Giant Leeches", 1959, ""),
    ("恐怖小店", "The Little Shop of Horrors", 1960, "Little_ShopOf_Horrors.avi"),
    ("时空屏障", "Beyond the Time Barrier", 1960, ""),
    ("神奇透明人", "The Amazing Transparent Man", 1960, ""),
    ("地球最后的女人", "Last Woman on Earth", 1960, ""),
    ("闹鬼海怪", "Creature from the Haunted Sea", 1961, ""),
    ("夜潮", "Night Tide", 1961, ""),
    ("恶魔之手", "The Devil's Hand", 1961, ""),
    ("灵魂狂欢节", "Carnival of Souls", 1962, "carnival_of_souls"),
    ("不死之脑", "The Brain That Wouldn't Die", 1962, ""),
    ("疯癫13", "Dementia 13", 1963, ""),
    ("恐怖古堡", "The Terror", 1963, ""),
    ("虐待狂", "The Sadist", 1963, ""),
    ("地球最后一人", "The Last Man on Earth", 1964, ""),
    ("圣诞老人征服火星人", "Santa Claus Conquers the Martians", 1964, ""),
    ("活死人之夜", "Night of the Living Dead", 1968, "Night.Of.The.Living.Dead_1080p"),
    # —— 西部片（约翰·韦恩 Lone Star 系列等）——
    ("命运骑士", "Riders of Destiny", 1933, ""),
    ("山艾树小径", "Sagebrush Trail", 1933, ""),
    ("幸运德州人", "The Lucky Texan", 1934, ""),
    ("蓝钢", "Blue Steel", 1934, ""),
    ("犹他来客", "The Man from Utah", 1934, ""),
    ("兰迪独行", "Randy Rides Alone", 1934, ""),
    ("执星者", "The Star Packer", 1934, ""),
    ("小径尽头", "The Trail Beyond", 1934, ""),
    ("无法边境", "The Lawless Frontier", 1934, ""),
    ("亚利桑那天空下", "'Neath the Arizona Skies", 1934, ""),
    ("德州恐怖", "Texas Terror", 1935, ""),
    ("彩虹谷", "Rainbow Valley", 1935, ""),
    ("沙漠小径", "The Desert Trail", 1935, ""),
    ("黎明骑士", "The Dawn Rider", 1935, ""),
    ("天堂峡谷", "Paradise Canyon", 1935, ""),
    ("西进英豪", "Westward Ho", 1935, ""),
    ("圣塔菲小道", "Santa Fe Trail", 1940, ""),
    ("阿比林镇", "Abilene Town", 1946, ""),
    ("天使与恶徒", "Angel and the Badman", 1947, ""),
    ("复仇谷", "Vengeance Valley", 1951, ""),
    ("大红树", "The Big Trees", 1952, ""),
    ("堪萨斯太平洋", "Kansas Pacific", 1953, ""),
    ("黎明之怒", "Rage at Dawn", 1955, ""),
]
CLASSICS = [{"title": t, "orig": o, "year": str(y), "ia": i} for t, o, y, i in CLASSICS_RAW]


def tmdb(path, **params):
    params["api_key"] = TMDB_KEY
    params.setdefault("language", "zh-CN")
    r = requests.get(API + path, params=params, headers=HEADERS, timeout=20)
    r.raise_for_status()
    return r.json()


def fetch_pages(path, pages, **extra):
    """翻页抓取一个 TMDB 列表的原始结果，最多 pages 页。"""
    out, page = [], 1
    while page <= pages:
        p = {"page": page}
        p.update(extra)
        js = tmdb(path, **p)
        res = js.get("results") or []
        out.extend(res)
        if not res or page >= (js.get("total_pages") or 1):
            break
        page += 1
        time.sleep(0.15)
    return out


def to_item(m, rank):
    """把 TMDB 影片对象转成前端用的结构。"""
    pp = m.get("poster_path")
    mid = m.get("id")
    va = m.get("vote_average")
    return {
        "rank": rank,
        "title": m.get("title") or m.get("original_title") or "",
        "orig": m.get("original_title"),
        "year": (m.get("release_date") or "")[:4] or None,
        "rating": round(float(va), 1) if va else None,
        "votes": m.get("vote_count"),
        "poster": (IMG + pp) if pp else None,
        "id": mid,
        "link": ("https://www.themoviedb.org/movie/%s" % mid) if mid else None,
    }


def top_rated_weighted(n):
    """高分电影 Top n：贝叶斯加权排序，经典（高分 + 高票）优先。"""
    pool, seen = [], set()
    for m in fetch_pages("/movie/top_rated", POOL_PAGES):
        mid = m.get("id")
        v = m.get("vote_count") or 0
        r = m.get("vote_average")
        if not mid or mid in seen or not r or v < FLOOR_VOTES:
            continue
        seen.add(mid)
        pool.append(m)
    if not pool:
        return []
    C = sum((m.get("vote_average") or 0) for m in pool) / len(pool)   # 候选池平均分

    def wr(m):
        v = m.get("vote_count") or 0
        r = m.get("vote_average") or 0
        return (v / (v + MIN_VOTES)) * r + (MIN_VOTES / (v + MIN_VOTES)) * C

    pool.sort(key=wr, reverse=True)
    return [to_item(m, i + 1) for i, m in enumerate(pool[:n])]


def pick_trailer(videos):
    """从 TMDB videos 里挑一支最合适的 YouTube 预告片：正式预告 > 先导，官方优先，中文加分。"""
    best, score = None, -1
    for v in videos or []:
        if v.get("site") != "YouTube" or not v.get("key"):
            continue
        s = {"Trailer": 4, "Teaser": 2}.get(v.get("type"), 0)
        if v.get("official"):
            s += 2
        if (v.get("iso_639_1") or "") == "zh":
            s += 1
        if s > score:
            best, score = v["key"], s
    return best


def pick_watch(results):
    """整理正版观看渠道（TMDB × JustWatch）：按地区聚合平台名，订阅 > 免费 > 租售。"""
    out = []
    for r in WATCH_REGIONS:
        d = (results or {}).get(r) or {}
        names = []
        for k in ("flatrate", "free", "ads", "rent", "buy"):
            for p in d.get(k) or []:
                n = p.get("provider_name")
                if n and n not in names:
                    names.append(n)
        if names:
            out.append({"region": r, "names": names[:6], "link": d.get("link")})
    return out


def enrich_play(items):
    """为每部片补预告片 YouTube key 与正版观看渠道；单片失败只影响自己。"""
    def one(it):
        if not it.get("id"):
            return
        try:
            js = tmdb("/movie/%s" % it["id"],
                      append_to_response="videos,watch/providers",
                      include_video_language="zh,en,null")
            t = pick_trailer((js.get("videos") or {}).get("results"))
            if t:
                it["trailer"] = t
            w = pick_watch((js.get("watch/providers") or {}).get("results"))
            if w:
                it["watch"] = w
        except Exception as e:
            print("[..] 详情失败 #%s：%s" % (it.get("id"), str(e)[:60]))
    with ThreadPoolExecutor(max_workers=8) as ex:
        list(ex.map(one, items))


def ia_get(path, **params):
    err = None
    for i in range(2):          # metadata API 偶发超时，重试一次
        try:
            r = requests.get("https://archive.org" + path, params=params, headers=HEADERS, timeout=25)
            r.raise_for_status()
            return r.json()
        except Exception as e:
            err = e
            time.sleep(1 + i)
    raise err


def _seconds(v):
    """把 Archive 文件时长（"1:23:45" 或秒数字符串）转成秒。"""
    s = str(v or "").strip()
    if not s:
        return 0
    try:
        out = 0.0
        for p in s.split(":"):
            out = out * 60 + float(p)
        return int(out)
    except ValueError:
        return 0


def ia_meta(identifier):
    """Internet Archive 条目元数据：返回 (可播, 标注年份, 最长视频秒数)。"""
    try:
        js = ia_get("/metadata/%s" % identifier)
    except Exception:
        return False, None, 0
    if not isinstance(js, dict) or not js.get("metadata") or js.get("is_dark"):
        return False, None, 0
    md = js["metadata"]
    y = str(md.get("year") or md.get("date") or "")[:4]
    year = int(y) if y.isdigit() else None
    playable, longest = False, 0
    for f in js.get("files") or []:
        if str(f.get("name", "")).lower().endswith((".mp4", ".m4v", ".ogv")):
            playable = True
            longest = max(longest, _seconds(f.get("length")))
    return playable, year, longest


def ia_find(orig, year):
    """按片名搜 Internet Archive 影片区做兜底。挡同名杂项：排除 trailer 条目、
    要求视频 ≥ 40 分钟（挡预告片/剧集单集）、条目标注年份需接近上映年。"""
    try:
        js = ia_get("/advancedsearch.php",
                    q='title:"%s" AND mediatype:movies' % orig,
                    **{"fl[]": "identifier", "sort[]": "downloads desc",
                       "rows": 10, "output": "json"})
        docs = (js.get("response") or {}).get("docs") or []
    except Exception:
        return None
    for d in docs:
        ident = d.get("identifier") or ""
        if not ident or "trailer" in ident.lower():
            continue
        ok, iy, secs = ia_meta(ident)
        # 严格口径：必须有年份且匹配。缺年份的条目宁可放弃——曾出现同名子串碰撞
        # （搜 The Kid 命中 Billy the Kid in Texas）甚至误配到有版权的现代片。
        if not ok or secs < 2400 or iy is None or abs(iy - int(year)) > 2:
            continue
        return ident
    return None


def read_prev_classics():
    """读取上次 data.json 里已验证过的公版片源映射 {(原名, 年份): 条目标识}，
    让搜索解析出的结果在后续构建中直接沿用、免于每晚重搜。"""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            old = json.load(f)
        l = next((x for x in old.get("lists") or [] if x.get("key") == "classics"), None)
        return {((it.get("orig") or it.get("title")), str(it.get("year"))): it["video"]
                for it in (l or {}).get("items") or [] if it.get("video")}
    except Exception:
        return {}


def classics_list(prev):
    """公版经典榜单：并行校验 / 搜寻 Internet Archive 片源（优先沿用上次已验证的标识），
    用 TMDB 补中文片名、海报与评分，最后按加权评分排序取前 CLASSICS_MAX 部。"""
    def resolve(c):
        year = int(c["year"])
        # 手工固化的标识可信度高：存在、可播、年份不冲突（缺年份不算冲突）即可
        if c["ia"] and "trailer" not in c["ia"].lower():
            ok, iy, _ = ia_meta(c["ia"])
            if ok and (iy is None or abs(iy - year) <= 2):
                return c["ia"]
        # 上次搜索沿用的标识按严格口径复核（必须有年份且匹配、片长达标），坏源自然淘汰
        p = prev.get((c["orig"], c["year"]))
        if p and p != c["ia"] and "trailer" not in p.lower():
            ok, iy, secs = ia_meta(p)
            if ok and secs >= 2400 and iy is not None and abs(iy - year) <= 2:
                return p
        return ia_find(c["orig"], c["year"])

    def build_one(c):
        ident = resolve(c)
        if not ident:
            print("[..] 公版片源未找到，剔除：%s" % c["orig"])
            return None
        it = {
            "rank": 0,
            "title": c["title"], "orig": c["orig"], "year": c["year"],
            "rating": None, "votes": None,
            "poster": "https://archive.org/services/img/%s" % ident,
            "id": None,
            "link": "https://archive.org/details/%s" % ident,
            "video": ident,
        }
        try:
            for m in (tmdb("/search/movie", query=c["orig"]).get("results") or [])[:5]:
                y = (m.get("release_date") or "")[:4]
                if not (y.isdigit() and abs(int(y) - int(c["year"])) <= 2):
                    continue
                it["title"] = m.get("title") or it["title"]
                if m.get("poster_path"):
                    it["poster"] = IMG + m["poster_path"]
                va = m.get("vote_average")
                it["rating"] = round(float(va), 1) if va else None
                it["votes"] = m.get("vote_count")
                it["id"] = m.get("id")
                break
        except Exception as e:
            print("[..] TMDB 检索失败 %s：%s" % (c["orig"], str(e)[:60]))
        return it

    with ThreadPoolExecutor(max_workers=6) as ex:
        items = [it for it in ex.map(build_one, CLASSICS) if it]

    def wr(it):        # 加权评分：票太少的高分不至于霸榜（m=200）
        return ((it.get("votes") or 0) / ((it.get("votes") or 0) + 200.0)) * (it.get("rating") or 0)

    items.sort(key=wr, reverse=True)
    items = items[:CLASSICS_MAX]
    for i, it in enumerate(items):
        it["rank"] = i + 1
    return items


def collect(path, n, region=None):
    """按 TMDB 原始顺序取前 n 部（用于「最新上映」）。"""
    extra = {"region": region} if region else {}
    out = []
    for m in fetch_pages(path, n // 20 + 2, **extra):
        out.append(to_item(m, len(out) + 1))
        if len(out) >= n:
            break
    return out


def build():
    if not TMDB_KEY:
        print("未配置 TMDB_KEY —— 跳过、保留上次 data.json。"
              "请在仓库 Settings → Secrets and variables → Actions 新增名为 TMDB_KEY 的密钥后即自动生效。")
        return

    lists = []
    try:
        top = top_rated_weighted(250)
        if top:
            lists.append({"key": "top", "name": "高分电影 Top 250", "items": top})
            print(f"[OK] 高分 Top 250：{len(top)} 部，#1 {top[0]['title']} ★{top[0]['rating']}")
    except Exception as e:
        print(f"[..] top_rated 失败：{str(e)[:90]}")
    try:
        now = collect("/movie/now_playing", 60, region="US")
        if now:
            lists.append({"key": "popular", "name": "全球最新上映", "items": now})
            print(f"[OK] 最新上映：{len(now)} 部")
    except Exception as e:
        print(f"[..] now_playing 失败：{str(e)[:90]}")

    if not lists:
        print("TMDB 未取到数据（请检查 TMDB_KEY 是否有效），保留上次 data.json，不覆盖。")
        return

    for l in lists:
        enrich_play(l["items"])
        got = sum(1 for it in l["items"] if it.get("trailer"))
        print(f"[OK] {l['name']}：预告片 {got}/{len(l['items'])}")
    try:
        classics = classics_list(read_prev_classics())
        if classics:
            lists.append({"key": "classics", "name": "公版经典 · 免费正片", "items": classics})
            print(f"[OK] 公版经典：{len(classics)}/{len(CLASSICS)} 部（上限 {CLASSICS_MAX}）")
    except Exception as e:
        print(f"[..] 公版经典构建失败：{str(e)[:90]}")

    top = next((l for l in lists if l["key"] == "top"), None)
    rates = [it["rating"] for it in (top["items"] if top else []) if isinstance(it.get("rating"), (int, float))]
    avg = round(sum(rates) / len(rates), 1) if rates else None

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "TMDB · The Movie Database",
        "avgRating": avg,
        "defaultKey": "top",
        "lists": lists,
        "note": ("数据来自 TMDB（The Movie Database）公开 API：高分电影 Top 250（按票数加权排序、经典优先）"
                 "与全球最新上映，含海报与中文片名，每日自动更新。点击海报可在线看官方预告片（YouTube），"
                 "「公版经典」为已进入公有领域的经典电影（含华语老片）、正片由 Internet Archive 提供；"
                 "观看渠道数据来自 TMDB × JustWatch。评分为 TMDB 用户评分，仅供参考。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(lists)} 个榜单，Top 平均分 {avg}")


if __name__ == "__main__":
    build()
