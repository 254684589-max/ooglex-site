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

  /* --------------------------------------------------------- 科技领袖 X 动态
     人名用榜单已有的英文原名，不另行音译；@handle、帖子正文与诊断码保持原文。 */
  var TECH_LEADERS = {
    "科技领袖 X 动态": "Tech Leaders on X",
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
    "在 X 打开原主页 ↗": "Open the profile on X ↗",
    "个人公开 X 账号。": "Personal public X account.",
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
      });
    });
    /* 也盯 ATTRS 里那几个属性：原先只盯 childList/characterData，
       于是「就地改写已有元素的 aria-label/title」这类更新永远翻不到
       （行情板的「当前显示 73 项：上涨 25…」就是这么漏的）。
       改写属性本身会再触发一次 mutation，但英文串查不到词条，第二轮是空转，不会循环。 */
    observer.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
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
