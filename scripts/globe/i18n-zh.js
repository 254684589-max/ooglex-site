/* ===========================================================================
   全球态势地球 —— 界面中文化层
   ---------------------------------------------------------------------------
   上游 God's Eye View 没有国际化层，界面文案散落在 HTML 模板与 JS 里。分叉源码
   逐处替换会让每次同步上游都要重做，因此这里在运行时做一层 DOM 文案映射。

   三条安全约束：

   1) **白名单**。只替换 DICT 里逐条列出的完整文案，绝不做子串替换。原因：界面用
      Material Icons 的**连字名**当图标内容（`arrow_forward`、`chevron_left`、
      `public`、`radar` 等），一旦被翻译图标会直接变成乱码文字；数据读数
      （MGRS、经纬度、时刻、呼号、机型）也绝不能动。白名单天然排除这些。

   2) **跳过署名区**。Cesium 署名行与「Data attribution」弹层里的文字是许可要求
      的署名（Esri / Google / OSM / TeleGeography / NASA 等），必须原样保留，
      翻译即违反许可。见 SKIP_SELECTORS。

   3) **保留数据源专名**。OpenSky、adsb.lol、AISStream、OpenStreetMap、CelesTrak、
      USGS、TeleGeography 等作为出处标识不翻译。

   切回英文：给页面加 `?lang=en`（包装页顶栏的「中/EN」按钮就是这么做的）。
   不做「撤销翻译」的簿记 —— 重载更可靠。
   =========================================================================== */
(function () {
  'use strict';

  try {
    if (new URLSearchParams(location.search).get('lang') === 'en') return;
  } catch (e) { /* 继续按中文渲染 */ }

  /** 这些子树内的文字是许可要求的署名，绝不翻译。 */
  var SKIP_SELECTORS = [
    '#cesium-credits',
    '.cesium-widget-credits',
    '.cesium-credit-lightbox',
    '.cesium-credit-lightbox-overlay',
    '[data-no-translate]',
  ];

  var DICT = {
    // ---------------------------------------------------------------- 品牌行
    "GOD'S EYE": '全球态势', 'VIEW': '地球',
    "God's Eye View": '全球态势地球',
    'NO PLACE LEFT BEHIND': '无处不可见',

    // ------------------------------------------------------------ 面板标题
    'DATA LAYERS': '数据图层',
    'SCENES': '场景',
    'DISPLAY': '显示',
    'VISUAL PRESETS': '视觉预设',
    'LOCATION': '定位',
    'CONTEXT': '周边情况',
    'MISSION CONTROL': '任务控制',
    'MISSION CONTROL · FIRST LAUNCH': '任务控制 · 首次启动',
    'COMMAND DOCK': '指令栏',
    'ACTIVE STYLE': '当前风格',
    'CCTV': '监控摄像头',
    'RADIO': '电台',
    'MIC': '语音',
    'AI AGENT': 'AI 助手',
    'VOICE': '语音',
    'LAYERS': '图层',
    'MAP SOURCE': '底图来源',
    'PROVIDER SETTINGS': '数据源设置',

    // ------------------------------------------------------------ 图层名称
    'Live Flights': '实时航班',
    'Flights': '航班',
    'Military Flights': '军用航班',
    'Military flights': '军用航班',
    'Live AIS Vessels': '实时船舶（AIS）',
    'AIS vessels': 'AIS 船舶',
    'Earthquakes (24h)': '地震（近 24 小时）',
    'Satellites': '卫星',
    'Space Missions (30d)': '航天任务（近 30 天）',
    'ALPR Cameras': '车牌识别摄像头',
    'ALPR camera': '车牌识别摄像头',
    'ALPR CAMERA': '车牌识别摄像头',
    'Street Traffic': '道路交通',
    'Submarine Cables': '海底电缆',
    'Mapped Installations': '已测绘设施',
    'Mapped installations': '已测绘设施',
    'Global Context': '全球周边情况',
    'Bikeshare': '公共自行车',
    'Active Fires': '活跃火点',
    'Data Centers': '数据中心',
    'Dams': '大坝',
    'Radio': '电台',
    'Music': '音乐',
    'Talk': '谈话',
    'News': '新闻',
    'Public Safety': '公共安全',
    'Aviation / Marine': '航空 / 航海',
    'Other': '其他',

    // ---------------------------------------------------------- 开关与状态
    'ON': '开', 'OFF': '关', 'ON/OFF': '开 / 关',
    'ENABLE': '启用', 'DISABLE': '停用',
    'STOP': '停止', 'START': '开始',
    'All': '全部', 'ALL': '全部', 'NONE': '无',
    'PREV': '上一个', 'NEXT': '下一个',
    'CURRENT': '当前', 'UNKNOWN': '未知',
    'LOADING LIVE DATA': '正在加载实时数据',
    'LOADING': '加载中', 'SYNCING': '同步中',
    'syncing road network': '正在同步路网',
    'loading frames': '正在加载画面',
    'LOAD FAILED': '加载失败',
    'UNAVAILABLE': '不可用',
    'VOICE UNAVAILABLE': '语音不可用',
    'VOICE STANDBY': '语音待机',
    'ERROR': '错误',
    'never': '从未更新',
    'STANDBY': '待机',
    'ACTIVE': '已启用',
    'READY': '就绪',
    'NO DATA': '无数据',
    'EMPTY': '空',
    'STALE': '已过期',
    'RATE LIMITED': '被限流',
    'KEY REQUIRED': '需要密钥',
    'NOT CONFIGURED': '未配置',
    'CONTEXT ONLY': '仅作参考',
    'NO AVAILABLE EXAMPLE': '暂无可用示例',
    'ROUTE DATA UNAVAILABLE': '航路数据不可用',
    'ESTIMATED FLIGHT PLAN': '推算航路（非实际航迹）',
    'AVAILABLE INPUTS ONLY · NOT AN ALL-CLEAR': '仅为可得信息，不代表已排除风险',
    'NEAREST OBSERVED / MAPPED': '最近的已观测 / 已测绘对象',
    'OBSERVED / MAPPED PINGS': '已观测 / 已测绘目标',
    'LATEST LOCATION-MATCHED REPORTING': '按位置匹配的最新报道',
    'PLACE / CONDITIONS / POSITION': '地点 / 天气 / 坐标',
    'SHOW NEAREST': '显示最近的',
    'CONTACTS · 250 KM': '目标 · 250 公里内',
    'CONTACT': '目标',

    // -------------------------------------------------------------- 显示控制
    'DENSITY': '密度',
    'ALLOCATION': '分配方式',
    'ELASTIC': '弹性', 'WEIGHTED': '加权',
    'FADE': '淡出', 'OUTSIDE': '视野外',
    'MODELS': '三维模型', 'PROXIMITY': '就近',
    'SCOPE': '视域', 'FEATHER': '羽化',
    'CELESTIAL': '星空', 'CLEAN UI': '隐藏界面', 'BLOOM': '泛光',
    'LEVEL': '等级', 'VOLUME': '音量',
    'NORMAL': '常规', 'FIRST PERSON': '第一人称',
    '3D': '三维',
    'FOV': '视场角', 'RANGE': '距离',
    'PITCH': '俯仰', 'HDG': '航向', 'HGT': '高度',

    // -------------------------------------------------------------- 驾驶舱
    'AIRCRAFT': '航空器',
    'ALTITUDE': '高度', 'ALTITUDE · FT': '高度 · 英尺',
    'GROUND SPEED': '地速', 'GROUND SPEED · KTS': '地速 · 节',
    'KTS': '节', 'FT': '英尺',
    'FROM': '起点', 'TO': '终点',
    'LIVE TRACK · COURSE ALIGNED': '实时航迹 · 已对齐航向',
    'OPTICAL PLANE · 01': '光学平面 · 01',
    'VISOR LOCK · ACTIVE': '镜面锁定 · 已启用',
    'WX': '天气',
    'SITE': '站点',
    'FLT': '民航', 'MIL': '军机', 'AIS': '船舶', 'FIRE': '火点',

    // ------------------------------------------------------------ 首次启动
    'Choose your first view': '选择第一个视角',
    "It feels like a forbidden cockpit—then you realize the sources are public and the data is real.":
      '像是坐进了不该进的驾驶舱 —— 然后你发现这些数据源全是公开的，数据也都是真的。',
    "Don't show this again": '不再显示',
    'Tip: the GEV MIC button in the dock lets you talk to the map.':
      '提示：指令栏的语音按钮可以直接对地图说话（本站未配置语音服务）。',
    'ESC TO DISMISS': '按 ESC 关闭',
    'SUMMARY': '摘要',
    'Global Context': '全球周边情况',
    'loading...': '加载中…',
    'just now': '刚刚',
    'stale': '数据过期',
    'Data provided by:': '数据来源：',
  };

  /* 组合状态串：图层面板的副标题是 `${来源} · ${详情}` 拼出来的
     （上游 src/ui/layerPanel.js 的 _statusLine/_timeAgo），整串不可能进字典。
     这里用**两端锚定**的正则，只翻译尾部的时间/状态词，捕获组原样保留 ——
     来源专名（OpenSky、adsb.lol、CelesTrak…）是署名，必须留英文。
     刻意不做自由子串替换，理由见文件头第 1 条。 */
  var PATTERNS = [
    [/^(.*) · never$/, '$1 · 从未更新'],
    [/^(.*) · just now$/, '$1 · 刚刚'],
    [/^(.*) · (\d+)s ago$/, '$1 · $2 秒前'],
    [/^(.*) · (\d+)m ago$/, '$1 · $2 分钟前'],
    [/^(.*) · (\d+)h ago$/, '$1 · $2 小时前'],
    [/^(.*) · loading\.\.\.$/, '$1 · 加载中…'],
    [/^(.*) · stale$/, '$1 · 数据过期'],
    [/^(.*) · rate limited$/, '$1 · 被限流'],
    [/^(.*) · unavailable$/, '$1 · 不可用'],
  ];

  /** 字典未命中时，尝试锚定正则；都不中就原样返回 null。 */
  function translateComposite(key) {
    for (var i = 0; i < PATTERNS.length; i++) {
      if (PATTERNS[i][0].test(key)) return key.replace(PATTERNS[i][0], PATTERNS[i][1]);
    }
    return null;
  }

  /** 同名映射也用于这些属性。 */
  var ATTRS = ['title', 'aria-label', 'placeholder', 'alt'];

  function inSkippedSubtree(node) {
    var el = node.nodeType === 1 ? node : node.parentElement;
    for (; el; el = el.parentElement) {
      for (var i = 0; i < SKIP_SELECTORS.length; i++) {
        if (el.matches && el.matches(SKIP_SELECTORS[i])) return true;
      }
    }
    return false;
  }

  /** 只在整段文字完整命中字典时替换，并保留原有首尾空白。 */
  function translateTextNode(node) {
    var raw = node.nodeValue;
    if (!raw) return;
    var key = raw.trim();
    if (!key) return;
    var hit = Object.prototype.hasOwnProperty.call(DICT, key)
      ? DICT[key]
      : translateComposite(key);
    if (hit === null || hit === undefined || hit === key) return;
    if (inSkippedSubtree(node)) return;
    var lead = raw.slice(0, raw.indexOf(key));
    var tail = raw.slice(raw.indexOf(key) + key.length);
    node.nodeValue = lead + hit + tail;
  }

  function translateAttrs(el) {
    if (inSkippedSubtree(el)) return;
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      if (!el.hasAttribute || !el.hasAttribute(a)) continue;
      var v = el.getAttribute(a).trim();
      if (Object.prototype.hasOwnProperty.call(DICT, v)) el.setAttribute(a, DICT[v]);
    }
  }

  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { translateTextNode(root); return; }
    if (root.nodeType !== 1 && root.nodeType !== 11) return;
    if (root.nodeType === 1) translateAttrs(root);
    var tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    var n;
    while ((n = tw.nextNode())) {
      if (n.nodeType === 3) translateTextNode(n);
      else translateAttrs(n);
    }
  }

  function start() {
    walk(document.body);
    // 界面大量面板是交互后才插入 DOM 的，必须持续跟进
    new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (r.type === 'characterData') translateTextNode(r.target);
        else if (r.type === 'attributes') translateAttrs(r.target);
        else for (var j = 0; j < r.addedNodes.length; j++) walk(r.addedNodes[j]);
      }
    }).observe(document.body, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ATTRS,
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
