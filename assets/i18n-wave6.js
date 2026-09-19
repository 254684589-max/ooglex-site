/* Ooglex sixth-wave i18n layer.
   Covers the pages the first five rollout waves never reached: Tech Leaders on X,
   StarPupil telescope, Home Value Compass and the two science-explainer labs.
   Reads localStorage["ooglex.language"], translates reviewed UI/runtime strings and
   keeps the original Chinese DOM so switching back is lossless.
   Post bodies, account handles and cited paper titles stay in their original language. */
(function () {
  "use strict";

  var KEY = "ooglex.language";
  var path = (location.pathname || "/").replace(/\/index\.html$/, "/");
  var current = "zh";
  var textOrig = new WeakMap(), textTouched = [];
  var attrOrig = new WeakMap(), attrTouched = [];
  // 比前几波多管一个 alt：望远镜的灯箱图就靠它给读屏用户报出「照片预览」。
  var ATTRS = ["placeholder", "aria-label", "title", "alt"];

  function readLang() {
    try {
      if (window.OoglexI18n && window.OoglexI18n.getLanguage) {
        return window.OoglexI18n.getLanguage() === "en" ? "en" : "zh";
      }
      return localStorage.getItem(KEY) === "en" ? "en" : "zh";
    } catch (e) { return "zh"; }
  }
  function add(dst, src) { Object.keys(src).forEach(function (k) { dst[k] = src[k]; }); }

  var COMMON = {
    "← 返回": "← Back",
    "← 返回首页": "← Back to Home",
    "关闭": "Close",
    "重置": "Reset",
    "重新加载": "Reload",
    "▶ 播放": "▶ Play",
    "⏸ 暂停": "⏸ Pause",
    "🔈 音量": "🔈 Volume",
    "简短答案：": "Short answer: ",
    "📚 参考与延伸阅读": "📚 References & Further Reading"
  };

  /* --------------------------------------------------------- 科技领袖实时动态流
     人名用榜单已有的英文原名，不另行音译；@handle、帖子正文与诊断码保持原文。 */
  var TECH_LEADERS = {
    /* V4.2（2026-09-19 上游改版）：人名、公司、职位与分类逐条取自
       apps/tech-leaders/leaders.json 的 `name_zh`/`name_en`、`company_zh`/`company_en`
       等成对字段，生成而非手译；职位与分类是固定词表，逐条核对过。 */
    "37signals / Ruby on Rails · 37signals / Ruby on Rails": "37signals / Ruby on Rails",
    "37signals / Ruby on Rails · 37signals / Ruby on Rails · 共同所有人 / 创始作者": "37signals / Ruby on Rails · Co-owner / founding author",
    "AI 与机器人研究员": "AI & robotics researcher",
    "AI 研究员": "AI researcher",
    "AI 研究员 / 创始人": "AI researcher / founder",
    "AI 研究负责人": "Head of AI research",
    "AI 高管 / 创业者": "AI executive / entrepreneur",
    "AMD · AMD": "AMD",
    "AMD · AMD · 董事长兼 CEO": "AMD · Chairman & CEO",
    "Affirm · Affirm": "Affirm",
    "Affirm · Affirm · 创始人兼 CEO": "Affirm · Founder & CEO",
    "Airbnb · Airbnb": "Airbnb",
    "Airbnb · Airbnb · 联合创始人兼 CEO": "Airbnb · Co-founder & CEO",
    "Altimeter · Altimeter": "Altimeter",
    "Altimeter · Altimeter · 创始人兼 CEO": "Altimeter · Founder & CEO",
    "Andreessen Horowitz · Andreessen Horowitz": "Andreessen Horowitz",
    "Andreessen Horowitz · Andreessen Horowitz · 联合创始人": "Andreessen Horowitz · Co-founder",
    "Anduril · Anduril": "Anduril",
    "Anduril · Anduril · 创始人": "Anduril · Founder",
    "AngelList · AngelList": "AngelList",
    "AngelList · AngelList · 联合创始人 / 投资人": "AngelList · Co-founder / investor",
    "Anthropic · Anthropic": "Anthropic",
    "Anthropic · Anthropic · 联合创始人兼 CEO": "Anthropic · Co-founder & CEO",
    "Arm · Arm": "Arm",
    "Arm · Arm · CEO": "Arm · CEO",
    "Automattic / WordPress · Automattic / WordPress": "Automattic / WordPress",
    "Automattic / WordPress · Automattic / WordPress · CEO / 联合创始人": "Automattic / WordPress · CEO / co-founder",
    "Benchmark · Benchmark": "Benchmark",
    "Benchmark · Benchmark · 科技投资人": "Benchmark · Technology investor",
    "Block / Twitter · Block / Twitter": "Block / Twitter",
    "Block / Twitter · Block / Twitter · 联合创始人": "Block / Twitter · Co-founder",
    "Box · Box": "Box",
    "Box · Box · 联合创始人兼 CEO": "Box · Co-founder & CEO",
    "CEO / 联合创始人": "CEO / co-founder",
    "CEO / 芯片架构师": "CEO / chip architect",
    "CEO 兼创始人": "CEO & founder",
    "Canva · Canva": "Canva",
    "Canva · Canva · 联合创始人兼 CEO": "Canva · Co-founder & CEO",
    "Cloudflare · Cloudflare": "Cloudflare",
    "Cloudflare · Cloudflare · 联合创始人兼 CEO": "Cloudflare · Co-founder & CEO",
    "Cloudflare · Cloudflare · 联合创始人兼总裁": "Cloudflare · Co-founder & President",
    "Cohere · Cohere": "Cohere",
    "Cohere · Cohere · 联合创始人兼 CEO": "Cohere · Co-founder & CEO",
    "Coinbase · Coinbase": "Coinbase",
    "Coinbase · Coinbase · 联合创始人兼 CEO": "Coinbase · Co-founder & CEO",
    "Covariant / 加州大学伯克利分校": "Covariant / UC Berkeley",
    "Covariant / 加州大学伯克利分校 · Covariant / UC Berkeley": "Covariant / UC Berkeley",
    "Covariant / 加州大学伯克利分校 · Covariant / UC Berkeley · 机器人与 AI 研究员": "Covariant / UC Berkeley · Robotics & AI researcher",
    "CrowdStrike · CrowdStrike": "CrowdStrike",
    "CrowdStrike · CrowdStrike · CEO 兼创始人": "CrowdStrike · CEO & founder",
    "DHH": "David Heinemeier Hansson",
    "DeepLearning.AI / AI Fund · DeepLearning.AI / AI Fund": "DeepLearning.AI / AI Fund",
    "DeepLearning.AI / AI Fund · DeepLearning.AI / AI Fund · 创始人": "DeepLearning.AI / AI Fund · Founder",
    "Dropbox · Dropbox": "Dropbox",
    "Dropbox · Dropbox · 联合创始人兼 CEO": "Dropbox · Co-founder & CEO",
    "Eureka Labs · Eureka Labs": "Eureka Labs",
    "Eureka Labs · Eureka Labs · AI 研究员 / 创始人": "Eureka Labs · AI researcher / founder",
    "Figma · Figma": "Figma",
    "Figma · Figma · 联合创始人兼 CEO": "Figma · Co-founder & CEO",
    "Figure AI · Figure AI": "Figure AI",
    "Figure AI · Figure AI · 创始人兼 CEO": "Figure AI · Founder & CEO",
    "GitHub · GitHub": "GitHub",
    "GitHub · GitHub · 联合创始人": "GitHub · Co-founder",
    "GitLab · GitLab": "GitLab",
    "GitLab · GitLab · 联合创始人": "GitLab · Co-founder",
    "HashiCorp / Ghostty · HashiCorp / Ghostty": "HashiCorp / Ghostty",
    "HashiCorp / Ghostty · HashiCorp / Ghostty · 联合创始人 / 开发者": "HashiCorp / Ghostty · Co-founder / developer",
    "Hugging Face · Hugging Face": "Hugging Face",
    "Hugging Face · Hugging Face · 联合创始人兼 CEO": "Hugging Face · Co-founder & CEO",
    "IBM · IBM": "IBM",
    "IBM · IBM · 董事长兼 CEO": "IBM · Chairman & CEO",
    "Instagram · Instagram": "Instagram",
    "Instagram · Instagram · 负责人": "Instagram · Lead",
    "Khosla Ventures · Khosla Ventures": "Khosla Ventures",
    "Khosla Ventures · Khosla Ventures · 创始人": "Khosla Ventures · Founder",
    "Lightspark · Lightspark": "Lightspark",
    "Lightspark · Lightspark · 联合创始人兼 CEO": "Lightspark · Co-founder & CEO",
    "LinkedIn / Greylock · LinkedIn / Greylock": "LinkedIn / Greylock",
    "LinkedIn / Greylock · LinkedIn / Greylock · 联合创始人 / 投资人": "LinkedIn / Greylock · Co-founder / investor",
    "Meta · Meta": "Meta",
    "Meta · Meta · CTO": "Meta · CTO",
    "Meta · Meta · 创始人兼 CEO": "Meta · Founder & CEO",
    "Meta 超级智能团队": "Meta Superintelligence",
    "Meta 超级智能团队 · Meta Superintelligence": "Meta Superintelligence",
    "Meta 超级智能团队 · Meta Superintelligence · AI 高管 / 创业者": "Meta Superintelligence · AI executive / entrepreneur",
    "Nest · Nest": "Nest",
    "Nest · Nest · 创始人": "Nest · Founder",
    "OpenAI · OpenAI": "OpenAI",
    "OpenAI · OpenAI · 总裁兼联合创始人": "OpenAI · President & co-founder",
    "OpenAI · OpenAI · 联合创始人兼 CEO": "OpenAI · Co-founder & CEO",
    "Palo Alto Networks · Palo Alto Networks": "Palo Alto Networks",
    "Palo Alto Networks · Palo Alto Networks · 董事长兼 CEO": "Palo Alto Networks · Chairman & CEO",
    "Perplexity · Perplexity": "Perplexity",
    "Perplexity · Perplexity · 联合创始人兼 CEO": "Perplexity · Co-founder & CEO",
    "Reddit / Seven Seven Six · Reddit / Seven Seven Six": "Reddit / Seven Seven Six",
    "Reddit / Seven Seven Six · Reddit / Seven Seven Six · 联合创始人 / 投资人": "Reddit / Seven Seven Six · Co-founder / investor",
    "Relativity Space · Relativity Space": "Relativity Space",
    "Relativity Space · Relativity Space · 联合创始人": "Relativity Space · Co-founder",
    "Replit · Replit": "Replit",
    "Replit · Replit · 创始人兼 CEO": "Replit · Founder & CEO",
    "Robinhood · Robinhood": "Robinhood",
    "Robinhood · Robinhood · 联合创始人兼 CEO": "Robinhood · Co-founder & CEO",
    "Safe Superintelligence · Safe Superintelligence": "Safe Superintelligence",
    "Safe Superintelligence · Safe Superintelligence · 联合创始人": "Safe Superintelligence · Co-founder",
    "Salesforce · Salesforce": "Salesforce",
    "Salesforce · Salesforce · 董事长兼 CEO": "Salesforce · Chairman & CEO",
    "ServiceNow · ServiceNow": "ServiceNow",
    "ServiceNow · ServiceNow · 董事长兼 CEO": "ServiceNow · Chairman & CEO",
    "Shopify · Shopify": "Shopify",
    "Shopify · Shopify · 联合创始人兼 CEO": "Shopify · Co-founder & CEO",
    "Sierra / OpenAI · Sierra / OpenAI": "Sierra / OpenAI",
    "Sierra / OpenAI · Sierra / OpenAI · 联合创始人兼 CEO / 董事": "Sierra / OpenAI · Co-founder & CEO / board member",
    "Slack · Slack": "Slack",
    "Slack · Slack · 联合创始人": "Slack · Co-founder",
    "Social Capital · Social Capital": "Social Capital",
    "Social Capital · Social Capital · 创始人兼 CEO": "Social Capital · Founder & CEO",
    "Spotify / Prima Materia · Spotify / Prima Materia": "Spotify / Prima Materia",
    "Spotify / Prima Materia · Spotify / Prima Materia · 创始人": "Spotify / Prima Materia · Founder",
    "Stripe · Stripe": "Stripe",
    "Stripe · Stripe · 联合创始人兼 CEO": "Stripe · Co-founder & CEO",
    "Telegram · Telegram": "Telegram",
    "Telegram · Telegram · 创始人兼 CEO": "Telegram · Founder & CEO",
    "Tenstorrent · Tenstorrent": "Tenstorrent",
    "Tenstorrent · Tenstorrent · CEO / 芯片架构师": "Tenstorrent · CEO / chip architect",
    "Thinking Machines Lab · Thinking Machines Lab": "Thinking Machines Lab",
    "Thinking Machines Lab · Thinking Machines Lab · 创始人兼 CEO": "Thinking Machines Lab · Founder & CEO",
    "Uber · Uber": "Uber",
    "Uber · Uber · CEO": "Uber · CEO",
    "Union Square Ventures · Union Square Ventures": "Union Square Ventures",
    "Union Square Ventures · Union Square Ventures · 联合创始人": "Union Square Ventures · Co-founder",
    "VC": "Venture Capital",
    "Vercel · Vercel": "Vercel",
    "Vercel · Vercel · 创始人兼 CEO": "Vercel · Founder & CEO",
    "Vue.js · Vue.js": "Vue.js",
    "Vue.js · Vue.js · 创始作者": "Vue.js · Founding author",
    "World Labs / 斯坦福大学": "World Labs / Stanford",
    "World Labs / 斯坦福大学 · World Labs / Stanford": "World Labs / Stanford",
    "World Labs / 斯坦福大学 · World Labs / Stanford · 联合创始人兼 CEO": "World Labs / Stanford · Co-founder & CEO",
    "Y Combinator · Y Combinator": "Y Combinator",
    "Y Combinator · Y Combinator · 总裁兼 CEO": "Y Combinator · President & CEO",
    "Y Combinator · Y Combinator · 联合创始人": "Y Combinator · Co-founder",
    "YouTube · YouTube": "YouTube",
    "YouTube · YouTube · CEO": "YouTube · CEO",
    "Zoom · Zoom": "Zoom",
    "Zoom · Zoom · 创始人兼 CEO": "Zoom · Founder & CEO",
    "丹尼尔·埃克": "Daniel Ek",
    "乔治·库尔茨": "George Kurtz",
    "云计算": "Cloud",
    "云计算 / 企业科技": "Cloud & Enterprise Technology",
    "云计算 / 企业科技 · Cloud & Enterprise Technology": "Cloud & Enterprise Technology",
    "云计算 / 企业科技 · Cloud & Enterprise Technology · 科技高管": "Cloud & Enterprise Technology · Technology executive",
    "Helix 数字基础设施 · Helix Digital Infrastructure": "Helix Digital Infrastructure",
    "Helix 数字基础设施 · Helix Digital Infrastructure · 联合创始人兼 CEO": "Helix Digital Infrastructure · Co-founder & CEO",
    "亚伦·莱维": "Aaron Levie",
    "亚历克西斯·奥哈尼安": "Alexis Ohanian",
    "亚历山大·王": "Alexandr Wang",
    "亚当·塞利普斯基": "Adam Selipsky",
    "亚当·莫塞里": "Adam Mosseri",
    "亚马逊": "Amazon",
    "亚马逊 / 蓝色起源": "Amazon / Blue Origin",
    "亚马逊 / 蓝色起源 · Amazon / Blue Origin": "Amazon / Blue Origin",
    "亚马逊 / 蓝色起源 · Amazon / Blue Origin · 创始人": "Amazon / Blue Origin · Founder",
    "亚马逊 · Amazon": "Amazon",
    "亚马逊 · Amazon · CEO": "Amazon · CEO",
    "亚马逊 · Amazon · CTO": "Amazon · CTO",
    "以太坊": "Ethereum",
    "以太坊 · Ethereum": "Ethereum",
    "以太坊 · Ethereum · 联合创始人": "Ethereum · Co-founder",
    "伊利亚·苏茨克维": "Ilya Sutskever",
    "保罗·格雷厄姆": "Paul Graham",
    "克莱芒·德朗格": "Clément Delangue",
    "克里斯·万斯特拉斯": "Chris Wanstrath",
    "克里斯托夫·富凯": "Christophe Fouquet",
    "克里斯蒂亚诺·阿蒙": "Cristiano Amon",
    "共同所有人 / 创始作者": "Co-owner / founding author",
    "凯文·罗斯": "Kevin Rose",
    "切尔西·芬恩": "Chelsea Finn",
    "创业者 / 投资人": "Entrepreneur / investor",
    "创始人": "Founder",
    "创始人 / CEO": "Founder / CEO",
    "创始人兼 CEO": "Founder & CEO",
    "创始作者": "Founding author",
    "前 CEO / 投资人": "Former CEO / investor",
    "加州大学伯克利分校": "UC Berkeley",
    "加州大学伯克利分校 · UC Berkeley": "UC Berkeley",
    "加州大学伯克利分校 · UC Berkeley · 机器人与 AI 研究员": "UC Berkeley · Robotics & AI researcher",
    "加里·谭": "Garry Tan",
    "劳氏": "Lowe's",
    "劳氏 · Lowe's": "Lowe's",
    "劳氏 · Lowe's · 董事长、总裁兼 CEO": "Lowe's · Chairman, President & CEO",
    "医疗": "Healthcare",
    "半导体 / AI 硬件": "Semiconductors / AI Hardware",
    "半导体 / AI 硬件 · Semiconductors / AI Hardware": "Semiconductors / AI Hardware",
    "半导体 / AI 硬件 · Semiconductors / AI Hardware · 芯片架构师": "Semiconductors / AI Hardware · Chip architect",
    "半导体行业": "Semiconductors",
    "半导体行业 · Semiconductors": "Semiconductors",
    "半导体行业 · Semiconductors · 科技高管": "Semiconductors · Technology executive",
    "博通": "Broadcom",
    "博通 · Broadcom": "Broadcom",
    "博通 · Broadcom · CEO": "Broadcom · CEO",
    "吉列尔莫·劳赫": "Guillermo Rauch",
    "吉姆·凯勒": "Jim Keller",
    "吉姆·法利": "Jim Farley",
    "吴恩达": "Andrew Ng",
    "商业航天": "Commercial Spaceflight",
    "商业航天 · Commercial Spaceflight": "Commercial Spaceflight",
    "商业航天 · Commercial Spaceflight · 航天企业家": "Commercial Spaceflight · Space entrepreneur",
    "埃里克·施密特": "Eric Schmidt",
    "大卫·海涅迈尔·汉松": "David Heinemeier Hansson",
    "大卫·马库斯": "David Marcus",
    "孙正义": "Masayoshi Son",
    "安德烈·卡帕西": "Andrej Karpathy",
    "安德鲁·博斯沃思": "Andrew Bosworth",
    "安迪·贾西": "Andy Jassy",
    "小米": "Xiaomi",
    "小米 · Xiaomi": "Xiaomi",
    "小米 · Xiaomi · 创始人兼 CEO": "Xiaomi · Founder & CEO",
    "尤雨溪": "Evan You",
    "尼克什·阿罗拉": "Nikesh Arora",
    "尼尔·莫汉": "Neal Mohan",
    "工业": "Industrials",
    "布拉德·格斯特纳": "Brad Gerstner",
    "布莱恩·切斯基": "Brian Chesky",
    "布莱恩·阿姆斯特朗": "Brian Armstrong",
    "布雷特·泰勒": "Bret Taylor",
    "布雷特·阿德科克": "Brett Adcock",
    "帕尔默·拉奇": "Palmer Luckey",
    "帕特·基辛格": "Pat Gelsinger",
    "帕特里克·科里森": "Patrick Collison",
    "帕维尔·杜罗夫": "Pavel Durov",
    "弗拉德·特内夫": "Vlad Tenev",
    "弗雷德·威尔逊": "Fred Wilson",
    "彼得·贝克": "Peter Beck",
    "彼得·阿比尔": "Pieter Abbeel",
    "微软": "Microsoft",
    "微软 AI": "Microsoft AI",
    "微软 AI · Microsoft AI": "Microsoft AI",
    "微软 AI · Microsoft AI · CEO": "Microsoft AI · CEO",
    "微软 · Microsoft": "Microsoft",
    "微软 · Microsoft · 董事长兼 CEO": "Microsoft · Chairman & CEO",
    "德米斯·哈萨比斯": "Demis Hassabis",
    "德鲁·休斯顿": "Drew Houston",
    "思科": "Cisco",
    "思科 · Cisco": "Cisco",
    "思科 · Cisco · 董事长兼 CEO": "Cisco · Chairman & CEO",
    "总裁兼 CEO": "President & CEO",
    "总裁兼联合创始人": "President & co-founder",
    "戴尔科技": "Dell Technologies",
    "戴尔科技 · Dell Technologies": "Dell Technologies",
    "戴尔科技 · Dell Technologies · 董事长兼 CEO": "Dell Technologies · Chairman & CEO",
    "托尼·法德尔": "Tony Fadell",
    "托比亚斯·吕特克": "Tobias Lütke",
    "托里·布鲁诺": "Tory Bruno",
    "投资人 / 前 GitHub CEO": "Investor / former GitHub CEO",
    "拉贾·科杜里": "Raja Koduri",
    "斯图尔特·巴特菲尔德": "Stewart Butterfield",
    "斯坦福大学": "Stanford",
    "斯坦福大学 · Stanford": "Stanford",
    "斯坦福大学 · Stanford · AI 与机器人研究员": "Stanford · AI & robotics researcher",
    "机器人与 AI 研究员": "Robotics & AI researcher",
    "机器人产业": "Robotics",
    "机器人产业 · Robotics": "Robotics",
    "机器人产业 · Robotics · 机器人学家 / 创业者": "Robotics · Roboticist / entrepreneur",
    "机器人公司": "Robotics company",
    "机器人学家 / 创业者": "Roboticist / entrepreneur",
    "李飞飞": "Fei-Fei Li",
    "杨立昆": "Yann LeCun",
    "杰克·多西": "Jack Dorsey",
    "杰夫·贝索斯": "Jeff Bezos",
    "杰夫·迪恩": "Jeff Dean",
    "查克·罗宾斯": "Chuck Robbins",
    "查马斯·帕里哈皮蒂亚": "Chamath Palihapitiya",
    "格雷格·布罗克曼": "Greg Brockman",
    "桑杰·梅赫罗特拉": "Sanjay Mehrotra",
    "桑达尔·皮查伊": "Sundar Pichai",
    "梅拉妮·珀金斯": "Melanie Perkins",
    "比尔·格利": "Bill Gurley",
    "比尔·麦克德莫特": "Bill McDermott",
    "汤姆·普雷斯顿-维尔纳": "Tom Preston-Werner",
    "汽车": "Automotive",
    "波士顿动力": "Boston Dynamics",
    "波士顿动力 · Boston Dynamics": "Boston Dynamics",
    "波士顿动力 · Boston Dynamics · 机器人公司": "Boston Dynamics · Robotics company",
    "消费零售": "Consumer & Retail",
    "火箭实验室": "Rocket Lab",
    "火箭实验室 · Rocket Lab": "Rocket Lab",
    "火箭实验室 · Rocket Lab · 创始人兼 CEO": "Rocket Lab · Founder & CEO",
    "特斯拉 / SpaceX / xAI / X": "Tesla / SpaceX / xAI / X",
    "特斯拉 / SpaceX / xAI / X · Tesla / SpaceX / xAI / X": "Tesla / SpaceX / xAI / X",
    "特斯拉 / SpaceX / xAI / X · Tesla / SpaceX / xAI / X · 创始人 / CEO": "Tesla / SpaceX / xAI / X · Founder / CEO",
    "玛丽·博拉": "Mary Barra",
    "福特": "Ford",
    "福特 · Ford": "Ford",
    "福特 · Ford · CEO": "Ford · CEO",
    "科技创业 / 投资": "Technology / Investing",
    "科技创业 / 投资 · Technology / Investing": "Technology / Investing",
    "科技创业 / 投资 · Technology / Investing · 创业者 / 投资人": "Technology / Investing · Entrepreneur / investor",
    "科技投资": "Technology Investing",
    "科技投资 · Technology Investing": "Technology Investing",
    "科技投资 · Technology Investing · 投资人 / 前 GitHub CEO": "Technology Investing · Investor / former GitHub CEO",
    "科技投资人": "Technology investor",
    "科技高管": "Technology executive",
    "穆斯塔法·苏莱曼": "Mustafa Suleyman",
    "米切尔·哈希莫托": "Mitchell Hashimoto",
    "米拉·穆拉蒂": "Mira Murati",
    "米歇尔·扎特林": "Michelle Zatlyn",
    "纳斯达克": "Nasdaq",
    "纳斯达克 · Nasdaq": "Nasdaq",
    "纳斯达克 · Nasdaq · 董事长兼 CEO": "Nasdaq · Chairman & CEO",
    "纳特·弗里德曼": "Nat Friedman",
    "纳瓦尔·拉维坎特": "Naval Ravikant",
    "纽约大学": "NYU",
    "纽约大学 · NYU": "NYU",
    "纽约大学 · NYU · AI 研究员": "NYU · AI researcher",
    "维塔利克·布特林": "Vitalik Buterin",
    "维尔纳·沃格尔斯": "Werner Vogels",
    "维诺德·科斯拉": "Vinod Khosla",
    "网络安全": "Cybersecurity",
    "罗德尼·布鲁克斯": "Rodney Brooks",
    "美光科技": "Micron",
    "美光科技 · Micron": "Micron",
    "美光科技 · Micron · CEO": "Micron · CEO",
    "联合创始人": "Co-founder",
    "联合创始人 / 开发者": "Co-founder / developer",
    "联合创始人 / 投资人": "Co-founder / investor",
    "联合创始人兼 CEO": "Co-founder & CEO",
    "联合创始人兼 CEO / 董事": "Co-founder & CEO / board member",
    "联合创始人兼总裁": "Co-founder & President",
    "联合发射联盟": "United Launch Alliance",
    "联合发射联盟 · United Launch Alliance": "United Launch Alliance",
    "联合发射联盟 · United Launch Alliance · CEO": "United Launch Alliance · CEO",
    "能源": "Energy",
    "航天企业家": "Space entrepreneur",
    "航空航天": "Aerospace",
    "艾丹·戈麦斯": "Aidan Gomez",
    "艾伯乐": "Albert Bourla",
    "芯片": "Semiconductors",
    "芯片架构师": "Chip architect",
    "苏姿丰": "Lisa Su",
    "英伟达": "NVIDIA",
    "英伟达 · NVIDIA": "NVIDIA",
    "英伟达 · NVIDIA · 创始人兼 CEO": "NVIDIA · Founder & CEO",
    "英特尔": "Intel",
    "英特尔 · Intel": "Intel",
    "英特尔 · Intel · CEO": "Intel · CEO",
    "苹果": "Apple",
    "苹果 · Apple": "Apple",
    "苹果 · Apple · CEO": "Apple · CEO",
    "萨姆·奥尔特曼": "Sam Altman",
    "萨提亚·纳德拉": "Satya Nadella",
    "董事长、总裁兼 CEO": "Chairman, President & CEO",
    "董事长兼 CEO": "Chairman & CEO",
    "蒂姆·埃利斯": "Tim Ellis",
    "蒂姆·库克": "Tim Cook",
    "袁征": "Eric Yuan",
    "西德·西布兰迪": "Sid Sijbrandij",
    "谢尔盖·莱文": "Sergey Levine",
    "谷歌": "Google",
    "谷歌 / Alphabet": "Google / Alphabet",
    "谷歌 / Alphabet · Google / Alphabet": "Google / Alphabet",
    "谷歌 / Alphabet · Google / Alphabet · CEO": "Google / Alphabet · CEO",
    "谷歌 / 科技投资": "Google / Technology Investing",
    "谷歌 / 科技投资 · Google / Technology Investing": "Google / Technology Investing",
    "谷歌 / 科技投资 · Google / Technology Investing · 前 CEO / 投资人": "Google / Technology Investing · Former CEO / investor",
    "谷歌 DeepMind": "Google DeepMind",
    "谷歌 DeepMind · Google DeepMind": "Google DeepMind",
    "谷歌 DeepMind · Google DeepMind · 联合创始人兼 CEO": "Google DeepMind · Co-founder & CEO",
    "谷歌 · Google": "Google",
    "谷歌 · Google · AI 研究负责人": "Google · Head of AI research",
    "负责人": "Lead",
    "贾里德·艾萨克曼": "Jared Isaacman",
    "软件": "Software",
    "软银集团": "SoftBank Group",
    "软银集团 · SoftBank Group": "SoftBank Group",
    "软银集团 · SoftBank Group · 董事长兼 CEO": "SoftBank Group · Chairman & CEO",
    "辉瑞": "Pfizer",
    "辉瑞 · Pfizer": "Pfizer",
    "辉瑞 · Pfizer · 董事长兼 CEO": "Pfizer · Chairman & CEO",
    "达拉·科斯罗萨西": "Dara Khosrowshahi",
    "达里奥·阿莫代": "Dario Amodei",
    "迈克尔·戴尔": "Michael Dell",
    "迪伦·菲尔德": "Dylan Field",
    "通用汽车": "General Motors",
    "通用汽车 · General Motors": "General Motors",
    "通用汽车 · General Motors · 董事长兼 CEO": "General Motors · Chairman & CEO",
    "里德·霍夫曼": "Reid Hoffman",
    "金融": "Financials",
    "阿姆贾德·马萨德": "Amjad Masad",
    "阿尔温德·克里希纳": "Arvind Krishna",
    "阿拉温德·斯里尼瓦斯": "Aravind Srinivas",
    "阿斯麦": "ASML",
    "阿斯麦 · ASML": "ASML",
    "阿斯麦 · ASML · CEO": "ASML · CEO",
    "阿迪娜·弗里德曼": "Adena Friedman",
    "陈福阳": "Hock Tan",
    "陈福阳 / Broadcom": "Hock Tan / Broadcom",
    "陈立武": "Lip-Bu Tan",
    "陈立武 / Intel": "Lip-Bu Tan / Intel",
    "雷内·哈斯": "Rene Haas",
    "雷军": "Lei Jun",
    "马修·普林斯": "Matthew Prince",
    "马克·安德森": "Marc Andreessen",
    "马克·扎克伯格": "Mark Zuckerberg",
    "马克·贝尼奥夫": "Marc Benioff",
    "马克斯·列夫琴": "Max Levchin",
    "马文·埃里森": "Marvin Ellison",
    "马斯克": "Elon Musk",
    "马特·穆伦维格": "Matt Mullenweg",
    "高通": "Qualcomm",
    "高通 · Qualcomm": "Qualcomm",
    "高通 · Qualcomm · 总裁兼 CEO": "Qualcomm · President & CEO",
    "黄仁勋": "Jensen Huang",
    "科技领袖实时动态流": "Tech Leaders Live Feed",
    "语言说明：": "Language note: ",
    "免费模式展示 X 原文。如需简体中文，可使用 Microsoft Edge / Chrome 网页翻译，或沉浸式翻译等浏览器扩展。":
      "Free mode displays the original X posts. For Simplified Chinese, use Microsoft Edge or Chrome page translation, or a browser translation extension such as Immersive Translate.",

    "聚合全球公司领袖、上市公司 CEO 与创始人的公开 X 动态。":
      "Public X posts from global corporate leaders, listed-company CEOs and founders.",
    "● 免费模式默认开启": "● Free mode on by default",
    "X 官方 Embed · $0 API": "Official X embed · $0 API",
    "免费模式 · 0 X API Credits": "Free mode · 0 X API credits",
    "Free Native Feed · Hard $0 X API": "Free Native Feed · Hard $0 X API",

    "单账号按需加载": "One account loaded on demand",
    "加载更多 10 条": "Load 10 more",

    "免费模式": "Free mode",
    "数据模式 · Credits": "Data mode · credits",
    "数据模式": "Data mode",
    "全部": "All",
    "全部分类": "All categories",
    "标普500 决策者": "S&P 500 decision-makers",
    "待补 0": "0 outstanding",
    "免费模式：": "Free mode: ",
    "数据模式：": "Data mode: ",
    "头像：": "Avatars: ",
    "硬性禁止调用 api.x.com。原生动态流与人物资料只读取公开源和 Ooglex 缓存，不消耗 X API Credits；默认显示最新 10 条，点击“加载更多 10 条”后单次会话最多显示 20 条，不做永久帖子归档；原生公开源不可用时自动回退官方 Embed。":
      "api.x.com is hard-blocked in free mode. Native feeds and profile data use only public sources and Ooglex cache, consuming no X API credits. The latest 10 posts are shown by default; after selecting “Load 10 more”, a session shows at most 20 posts, with no permanent post archive. If native public sources are unavailable the page automatically falls back to the official embed.",
    "仅在你手动切换后调用现有 Cloudflare + X API 后端，可用于 Ooglex 自主渲染、后续翻译、摘要和结构化分析，会消耗 X API Credits。":
      "only after you switch to it manually does the existing Cloudflare + X API backend get called. That enables Ooglex's own rendering, plus later translation, summarisation and structured analysis — and it does consume X API credits.",
    "优先读取公开 X 头像；若第三方头像服务不可用，会自动回退为姓名首字母头像，不影响名单与时间线使用。":
      "the public X avatar is read first; if the third-party avatar service is unavailable it falls back to an initial-letter avatar, which affects neither the roster nor the timeline.",
    "当前网络无法完成 X 官方时间线渲染": "This network cannot render the official X timeline",
    "免费模式本身没有产生 X API 费用。可以重试，或直接打开该账号的 X 原主页。":
      "Free mode itself incurs no X API cost. You can retry, or open the account's X profile directly.",
    "个人公开 X 账号。 · 头像由 Ooglex R2 自托管": "Personal public X account. · Avatar self-hosted on Ooglex R2",
    "© 2026 Ooglex · X 内容版权及账户资料归原发布者与 X 平台所有 · 本页仅作公开内容聚合、导航与嵌入展示 ·":
      "© 2026 Ooglex · X content and account material remain the property of the original posters and the X platform · This page only aggregates, navigates to and embeds public content ·",
    "科技领袖筛选与数据模式": "Leader filters and data mode",
    "搜索姓名、@账号、公司或股票代码…": "Search name, @handle, company or ticker…",
    "科技领袖分类筛选": "Leader category filter",
    "Ooglex 已确认本人公开账号": "Ooglex has verified this is the person's own public account",
    "科技领袖实时动态流": "Tech Leaders Live Feed",
    "优先通过 Ooglex Cloudflare 后端读取科技领袖公开 X 原文并由本站自主渲染；X API 尚未配置时自动退回官方嵌入模式，不影响现有页面.":
      "Reads tech leaders' public X posts through the Ooglex Cloudflare backend and renders them on this site; when the X API is not configured it falls back to the official embed, leaving the existing page untouched.",
    "优先通过 Ooglex Cloudflare 后端读取科技领袖公开 X 原文并由本站自主渲染；X API 尚未配置时自动退回官方嵌入模式，不影响现有页面。":
      "Reads tech leaders' public X posts through the Ooglex Cloudflare backend and renders them on this site; when the X API is not configured it falls back to the official embed, leaving the existing page untouched.",
    "● 最新公开动态": "● Latest public posts",
    "数据源检测中": "Detecting data source",
    "X 官方嵌入 · 备用": "Official X embed · fallback",
    "Ooglex 后端 · X API": "Ooglex backend · X API",
    "15 分钟缓存": "15-minute cache",
    "原文优先": "Original posts first",
    "马斯克": "Elon Musk",
    "黄仁勋 / NVIDIA": "Jensen Huang / NVIDIA",
    "苏姿丰": "Lisa Su",
    "桑达尔·皮查伊": "Sundar Pichai",
    "萨提亚·纳德拉": "Satya Nadella",
    "NVIDIA 官方账号 · 黄仁勋相关动态": "Official NVIDIA account · Jensen Huang coverage",
    /* 「Intel CEO · Intel 官方账号」这类 role 由 ` · ` 分段规则逐段翻，补上后半段。 */
    "Intel 官方账号": "official Intel account",
    "Broadcom 官方账号": "official Broadcom account",
    "ASML 官方账号": "official ASML account",
    "Micron 官方账号": "official Micron account",
    "在 X 打开原主页 ↗": "Open the profile on X ↗",
    "个人公开 X 账号。": "Personal public X account.",
    /* V4.3 的人物备注与头像核验状态：备注逐条取自 leaders.json 的 note 字段，
       核验状态取自 index.html 里 avatarNote 的三个分支。 */
    "现任 NVIDIA 创始人兼 CEO，本人公开 X 账号。": "Founder and CEO of NVIDIA; personal public X account.",
    "本页以 Intel 官方 X 账号作为陈立武相关动态入口。": "This page uses Intel's official X account as the entry point for Lip-Bu Tan coverage.",
    "本页以 Broadcom 官方 X 账号作为陈福阳相关动态入口。": "This page uses Broadcom's official X account as the entry point for Hock Tan coverage.",
    "本页以 ASML 官方 X 账号作为 CEO 相关动态入口。": "This page uses ASML's official X account as the entry point for CEO coverage.",
    "本页以 Micron 官方 X 账号作为 Sanjay Mehrotra 相关动态入口。": "This page uses Micron's official X account as the entry point for Sanjay Mehrotra coverage.",
    "官方 X 账号，用于跟踪 Boston Dynamics 机器人动态。": "Official X account, used to follow Boston Dynamics robotics news.",
    "现任 Ford CEO，本人公开 X 账号。": "CEO of Ford; personal public X account.",
    "现任 Cisco 董事长兼 CEO，本人公开 X 账号。": "Chair and CEO of Cisco; personal public X account.",
    "现任 ServiceNow 董事长兼 CEO，本人公开 X 账号。": "Chair and CEO of ServiceNow; personal public X account.",
    "现任 Lowe's 董事长、总裁兼 CEO，本人公开 X 账号。": "Chair, President and CEO of Lowe's; personal public X account.",
    "现任 CrowdStrike CEO 兼创始人，本人公开 X 账号。": "CEO and co-founder of CrowdStrike; personal public X account.",
    "现任 Palo Alto Networks 董事长兼 CEO，本人公开 X 账号。": "Chair and CEO of Palo Alto Networks; personal public X account.",
    "现任 Pfizer 董事长兼 CEO，本人公开 X 账号。": "Chair and CEO of Pfizer; personal public X account.",
    "现任 General Motors 董事长兼 CEO，本人公开 X 账号。": "Chair and CEO of General Motors; personal public X account.",
    "现任 Nasdaq 董事长兼 CEO，本人公开 X 账号。": "Chair and CEO of Nasdaq; personal public X account.",
    "公开 X 账号。": "Public X account.",
    "头像：X 原版已核验": "Avatar: X original verified",
    "头像：待核验 / 本地兜底": "Avatar: pending verification / local fallback",
    "头像：正在核验 X 原版": "Avatar: verifying the X original",
    "为避免误收录未核验个人账号，本页暂以 NVIDIA 官方 X 账号作为黄仁勋相关动态入口。":
      "To avoid listing an unverified personal account, this page uses NVIDIA's official X account as the entry point for Jensen Huang coverage.",
    "当前无法显示 X 时间线": "The X timeline cannot be shown right now",
    "Ooglex 后端尚未启用 X API，官方嵌入在当前网络/浏览器也没有完成渲染。":
      "The Ooglex backend has no X API enabled yet, and the official embed did not finish rendering in this network or browser.",
    "正在读取 Ooglex 后端": "Reading the Ooglex backend",
    "由 Cloudflare 后端请求 X 数据，浏览器不再直接依赖 X iframe。":
      "The Cloudflare backend requests the X data, so the browser no longer depends on the X iframe.",
    "正在检测 Ooglex 后端数据源": "Detecting the Ooglex backend data source",
    "若 X API 尚未配置，将自动退回现有官方嵌入模式。":
      "If the X API is not configured yet, the page falls back to the existing official embed.",
    "暂无新公开动态": "No new public posts",
    "后端连接正常，但当前没有返回可展示的原创帖子。":
      "The backend responded normally but returned no original posts to show.",
    "查看原文 ↗": "View on X ↗",
    "说明：": "Note: ",
    "本页只接入可核验的公开官方账号。黄仁勋目前在本页使用":
      "This page lists only verifiable public official accounts. Jensen Huang is currently represented here by ",
    "NVIDIA 官方 X 账号 @nvidia": "NVIDIA's official X account @nvidia",
    "作为相关动态入口，避免收录同名或未核验个人账号。X 嵌入组件由第三方直接加载；在无法访问 X 的网络环境下，时间线可能无法显示，此时页面会保留原主页跳转入口。":
      ", so that same-name or unverified personal accounts are not listed. The X embed widget is loaded directly by a third party; on networks that cannot reach X the timeline may not appear, and the page keeps the link to the original profile.",
    "© 2026 Ooglex · X 内容版权及账户资料归原发布者与 X 平台所有 · 本页仅作公开内容导航与嵌入展示":
      "© 2026 Ooglex · X content and account material remain the property of the original posters and the X platform · This page is only a navigation and embed surface for public content"
  };

  /* ------------------------------------------------------------- 星瞳望远镜 */
  var TELESCOPE = {
    "星瞳望远镜": "StarPupil Telescope",
    "StarPupil · 把手机变成强大的数码望远镜": "StarPupil · Turn your phone into a powerful digital telescope",
    "光学 + 数码混合变焦，远景近在眼前": "Hybrid optical + digital zoom brings distant views close",
    "一键拍照保存，内置取景相册": "One-tap capture and save, with a built-in viewfinder gallery",
    "夜视 / 增亮 / 锐化等画质增强": "Night vision, brightening, sharpening and other image enhancements",
    "电子罗盘 · 水平仪 · 网格瞄准辅助": "Digital compass · Spirit level · Grid aiming guides",
    "补光灯、十字准星、全屏沉浸取景": "Fill light, crosshair and full-screen immersive viewfinder",
    "开启望远镜": "Open the telescope",
    "需要允许摄像头权限 · 建议在 HTTPS / 本地环境下使用":
      "Camera permission is required · Best used over HTTPS or locally",
    "数码": "Digital",
    "相册": "Gallery",
    "工具": "Tools",
    "取景工具": "Viewfinder tools",
    "补光灯": "Fill light",
    "网格线": "Grid",
    "准星": "Crosshair",
    "水平仪": "Level",
    "罗盘": "Compass",
    "切换镜头": "Switch camera",
    "画质增强": "Image enhancement",
    "夜视增益": "Night-vision gain",
    "对比度": "Contrast",
    "锐度 / 清晰": "Sharpness",
    "色温暖度": "Colour warmth",
    "原始": "Original",
    "夜视": "Night vision",
    "鲜艳": "Vivid",
    "单色": "Mono",
    "取景相册": "Viewfinder gallery",
    "还没有照片，点击快门按钮开始拍摄 📸": "No photos yet — tap the shutter to start 📸",
    "⬇ 保存": "⬇ Save",
    "🗑 删除": "🗑 Delete",
    "全屏": "Fullscreen",
    "退出": "Exit",
    "放大": "Zoom in",
    "变焦": "Zoom",
    "缩小": "Zoom out",
    "拍照": "Take photo",
    "照片预览": "Photo preview"
  };

  /* --------------------------------------------------------------- 房值罗盘 */
  var HOME_VALUE = {
    "🧭 房值罗盘": "🧭 Home Value Compass",
    "输入地址 · 估一估房屋的价值量级": "Enter an address to estimate a home's order-of-magnitude value",
    "📍 房屋信息": "📍 Property details",
    "中文地址（写得越细，识别越准，如：浙江省杭州市西湖区文三街道××小区）":
      "Address in Chinese (the more detail, the better the match — e.g. 浙江省杭州市西湖区文三街道××小区)",
    "例如：上海市浦东新区张江镇科苑路": "e.g. 上海市浦东新区张江镇科苑路",
    "建筑面积（㎡）": "Floor area (m²)",
    "房龄": "Age of the building",
    "5 年以内（次新）": "Under 5 years (near-new)",
    "5 ~ 15 年": "5–15 years",
    "15 ~ 25 年": "15–25 years",
    "25 年以上（老破小/大）": "Over 25 years (older stock)",
    "装修情况": "Interior finish",
    "豪华装修": "Luxury finish",
    "精装修": "Fully fitted",
    "简单装修": "Basic finish",
    "毛坯": "Bare shell",
    "楼层与电梯": "Floor and lift",
    "电梯房 · 中间楼层": "With lift · middle floor",
    "电梯房 · 一般楼层": "With lift · ordinary floor",
    "楼梯房 · 低楼层": "Walk-up · low floor",
    "楼梯房 · 高楼层": "Walk-up · high floor",
    "加分项（点选）": "Value-adding features (tap to select)",
    "🏫 优质学区": "🏫 Good school district",
    "🚇 地铁 500 米内": "🚇 Metro within 500 m",
    "🌳 公园/江景": "🌳 Park or river view",
    "🛣️ 临高架/铁路": "🛣️ Next to an elevated road or railway",
    "开 始 估 算": "RUN ESTIMATE",
    "🧭 估算结果": "🧭 Estimate",
    "元/㎡（参考区间中值）": "CNY/m² (midpoint of the reference range)",
    "总价约": "Approximate total",
    "⚠️ 重要声明：本结果基于": "⚠️ Important: this result is computed from ",
    "内置静态参考均价 + 经验系数": "built-in static reference averages plus rule-of-thumb coefficients",
    "计算，数据非实时、未必反映当前行情，与真实成交价可能有较大偏差，":
      ". The data is not real-time, may not reflect the current market and can differ substantially from actual transaction prices. It ",
    "不构成任何置业、投资建议": "does not constitute property or investment advice",
    "。买卖房屋请以下方真实渠道的成交数据为准。":
      ". When buying or selling, rely on recorded transaction data from the real channels listed below.",
    "✅ 怎么查真实房价（认真买房看这里）": "✅ How to find real prices (read this if you are actually buying)",
    "看\"成交价\"而非\"挂牌价\"": "Look at closed prices, not asking prices",
    "——贝壳找房、链家 App 可查小区历史成交记录，比挂牌价真实得多。":
      " — the Beike and Lianjia apps list a development's transaction history, which is far more honest than the asking price.",
    "多平台交叉对比": "Cross-check several platforms",
    "——安居客、我爱我家、当地中介门店报价相互印证。":
      " — corroborate Anjuke, 5i5j and local agency quotes against each other.",
    "官方渠道": "Official channels",
    "——当地住建局/房产交易中心的网签备案数据、国家统计局 70 城房价指数看趋势。":
      " — registered contract data from the local housing bureau or property exchange, and the National Bureau of Statistics 70-city index for the trend.",
    "实地走访": "Visit in person",
    "——同小区不同楼栋、楼层、朝向差价可达 10~20%，多看几套才有\"盘感\"。":
      " — within one development, block, floor and orientation can move the price by 10–20%; you only get a feel for it after several viewings.",
    "留意挂牌周期": "Watch how long listings sit",
    "——挂了很久卖不掉的价格不是市场价；近 3 个月成交密集的价位才是。":
      " — a price that has not sold for months is not the market price; the band where sales cluster over the past three months is.",
    "房值罗盘 · 参考工具 · 托管于 GitHub Pages": "Home Value Compass · Reference tool · Hosted on GitHub Pages",
    "数据为静态参考量级，请以真实成交为准": "Static reference magnitudes only — defer to actual transactions"
  };

  /* --------------------------------------------------- 声波诱鱼实验室（科普） */
  var FISH_LAB = {
    "🐟 声波诱鱼实验室": "🐟 Acoustic Fish-Attraction Lab",
    "一台真能响的低频发生器 · 一份分得清真假的科学说明":
      "A low-frequency generator that really makes sound · and a write-up that separates evidence from hype",
    "🔊 诱鱼音发生器": "🔊 Fish-attraction tone generator",
    "低频区，多数鱼类听觉最敏感的范围": "Low frequencies — where most fish hear best",
    "120 Hz 低频纯音": "120 Hz pure low tone",
    "多数鱼听觉敏感区": "Most fish are sensitive here",
    "80 Hz 进食脉冲": "80 Hz feeding pulse",
    "模拟规律的\"咚咚\"投喂感": "Mimics the regular thump of feeding",
    "400 Hz 中频": "400 Hz mid frequency",
    "部分鱼种可感知": "Perceptible to some species",
    "60 Hz 低沉震动": "60 Hz deep vibration",
    "接近侧线感知下限": "Near the lower limit of lateral-line sensing",
    "1 kHz 高频对照": "1 kHz high-frequency control",
    "多数鱼已较不敏感": "Most fish are much less sensitive here",
    "⚠️ 关键前提：手机/电脑扬声器朝空气放声，": "⚠️ Key caveat: a phone or computer speaker fires into the air, so the ",
    "声音几乎进不了水": "sound barely enters the water",
    "（空气与水的声阻抗相差约 3600 倍）。要真正作用于水下，需要":
      " (the acoustic impedance of air and water differs by roughly 3,600×). To actually act underwater you need a ",
    "防水水下扬声器或换能器": "waterproof underwater speaker or transducer",
    "。本工具是声音实验与科普演示，不是保证渔获的器械。":
      ". This tool is a sound experiment and a science demo, not a device that guarantees a catch.",
    "🔬 科学真相：声音真能诱鱼吗？": "🔬 The science: does sound really attract fish?",
    "部分成立，但有重要前提。": "Partly, with important caveats.",
    "鱼确实能感知声音、低频尤其敏感，\"声学诱鱼\"在科研里有正面证据；但效果因鱼种和场景而异，且必须把声音有效送入水中才谈得上，远没有商家宣传的那么神。":
      "Fish do perceive sound and are especially sensitive to low frequencies, and acoustic attraction has positive evidence in the literature. But the effect varies by species and setting, it only counts once the sound actually gets into the water, and it is nowhere near as potent as marketing claims.",
    "点击展开，看看哪些说法靠谱、哪些被夸大了 👇": "Expand to see which claims hold up and which are overstated 👇",
    "✅ \"鱼能听见声音，低频尤其敏感\" —— 成立": "✅ \"Fish hear sound, especially low frequencies\" — holds up",
    "这是有坚实生理学基础的。鱼通过内耳的耳石以及身体两侧的": "This rests on solid physiology. Fish sense sound and water movement through the otoliths of the inner ear and the ",
    "侧线系统": "lateral line system",
    "感知声音和水流振动，多数硬骨鱼对约": " along each flank. Most bony fish are most sensitive to the ",
    "50–1000 Hz 的低频": "low band of roughly 50–1,000 Hz",
    "最敏感，侧线还能捕捉 200 Hz 以下的近场颗粒运动。所以本发生器默认放在低频区。":
      ", and the lateral line also picks up near-field particle motion below 200 Hz. That is why this generator defaults to the low band.",
    "✅ \"用声音训练鱼听声进食\" —— 成立（条件反射）": "✅ \"Fish can be trained to feed on a sound cue\" — holds up (conditioning)",
    "水产养殖里很常见：每次投喂前播放固定声音，重复多次后鱼群一听到声音就聚过来，这是经典的":
      "Common in aquaculture: play a fixed sound before every feed and after enough repetitions the school gathers on the cue alone — textbook ",
    "巴甫洛夫条件反射": "Pavlovian conditioning",
    "。但它依赖长期、固定环境下的训练，野外随机水域里临时放个声音，并不会有同样效果。":
      ". But it depends on sustained training in a fixed setting; playing a sound on the spot in random open water does not do the same thing.",
    "🟡 \"播放声音能把野生鱼吸引过来\" —— 有证据但有限": "🟡 \"Playing sound draws wild fish in\" — some evidence, but limited",
    "最有力的证据是 Gordon 等人 2019 年的研究：在退化珊瑚礁播放健康礁石的环境声，聚集的幼鱼数量约为对照的两倍。这说明声学诱集":
      "The strongest evidence is Gordon et al. (2019): playing the ambient soundscape of a healthy reef over a degraded one drew roughly twice as many juvenile fish as the control. So acoustic attraction ",
    "在特定条件下确实有效": "does work under specific conditions",
    "。但这是针对珊瑚礁鱼群的栖息地选择行为，能否照搬到你常钓的鲫鱼鲤鱼、能否胜过传统饵料打窝，":
      ". But that is habitat-selection behaviour in reef fish; whether it carries over to the carp and crucian you actually fish for, or beats conventional baiting and chumming, ",
    "缺乏一致证据": "lacks consistent evidence",
    "🟡 \"市售电子诱鱼器很神\" —— 普遍被夸大": "🟡 \"Commercial electronic fish attractors are amazing\" — generally overstated",
    "这类产品的独立测评结果参差不齐。核心问题：① 效果高度依赖鱼种、声音特性、水下传声条件；② 很多产品的实际声输出和宣传相去甚远。把它当作\"也许有点用的辅助\"可以，当成\"渔获保证\"就会失望。":
      "Independent tests of these products are all over the map. Two core problems: (1) any effect depends heavily on species, the character of the sound and how it propagates underwater; (2) the real acoustic output of many products is nothing like the advertising. Treat one as a maybe-helpful accessory and it is fine; treat it as a guaranteed catch and you will be disappointed.",
    "❗ \"手机喇叭对着水面放就能诱鱼\" —— 几乎无效": "❗ \"Point a phone speaker at the water and it attracts fish\" — essentially useless",
    "物理硬伤：空气与水的": "A hard physical limit: the ",
    "声阻抗相差约 3600 倍": "acoustic impedance of air and water differs by about 3,600×",
    "，声音从空气打到水面，绝大部分能量被反射回去，真正进入水中的微乎其微。要作用于水下，必须用":
      ", so when sound hits the surface from the air almost all of the energy reflects back and only a negligible fraction enters the water. To act underwater you must use a ",
    "防水水下扬声器/换能器": "waterproof underwater speaker or transducer",
    "把声音直接送进水里。这也是本工具反复强调的前提。":
      " that puts the sound straight into the water. That is the caveat this tool keeps repeating.",
    "🎣 真正能提高渔获的，是这些": "🎣 What actually improves your catch",
    "选对钓点与时段": "Pick the right spot and time",
    "——晨昏、水温适宜、有水草/结构/进出水口的地方，远比任何\"神器\"重要。":
      " — dawn and dusk, comfortable water temperature, weed, structure or inflows and outflows matter far more than any gadget.",
    "对路的饵料与打窝": "The right bait and groundbait",
    "——用目标鱼爱吃的饵，提前打窝聚鱼，是最经典也最有效的\"诱鱼\"。":
      " — use what the target species eats and chum ahead of time; this is the oldest and most effective form of attraction.",
    "看懂水情": "Read the water",
    "——观察鱼星、水色、风向；下风口常聚集食物和鱼。":
      " — watch for bubble trails, water colour and wind direction; the downwind shore usually collects both food and fish.",
    "钓组与灵敏度": "Rig and sensitivity",
    "——线组、浮漂、钩号匹配鱼情，信号清晰才能抓口。":
      " — match line, float and hook size to the conditions; you can only hit the bite if the signal is clean.",
    "安静与隐蔽": "Stay quiet and out of sight",
    "——岸上的脚步声、说话声会通过地面传入水中惊鱼，保持安静往往比\"放声\"更有用。":
      " — footsteps and talking on the bank travel through the ground into the water and spook fish; silence usually beats playing sound.",
    "遵守当地法规": "Follow local regulations",
    "——许多地区对电子诱鱼/声诱设备有限制甚至禁止，垂钓前务必了解当地渔业规定与禁渔期。":
      " — many jurisdictions restrict or ban electronic and acoustic fish attractors; check local fishery rules and closed seasons before you fish.",
    "Nature Communications, 2019. —— 播放健康礁石声音可使退化礁区聚集的鱼增加约一倍.":
      "Nature Communications, 2019. — Playing healthy-reef sound roughly doubled the fish that settled on degraded reef.",
    "Nature Communications, 2019. —— 播放健康礁石声音可使退化礁区聚集的鱼增加约一倍。":
      "Nature Communications, 2019. — Playing healthy-reef sound roughly doubled the fish that settled on degraded reef.",
    "• 大量研究表明，多数硬骨鱼的听觉敏感区集中在约 50–1000 Hz 的低频，侧线系统可感知约 200 Hz 以下的近场水流振动。":
      "• A large body of work puts the hearing sensitivity of most bony fish in the roughly 50–1,000 Hz low band, with the lateral line sensing near-field water motion below about 200 Hz.",
    "• 水产养殖中\"声音—投喂\"条件反射训练（经典条件反射）已被广泛应用，可让鱼群听到特定声音便聚集。":
      "• Sound-to-feed conditioning (classical conditioning) is widely used in aquaculture and reliably gathers a school on a specific cue.",
    "• 与此同时，市售\"电子诱鱼器\"的独立测评结果普遍参差，效果高度依赖鱼种、声音特性与水下传声条件。":
      "• At the same time, independent tests of commercial electronic fish attractors are broadly inconsistent, with any effect depending heavily on species, sound character and underwater propagation.",
    "注：以上为公开研究的概述，具体数据请查阅原文；本页面不构成渔获保证或法律建议，垂钓请遵守当地法规。":
      "Note: the above summarises published research — consult the original papers for the figures. This page is neither a guarantee of catch nor legal advice; follow your local fishing regulations.",
    "声波诱鱼实验室 · 科普向 · 托管于 GitHub Pages":
      "Acoustic Fish-Attraction Lab · Science explainer · Hosted on GitHub Pages",
    "分得清\"有依据\"和\"被夸大\"，才玩得明白 🌊":
      "Knowing what is evidenced and what is hype is half the fun 🌊"
  };

  /* --------------------------------------------------- 声波驱蚊实验室（科普） */
  var MOSQUITO_LAB = {
    "🦟 声波驱蚊实验室": "🦟 Ultrasonic Mosquito-Repellent Lab",
    "一台真能响的频率发生器 · 一份不忽悠的科学说明":
      "A tone generator that really makes sound · and a write-up that does not oversell it",
    "🔊 频率发生器": "🔊 Tone generator",
    "超高频，部分年轻人能听到": "Very high frequency — audible to some younger listeners",
    "18 kHz 超高频": "18 kHz very high frequency",
    "常见\"驱蚊\"宣传频率": "The frequency most often advertised as repellent",
    "1 kHz 雄蚊翅振": "1 kHz male wingbeat",
    "据说模拟雄蚊（无依据）": "Claimed to mimic a male mosquito (unsupported)",
    "12 kHz 蜻蜓说": "12 kHz dragonfly theory",
    "宣称模拟天敌蜻蜓": "Claimed to mimic a predatory dragonfly",
    "40 kHz 蝙蝠超声": "40 kHz bat ultrasound",
    "远超人耳与多数设备上限": "Far above human hearing and most devices' output limit",
    "440 Hz 标准音": "440 Hz reference tone",
    "听个响，校准音量用": "Just to hear something — use it to set the volume",
    "⚠️ 安全提示：请从低音量开始，高频长时间大音量可能伤害听力，尤其勿靠近婴幼儿与宠物（猫狗能听到更高频率，可能引起不适）。这是一个声音实验工具，":
      "⚠️ Safety: start quiet. Loud high frequencies over long periods can damage hearing, and keep it away from infants and pets (cats and dogs hear higher frequencies and may find it distressing). This is a sound-experiment tool, ",
    "不是医疗或驱虫器械": "not a medical or pest-control device",
    "🔬 科学真相：声波真能驱蚊吗？": "🔬 The science: does ultrasound actually repel mosquitoes?",
    "目前没有可靠科学证据表明声波/超声波能驱赶蚊子。":
      "There is currently no reliable scientific evidence that sound or ultrasound repels mosquitoes.",
    "多项严谨的野外与实验室研究都得出了否定结论，相关商业产品也屡遭监管处罚。":
      "Multiple rigorous field and laboratory studies came back negative, and the commercial products have repeatedly drawn regulatory action.",
    "下面是几种流行的\"声波驱蚊\"说法，以及它们为什么站不住脚 👇 点击展开：":
      "Here are the popular claims and why they do not hold up 👇 tap to expand:",
    "🦟 \"模拟雄蚊翅膀振动，吓走刚交配过、不想再被打扰的雌蚊\"":
      "🦟 \"It mimics male wingbeats and scares off mated females who want to be left alone\"",
    "这是最流行的说法。问题在于：受精后的雌蚊行为远比\"避开雄蚊\"复杂，并不会简单地被一个固定频率赶走；而且蚊子主要靠触角感受近场的空气振动，对远处扬声器发出的声波反应很弱。":
      "The most popular claim, and the problems are basic: the behaviour of a mated female is far more complex than \"avoid males\", and she is not driven off by one fixed frequency. Mosquitoes also sense near-field air motion with their antennae and respond weakly to sound from a distant speaker.",
    "实验中并未观察到驱赶效果。": "No repellent effect was observed in testing.",
    "🐉 \"模拟蜻蜓等天敌的振翅声，让蚊子因恐惧而逃离\"":
      "🐉 \"It mimics the wingbeat of dragonflies and other predators, so mosquitoes flee in fear\"",
    "蚊子并没有被证实能通过特定声音识别并躲避天敌。蜻蜓捕食靠的是视觉与飞行围捕，不是发出某种\"恐吓频率\"。":
      "Mosquitoes have never been shown to identify and avoid predators by sound. Dragonflies hunt by sight and aerial pursuit, not by emitting some intimidating frequency.",
    "这一理论缺乏实证支持。": "The theory has no empirical support.",
    "🦇 \"蝙蝠超声波（40 kHz 左右）能驱赶蚊子\"":
      "🦇 \"Bat ultrasound (around 40 kHz) drives mosquitoes away\"",
    "两个硬伤：其一，普通手机/电脑扬声器根本发不出 40 kHz 的有效声压；其二，即便发出，研究也未发现蚊子会因此远离。":
      "Two fatal flaws: an ordinary phone or computer speaker cannot produce meaningful sound pressure at 40 kHz at all; and even where it is produced, studies find no mosquito avoidance.",
    "FTC 曾对类似宣传的产品提起虚假广告诉讼。":
      "The FTC has brought false-advertising actions against products making this claim.",
    "📱 \"手机驱蚊 App 真的有用，下载量很高\"":
      "📱 \"Mosquito-repellent apps really work — look at the download counts\"",
    "下载量高不等于有效。这类 App 大多只是播放一段高频音，独立测评和科学研究都未能证明其能减少叮咬。高评分常源于安慰剂效应——\"今晚没被咬\"可能只是因为今晚蚊子本来就少。":
      "Downloads are not efficacy. These apps mostly just play a high tone, and neither independent testing nor scientific study has shown they reduce bites. High ratings usually reflect the placebo effect — \"I wasn't bitten tonight\" may simply mean there were fewer mosquitoes tonight.",
    "🔬 \"Cochrane 综述到底说了什么？\"": "🔬 \"What did the Cochrane review actually say?\"",
    "2007 年 Enayati 等人在 Cochrane 数据库发表的系统综述，汇总了 10 项野外试验。结论非常明确：":
      "The 2007 systematic review by Enayati et al. in the Cochrane Database pooled 10 field trials, and the conclusion is unambiguous:",
    "电子（超声波）驱蚊器对防止蚊虫叮咬没有效果，不应推荐用于预防蚊媒疾病。":
      "electronic (ultrasonic) mosquito repellents have no effect on preventing bites and should not be recommended for preventing mosquito-borne disease.",
    "这是目前该领域被引用最多的权威结论之一。":
      "It remains one of the most-cited authoritative conclusions in the field.",
    "✅ 那么，什么才真正有效？": "✅ So what actually works?",
    "含 DEET / 派卡瑞丁（Picaridin）/ 柠檬桉油（OLE）的驱蚊液":
      "Repellents containing DEET, picaridin or oil of lemon eucalyptus (OLE)",
    "——经权威机构验证有效，涂抹在皮肤上。": " — verified effective by public-health authorities; applied to the skin.",
    "蚊帐与纱窗": "Bed nets and window screens",
    "——物理隔离，最朴素也最可靠，尤其适合睡眠时段。":
      " — physical separation, the plainest and most reliable option, especially while sleeping.",
    "清除积水": "Remove standing water",
    "——花盆托盘、废旧轮胎、瓶罐里的死水是蚊子的繁殖温床，定期倒掉。":
      " — saucers under plant pots, old tyres and bottles are breeding grounds; empty them regularly.",
    "电热蚊香液/盘（含拟除虫菊酯）": "Plug-in or coil vaporisers (pyrethroid-based)",
    "——在通风的室内有效，注意按说明使用。": " — effective in ventilated rooms; follow the instructions.",
    "风扇": "A fan",
    "——蚊子飞行能力弱，一台对着吹的风扇就能让它们难以靠近，意外地好用。":
      " — mosquitoes are weak fliers, and a fan pointed at you keeps them off surprisingly well.",
    "穿浅色长袖长裤": "Light-coloured long sleeves and trousers",
    "——减少暴露的皮肤面积，蚊子也更易被深色吸引。":
      " — less exposed skin, and mosquitoes are more drawn to dark colours.",
    "Cochrane Database of Systematic Reviews, 2007. —— 系统综述结论：电子驱蚊器无降低叮咬的证据。":
      "Cochrane Database of Systematic Reviews, 2007. — Systematic review conclusion: no evidence that electronic repellents reduce bites.",
    "• 美国联邦贸易委员会（FTC）历年来对宣称\"超声波驱虫/驱蚊\"的产品提起过虚假广告诉讼。":
      "• The U.S. Federal Trade Commission has over the years brought false-advertising actions against products claiming ultrasonic pest or mosquito repellency.",
    "• 多家科普机构（如各国疾控中心、消费者权益组织）对超声波驱蚊持否定态度，建议采用上文的物理与化学防护方法。":
      "• Public-health and consumer bodies (national CDCs, consumer-rights organisations) reject ultrasonic mosquito repellency and recommend the physical and chemical measures above.",
    "注：以上为公开研究的概述，具体数据请查阅原文；本页面不构成医疗或健康建议。":
      "Note: the above summarises published research — consult the original papers for the figures. This page is not medical or health advice.",
    "声波驱蚊实验室 · 科普向 · 托管于 GitHub Pages":
      "Ultrasonic Mosquito-Repellent Lab · Science explainer · Hosted on GitHub Pages",
    "做一个诚实又好玩的小工具 ☀️": "An honest little tool that is still fun ☀️"
  };

  var dict = {};
  add(dict, COMMON);
  if (path.indexOf("/apps/tech-leaders/") === 0) add(dict, TECH_LEADERS);
  if (path.indexOf("/apps/telescope/") === 0) add(dict, TELESCOPE);
  if (path.indexOf("/apps/home-value/") === 0) add(dict, HOME_VALUE);
  if (path.indexOf("/apps/fish-lab/") === 0) add(dict, FISH_LAB);
  if (path.indexOf("/apps/mosquito-lab/") === 0) add(dict, MOSQUITO_LAB);

  /* 组合串整串进不了字典，只翻固定部分，把数字/账号/诊断码原样带回。 */
  function regexTranslate(s) {
    var m;
    if (path.indexOf("/apps/tech-leaders/") === 0) {
      // V4.2 的统计条与徽标是拼出来的，数字原样带回。
      if ((m = /^(\d+) 位 · (\d+) 大分类$/.exec(s))) return m[1] + " leaders · " + m[2] + " categories";
      if ((m = /^已收录 (\d+) 位 · 自托管头像 (\d+)\/(\d+) · (.+?) · 当前显示 (\d+) \/ (\d+) 位$/.exec(s))) {
        return m[1] + " leaders listed · " + m[2] + "/" + m[3] + " avatars self-hosted · " +
          (dict[m[4]] || m[4]) + " · showing " + m[5] + " of " + m[6];
      }
      if ((m = /^自托管头像 (\d+)\/(\d+)$/.exec(s))) return m[1] + "/" + m[2] + " avatars self-hosted";
      /* V4.3 把「自托管头像」改成了「X 原版头像核验」，统计条、两个筛选按钮与
         详情卡的说明一起换了措辞；旧规则全部失配。新旧都留着——上游还在迭代，
         回滚到 V4.2 时不至于又变回中文。 */
      if ((m = /^已收录 (\d+) 位 · X原版头像 (\d+)\/(\d+)(（核验中）)? · (.+?) · 当前显示 (\d+)(?: \/ (\d+))? 位$/.exec(s))) {
        return m[1] + " leaders listed · " + m[2] + "/" + m[3] + " X-original avatars" +
          (m[4] ? " (verifying)" : "") + " · " + (dict[m[5]] || m[5]) +
          " · showing " + m[6] + (m[7] ? " of " + m[7] : "");
      }
      if ((m = /^X原版 (\d+)\/(\d+)$/.exec(s))) return "X original " + m[1] + "/" + m[2];
      if ((m = /^核验中 (\d+)\/(\d+)$/.exec(s))) return "Verifying " + m[1] + "/" + m[2];
      if ((m = /^待核验 (\d+)$/.exec(s))) return m[1] + " to verify";
      if ((m = /^V([\d.]+) · 全球公司领袖 \+ X 原版头像核验$/.exec(s))) {
        return "V" + m[1] + " · Global corporate leaders + X-original avatar verification";
      }
      if ((m = /^待补 (\d+)$/.exec(s))) return m[1] + " outstanding";
      if ((m = /^展开 (\d+) 位 ↓$/.exec(s))) return "Show all " + m[1] + " ↓";
      if ((m = /^收起 ↑$/.exec(s))) return "Collapse ↑";
      if ((m = /^V([\d.]+) · 全球公司领袖 \+ Ooglex 自托管头像$/.exec(s))) {
        return "V" + m[1] + " · Global corporate leaders + Ooglex self-hosted avatars";
      }
      if ((m = /^全部分类$/.exec(s))) return "All categories";
      if ((m = /^(.+?) 头像$/.exec(s))) return (dict[m[1]] || m[1]) + " avatar";
      // 「AMD · 董事长兼 CEO」这类：逐段查表，查不到原样留下。
      if (s.indexOf(" · ") > 0 && /[\u4e00-\u9fff]/.test(s)) {
        var segs = s.split(" · "), hit = false;
        var joined = segs.map(function (seg) {
          if (dict[seg]) { hit = true; return dict[seg]; }
          return seg;
        }).join(" · ");
        if (hit && !/[\u4e00-\u9fff]/.test(joined)) return joined;
      }
      if ((m = /^诊断码：(\S+) · 免费 Embed 依赖访问者网络连接 X。$/.exec(s))) {
        return "Diagnostic code: " + m[1] + " · the free embed depends on the visitor's network reaching X.";
      }
    }
    if ((m = /^打开 @(\S+) ↗$/.exec(s))) return "Open @" + m[1] + " ↗";
    if ((m = /^诊断码：(\S+)$/.exec(s))) return "Diagnostic code: " + m[1];
    if ((m = /^回复 (\S+)$/.exec(s))) return "Replies " + m[1];
    if ((m = /^转发 (\S+)$/.exec(s))) return "Reposts " + m[1];
    if ((m = /^喜欢 (\S+)$/.exec(s))) return "Likes " + m[1];
    if ((m = /^(\d+) 张照片$/.exec(s))) return m[1] + (m[1] === "1" ? " photo" : " photos");
    return null;
  }

  function translateValue(s) {
    if (Object.prototype.hasOwnProperty.call(dict, s)) return dict[s];
    return regexTranslate(s);
  }

  function skipText(node) {
    var p = node && node.parentElement;
    if (!p || /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE)$/.test(p.tagName)) return true;
    if (p.closest && p.closest("[data-i18n-skip]")) return true;
    return false;
  }

  function translateText(node) {
    if (!node || node.nodeType !== 3 || skipText(node)) return;
    var raw = node.nodeValue || "", s = raw.trim();
    if (!s) return;
    var out = translateValue(s);
    if (!out || out === s) return;
    if (!textOrig.has(node)) { textOrig.set(node, raw); textTouched.push(node); }
    var i = raw.indexOf(s);
    node.nodeValue = (i >= 0 ? raw.slice(0, i) : "") + out + (i >= 0 ? raw.slice(i + s.length) : "");
  }

  function translateAttrs(el) {
    if (!el || el.nodeType !== 1) return;
    var saved = null;
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      if (!el.hasAttribute(a)) continue;
      var v = el.getAttribute(a), out = translateValue((v || "").trim());
      if (!out || out === v) continue;
      if (!saved) saved = attrOrig.get(el) || {};
      if (!(a in saved)) saved[a] = v;
      el.setAttribute(a, out);
    }
    if (saved && !attrOrig.has(el)) { attrOrig.set(el, saved); attrTouched.push(el); }
    else if (saved) attrOrig.set(el, saved);
  }

  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { translateText(root); return; }
    if (root.nodeType !== 1 && root.nodeType !== 9 && root.nodeType !== 11) return;
    var it = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), n;
    while ((n = it.nextNode())) translateText(n);
    if (root.nodeType === 1) translateAttrs(root);
    var els = root.querySelectorAll ? root.querySelectorAll("[placeholder],[aria-label],[title],[alt]") : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
    leaderInitials();   // 要读翻好的英文名，必须排在文本与属性翻译之后
  }

  function restore() {
    for (var i = 0; i < textTouched.length; i++) {
      var n = textTouched[i];
      if (n && textOrig.has(n)) n.nodeValue = textOrig.get(n);
    }
    for (var j = 0; j < attrTouched.length; j++) {
      var el = attrTouched[j], saved = attrOrig.get(el);
      if (!el || !saved) continue;
      Object.keys(saved).forEach(function (a) { el.setAttribute(a, saved[a]); });
    }
    textTouched = []; attrTouched = [];
    textOrig = new WeakMap(); attrOrig = new WeakMap();
  }

  var META = {
    "/apps/tech-leaders/": ["Tech Leaders on X · Public Posts from Musk, Huang and Peers",
      "Public X posts from tech leaders and their companies: Elon Musk, NVIDIA for Jensen Huang, Sam Altman, Lisa Su, Sundar Pichai and Satya Nadella."],
    "/apps/telescope/": ["StarPupil Telescope · Turn Your Phone into a Digital Telescope",
      "Hybrid optical and digital zoom, night vision and image enhancement, compass and level, with a built-in viewfinder gallery."],
    "/apps/home-value/": ["Home Value Compass · Order-of-Magnitude Property Estimate",
      "Estimate the rough value of a home from address, floor area, building age, finish and floor. Static reference data — not a valuation."],
    "/apps/fish-lab/": ["Acoustic Fish-Attraction Lab · A Working Tone Generator and the Evidence",
      "A low-frequency tone generator plus a plain-language review of what acoustic fish attraction can and cannot do."],
    "/apps/mosquito-lab/": ["Ultrasonic Mosquito-Repellent Lab · A Working Tone Generator and the Evidence",
      "A tone generator plus the research on why ultrasonic mosquito repellents do not work, and what does."]
  };
  var metaOrig = null;
  function translateMeta() {
    var m = META[path];
    if (!m) return;
    var d = document.querySelector('meta[name="description"]');
    if (!metaOrig) metaOrig = { title: document.title, desc: d ? d.content : "" };
    document.title = m[0];
    if (d) d.content = m[1];
  }
  function restoreMeta() {
    if (!metaOrig) return;
    document.title = metaOrig.title;
    var d = document.querySelector('meta[name="description"]');
    if (d) d.content = metaOrig.desc;
  }
  /* pending 原本是「本帧已排过队就直接 return」——但 return 掉的那一批 records
     **就此丢了**，不会被后面的 rAF 处理。数据枢纽这类一屏拉十几个 data.json、
     逐卡渲染的页面，一帧里能来好几批 mutation，于是「领涨」「今日上涨」这些
     字典里明明有的词条永远翻不到。改成先把 records 攒起来再统一处理：
     既保留按帧合并的原意，又一条都不丢。 */

  var observer = null, pending = false, queued = [];
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (records) {
      if (current !== "en") return;

      queued = queued.concat(Array.prototype.slice.call(records));

      if (pending) return;
      pending = true;
      requestAnimationFrame(function () {
        pending = false;
        /* rAF 排队期间用户可能已经切回中文：那时 restore() 已经跑完，
           这一帧再去翻译（尤其是末尾无条件调用的 specialEnglish）会把刚还原的
           标题、样式又改回英文态——宏观风险监测的中文大标题就是这么丢的。 */
        if (current !== "en") { queued = []; return; }
        var batch = queued; queued = [];
        batch.forEach(function (r) {
          if (r.type === "attributes") translateAttrs(r.target);
          else if (r.type === "characterData") translateText(r.target);
          else Array.prototype.forEach.call(r.addedNodes || [], function (n) { walk(n); });
        });
        /* 头像首字母必须在整批处理完之后再跑一次：详情卡换人时 textContent 被整体替换，
           到达这里的是一个纯文本节点，walk() 对文本节点会提前 return，
           挂在 walk() 末尾的那次调用根本不会执行；而且它要读同一个 shell 里
           已经翻好的 img[alt]，那条属性也在这一批里。 */
        leaderInitials();
      });
    });
    /* 也盯 ATTRS 里那几个属性：原先只盯 childList/characterData，
       于是「就地改写已有元素的 aria-label/title」这类更新永远翻不到
       （行情板的「当前显示 73 项：上涨 25…」就是这么漏的）。
       改写属性本身会再触发一次 mutation，但英文串查不到词条，第二轮是空转，不会循环。 */
    observer.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
  }

  /* 头像圆圈里是领袖中文名的前两个字（「马斯」「黄仁」）。名字已翻成英文，
     首字也得跟着换；同一张卡里找得到英文名才换，找不到不动。 */
  function leaderInitials() {
    if (path.indexOf("/apps/tech-leaders/") !== 0) return;
    document.querySelectorAll(".avatar-fallback").forEach(function (el) {
      var node = el.firstChild;
      if (!node || node.nodeType !== 3) return;
      var t = (node.nodeValue || "").trim();
      if (!t || !/^[\u4e00-\u9fff]+$/.test(t)) return;
      /* 同一个 shell 里的 <img alt> 此时已被翻成「Elon Musk avatar」，取它的首字母。
         取不到英文名就不动这个圆圈——宁可留中文，也不写一个对不上人的字母。 */
      var shell = el.closest && el.closest(".leader-avatar-shell,.profile-avatar-shell");
      var img = shell && shell.querySelector("img[alt]");
      var en = img ? img.getAttribute("alt").replace(/ avatar$/, "").trim() : "";
      if (!en || /[\u4e00-\u9fff]/.test(en)) return;
      if (!textOrig.has(node)) { textOrig.set(node, node.nodeValue); textTouched.push(node); }
      node.nodeValue = en.trim().charAt(0).toUpperCase();
    });
  }

  function apply(lang) {
    current = lang === "en" ? "en" : "zh";
    document.documentElement.setAttribute("data-lang", current);
    document.documentElement.setAttribute("lang", current === "en" ? "en" : "zh-CN");
    if (current === "en") { walk(document.body); translateMeta(); watch(); }
    else { restore(); restoreMeta(); }
  }

  function boot() { apply(readLang()); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  document.addEventListener("ooglex:languagechange", function (e) {
    apply(e && e.detail && e.detail.language === "en" ? "en" : "zh");
  });
  window.addEventListener("storage", function (e) {
    if (e.key === KEY) apply(e.newValue === "en" ? "en" : "zh");
  });
})();
