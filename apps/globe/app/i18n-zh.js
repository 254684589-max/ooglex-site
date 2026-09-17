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
    // 指令栏折叠态的标签宽度有限（实测四个字会被截成「觉预设」），用两个字保证装得下
    'VISUAL PRESETS': '预设',
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
    // 首次启动对话框的四个入口 —— 用户打开页面第一眼看到的就是这些
    'LIVE CONTACTS': '实时目标',
    'Aircraft, vessels and nearby intelligence': '航班、船舶与周边情况（本站需服务端的图层不可用）',
    'SPACE MISSIONS': '航天任务',
    'Launches, spacecraft and orbital context': '发射记录、航天器与在轨情况',
    'ENVIRONMENTAL': '环境监测',
    'Live earthquakes and active fires, from USGS and NASA': '来自 USGS 的实时地震与 NASA 的活跃火点',
    'EXPLORE MANUALLY': '自由浏览',
    'Begin with a clean globe': '从一个干净的地球开始',
    'ESC to dismiss': '按 ESC 关闭',
    "It feels like a forbidden cockpit—then you realize the sources are public and the data is real.":
      '像是坐进了不该进的驾驶舱 —— 然后你发现这些数据源全是公开的，数据也都是真的。',
    "Don't show this again": '不再显示',
    'Tip: the GEV MIC button in the dock lets you talk to the map.':
      '提示：指令栏的语音按钮可以直接对地图说话（本站未配置语音服务）。',
    'ESC TO DISMISS': '按 ESC 关闭',
    'SUMMARY': '摘要',
    // 场景面板的预设与控件
    'Global Flights Radar': '全球航班雷达',
    'Orbital Watch': '在轨监视',
    'Thermal Threat Board': '热源态势板',
    'City Overload': '城市细节',
    'Omniscience Pullback': '全景拉远',
    'NEW': '新建', 'DEL': '删除', 'LOAD': '载入',
    'CAPTURE SHOT': '记录镜头', 'UPDATE SHOT': '更新镜头',
    'RETRO': '回溯',
    // 显示面板与语音条（手机上这几处最显眼）
    'HUD': '平显', 'LAYOUT': '布局', 'DENSITY': '密度',
    'Tactical': '战术', 'Operator': '操作员', 'Minimal': '精简',
    'HUD layout': '平显布局',
    'VOICE CONTROL': '语音控制',
    // 原文用的是间隔号 · 不是逗号 —— 整串精确匹配，写错一个字符就不生效
    'Hold Space to speak · tap Space to activate focused controls':
      '按住空格说话 · 轻点空格激活当前控件（本站未配置语音服务）',
    'Hold Space to talk': '按住空格说话',
    // 目标检测密度档位
    'DENSE': '密集', 'SPARSE': '稀疏', 'BALANCED': '均衡',
    // 图层取数失败的提示
    'OVERPASS TEMPORARILY UNAVAILABLE': 'OVERPASS 暂时不可用',
    'RETRYING': '正在重试',
    'RETRYING…': '正在重试…',
    'TEMPORARILY UNAVAILABLE': '暂时不可用',
    // 周边情况面板：这两条是 <br> 拆开的两个文本节点，整串不在字典里就会留英文
    'SELECT CONTEXT': '选择关注内容',
    'CONTACTS — nearest planes · vessels · sites': '实时目标 —— 最近的飞机 · 船舶 · 设施',
    'SPACE MISSIONS — launches & orbital assets': '航天任务 —— 发射记录与在轨目标',
    'Context mode': '关注内容',
    'Contact Context actions': '目标相关操作',
    'loading...': '加载中…',
    'just now': '刚刚',
    'stale': '数据过期',
    'Data provided by:': '数据来源：',
    'Clear selected data layers': '清除已选数据图层',
    'Available Space Missions': '可选航天任务',
    'Aircraft cockpit view': '航空器驾驶舱视角',
    'CCTV camera': '监控摄像头',
    'Bloom intensity': '泛光强度',
    'Cancel replay': '取消回放',
    'Cockpit Radio volume': '驾驶舱电台音量',
    'Cockpit display options': '驾驶舱显示选项',
    'Cockpit vision style': '驾驶舱视觉风格',
    'Camera pose — click a value to type': '相机姿态 —— 点击数值可直接输入',
    'CONTACTS': '目标',
    'CYCLE OFF': '循环关闭',
    'Contact panel': '目标面板',

    // ------------------------------------------------------- 顶部地球操作按钮
    'Visible map targets': '地图上可见的目标',
    'Globe actions': '地球操作',
    'Turn off all selected data layers': '关闭所有已选数据图层',
    'Copy share link': '复制分享链接',
    'Reset camera and return to full globe view': '相机复位，回到全球视角',
    'Reset to full globe view': '复位到全球视角',
    'Power up the globe': '启动地球',
    'POWER UP': '启动',
    'GROUND STATION · PROVIDER SETTINGS': '地面站 · 服务商设置',
    'SAVE KEYS': '保存密钥',
    'ESC to close': '按 ESC 关闭',
    'The Google Maps key buys the photorealistic planet — everything else stacks on top.':
      'Google Maps 密钥换来的是照片级真实地球 —— 其他图层都叠在它上面。',
    'Initializing photorealistic world...': '正在初始化照片级地球…',

    // ---------------------------------------------------------- 驾驶舱 HUD
    'COCKPIT': '驾驶舱',
    'Estimated destination direction': '预计目标方向',
    'Previous vision style': '上一个视觉风格',
    'Previous cockpit vision style': '上一个驾驶舱视觉风格',
    'Next vision style': '下一个视觉风格',
    'Next cockpit vision style': '下一个驾驶舱视觉风格',
    'Current aircraft heading': '当前航向',
    'Contact cockpit summary': '目标驾驶舱摘要',
    'Contact navigation': '目标切换',
    'Previous — prior visited contact in the 250 km window': '上一个 —— 250 公里内上一个看过的目标',
    'Next — nearest unvisited contact in the 250 km window': '下一个 —— 250 公里内最近的未看过目标',
    'Nearby cohort counts': '周边各类目标数量',
    'Enable cockpit weather effects': '开启驾驶舱天气效果',
    'Cockpit briefing carousel': '驾驶舱简报轮播',
    // 与上面可见文案的 'ESTIMATED FLIGHT PLAN' 用同一句 —— 同一内容不要两种译法
    'Estimated flight plan': '推算航路（非实际航迹）',
    'LIVE SIGNALS': '实时信号',
    'Live signals': '实时信号',
    'Cockpit briefing controls': '驾驶舱简报控制',
    'Cockpit briefing pages': '驾驶舱简报分页',
    'Previous briefing page': '上一页简报',
    'Next briefing page': '下一页简报',
    'Cycle briefing pages automatically every 9 seconds (Signals → News → Local). Pauses while you hover or focus the panel. Live signal data refreshes continuously either way.':
      '每 9 秒自动翻页（信号 → 新闻 → 本地）。鼠标悬停或面板获得焦点时暂停。无论是否翻页，实时信号数据都持续刷新。',
    'Latest regional news': '本地最新报道',
    'ACQUIRING REGIONAL NEWS': '正在获取本地报道',
    'Location-based information': '按位置的周边信息',
    'RESOLVING REGION': '正在确定所在区域',
    'SOURCE-BACKED EVENTS · NO SYNTHETIC NEWS': '均为有出处的事件 · 不生成虚构新闻',
    'Show Live Signals': '显示实时信号',
    'Show Regional News': '显示本地报道',
    'Show Local Info': '显示本地信息',
    'SIG': '信号', 'NEWS': '新闻', 'LOCAL': '本地',
    // 出处标识只翻连接词，服务名与域名原样保留 —— 署名照旧，界面不留英文句子
    'Weather data by Open-Meteo.com': '天气数据来自 Open-Meteo.com',
    'TEMP': '气温', 'WIND': '风', 'SKY': '天空', 'PRECIP': '降水', 'MM': '毫米',
    'Cockpit display and Radio controls': '驾驶舱显示与电台控制',
    'Expand Cockpit display options': '展开驾驶舱显示选项',
    'Expand Cockpit Radio controls': '展开驾驶舱电台控制',
    'Cockpit compact Radio controls': '驾驶舱精简电台控制',
    'Previous filtered radio station': '上一个筛选电台',
    'Play selected radio station': '播放所选电台',
    'Next filtered radio station': '下一个筛选电台',
    'ESC EXIT': 'ESC 退出',
    'C TOGGLE': 'C 切换',
    'View switcher': '视角切换',
    'Exit cockpit and return to full globe view': '退出驾驶舱，回到全球视角',
    'Reset cockpit to full globe view': '驾驶舱复位到全球视角',
    'RESET': '复位',
    'Exit cockpit view': '退出驾驶舱视角',
    'EXIT COCKPIT': '退出驾驶舱',
    'Cycles the nearest contacts of whatever type you select — planes, vessels, installations. Satellites track independently.':
      '在你选的类型里按由近到远轮换目标 —— 飞机、船舶、设施。卫星单独跟踪。',

    // -------------------------------------------------- 显示控制（识别叠加层）
    'Collapse panel': '收起面板',
    'Expand panel': '展开面板',
    'Intelligence HUD (H)': '情报 HUD（H）',
    'Layout': '布局',
    'Detection Overlay (D)': '识别叠加层（D）',
    'Detection overlay': '识别叠加层',
    'DETECT': '识别',
    'Detection label density': '识别标签密度',
    'Detection label allocation': '识别标签分配方式',
    'World-overlay fade distance outside the keyhole as a percentage of its radius':
      '叠加层在取景圈外的淡出距离，按圈半径的百分比计',
    'Detection fade distance': '识别淡出距离',
    'World-overlay label and card opacity beyond the fade distance':
      '超出淡出距离后叠加层标签与卡片的不透明度',
    'Detection opacity outside the keyhole': '取景圈外识别层的不透明度',
    'PARAMETERS': '参数',
    '3D aircraft — flat icons zoomed out, 3D models up close':
      '三维飞机 —— 远看是平面图标，近看是三维模型',
    '3D model coverage': '三维模型覆盖范围',
    'Scope — the circular viewport mask': '视域 —— 圆形取景遮罩',
    'Scope edge feather as a percentage of the keyhole radius': '视域边缘羽化，按取景圈半径的百分比计',
    'Scope edge feather': '视域边缘羽化',
    'Celestial ring — reveal the full globe': '星空环 —— 显示完整地球',
    'Hide UI chrome': '隐藏界面外框',
    'Bloom / Glow': '泛光 / 光晕',
    'Sharpening': '锐化', 'Sharpen': '锐化', 'Sharpen intensity': '锐化强度',
    'Return UI controls': '恢复界面控件',
    'EXIT CLEAN VIEW': '退出隐藏界面',

    // ------------------------------------------------------------ 视觉预设
    'Navigation, voice, and visual preset controls': '导航、语音与视觉预设控制',
    'Expand Visual Presets': '展开视觉预设',
    'Keep visual presets open': '保持视觉预设展开',
    'Pin visual presets': '固定视觉预设',
    'Show the globe without a visual filter.': '不加任何视觉滤镜显示地球。',
    'Emulate a green phosphor CRT with scanlines and screen curvature.':
      '模拟绿色荧光 CRT 显示器，带扫描线与屏幕曲率。',
    'Simulate night-vision goggles with green intensification and a tube vignette.':
      '模拟夜视仪的绿色增强与镜筒暗角。',
    'NVG': '夜视',
    'Simulate FLIR-style thermal contrast. Turn up Ironbow for color.':
      '模拟 FLIR 热成像的明暗对比。想要伪彩就调高 Ironbow。',
    'FLIR': '热成像',
    'Apply bright cel-shaded color and illustrated outlines.': '套用明亮的赛璐璐上色与插画描边。',
    'Anime': '动画',
    'Apply high-contrast monochrome film-noir grading.': '套用高对比黑白电影的调色。',
    'Noir': '黑白',
    'Add a cold, snowy whiteout treatment to the scene.': '给画面加上冷色调的风雪白化效果。',
    'Snow': '风雪',
    'Map source': '底图来源',
    'Style': '风格',

    // ------------------------------------------------------------ 定位面板
    'Keep location tray open': '保持定位栏展开',
    'Pin location tray': '固定定位栏',
    'Search any location': '搜索任意地点',
    'Search location by name or coordinates': '按名称或坐标搜索地点',
    'Search any location...': '搜索任意地点…',

    // -------------------------------------------------------- 监控摄像头面板
    'CCTV feed frame': '监控画面框',
    'SOURCE · UNKNOWN': '来源 · 未知',
    'Enable CCTV to load camera intersections': '开启监控摄像头后加载路口画面',
    'CCTV OFF': '监控已关闭',
    'NEAREST': '最近', 'FOCUS': '聚焦',
    'COVERAGE OFF': '覆盖范围已关闭',
    'AUTO HOP OFF': '自动跳转已关闭',
    'PROJECTION ON': '地面投影已开启',
    'CALIBRATION': '标定', 'ADJUST': '调整',
    'Drag the camera in the world: rings rotate, arrows move, handles set range/FOV':
      '在地图上拖动摄像头：圆环旋转，箭头平移，手柄设置距离与视场角',
    'Heading (compass °) — click to type': '航向（罗盘度）—— 点击可直接输入',
    'Pitch (° up/down) — click to type': '俯仰（上下度数）—— 点击可直接输入',
    'Horizontal FOV (°) — click to type': '水平视场角（度）—— 点击可直接输入',
    'Range / monitor-plane distance (m) — click to type': '距离 / 监视面距离（米）—— 点击可直接输入',
    'Mount height above ground (m) — click to type': '离地安装高度（米）—— 点击可直接输入',
    'North offset from catalog position (m) — click to type': '相对编目位置的北向偏移（米）—— 点击可直接输入',
    'East offset from catalog position (m) — click to type': '相对编目位置的东向偏移（米）—— 点击可直接输入',
    'SAVE CAL': '保存标定', 'RESET CAL': '重置标定',
    'SCENE SUMMARY': '画面摘要',
    'Enable CCTV to start camera-linked intelligence summaries.': '开启监控摄像头后开始生成画面情报摘要。',
    'Scene recipe': '场景配方',
    'EXPORT PRESETS': '导出预设', 'IMPORT': '导入', 'RUN LOG': '运行日志', 'Ready': '就绪',

    // ---------------------------------------------------------------- 电台
    'Internet radio companion': '网络电台',
    'Expand Radio': '展开电台',
    'Expand Radio section': '展开电台面板',
    'Compact Radio controls': '精简电台控制',
    'Compact Radio volume': '精简电台音量',
    'RADIO READY': '电台就绪',
    'STATION TAG': '电台标签',
    'Filter stations by station tag': '按标签筛选电台',
    'NO STATION SELECTED': '未选择电台',
    'Enable Radio, then choose a globe marker or use next.': '先开启电台，再点地图上的标记或按「下一个」。',
    'DIRECTORY BAND': '目录频段',
    'DRAG TO TUNE': '拖动调频',
    'Tune available internet radio stations': '在可用的网络电台里调频',
    'ALL · DRAG THE NEEDLE': '全部 · 拖动指针',
    'SNAPS TO AVAILABLE STATIONS': '自动吸附到可用电台',
    'Radio playback': '电台播放',
    'Previous station': '上一个电台', 'Next station': '下一个电台',
    'Previous filtered station': '上一个筛选电台', 'Next filtered station': '下一个筛选电台',
    'Play': '播放', 'Play selected station': '播放所选电台',
    'Stop radio playback': '停止电台播放',
    'Radio volume': '电台音量', 'Radio off': '电台已关闭',
    'STATION SITE': '电台网站',
    // 目录服务名（Radio Browser）是出处标识，原样保留
    'DIRECTORY: RADIO BROWSER': '目录：Radio Browser',
    'Audio connects directly to the broadcaster after you press play. Your IP is visible to that broadcaster.':
      '按下播放后音频直连广播方，对方能看到你的 IP。',

    // ------------------------------------------------------ 目标周边 / 航天任务
    'SEARCH NEARBY SITES': '搜索附近设施',
    'Reclassify as TR-3B': '重新标记为 TR-3B',
    'Reclassify tracked contact as TR-3B': '把跟踪目标重新标记为 TR-3B',
    'CONTACTS CONTEXT OFF': '目标周边情况已关闭',
    'SELECT CONTACTS TO LOAD OBSERVED / MAPPED PROXIMITY': '选择目标以加载观测 / 已标注的周边情况',
    'AVAILABLE MISSIONS': '可选航天任务',
    'SELECT A MISSION TO INSPECT': '选一个任务查看',
    'LOADING 30-DAY MISSION INDEX': '正在加载近 30 天任务索引',
    'TAB PREVIEWS · ENTER / SPACE SELECTS': 'Tab 预览 · 回车 / 空格 选择',
  };

  /* CSS 的 text-transform: uppercase 会让截图上显示 MODELS、DOM 里其实是
     `Models` —— 照着截图把键写成大写，运行时就永远命中不了。这一类漏翻曾经栽了
     一整片：Density / Allocation / Models / Proximity / Scope / Feather /
     Celestial / Bloom / Normal / Layout / Style…
     所以在精确匹配之后补一层**折叠大小写**的查找。

     它不放松文件头第 1 条安全约束：依旧是「整串命中白名单」，不做子串替换；
     图标连字（`arrow_forward`、`chevron_left` 这类）任何大小写形式都不在 DICT
     里，折叠也命不中。两个键折叠后同名但译文不同时，两个都不进折叠表 ——
     宁可漏翻，也不能翻错。 */
  var FOLDED = (function () {
    var map = Object.create(null), clash = Object.create(null);
    Object.keys(DICT).forEach(function (k) {
      var f = k.toLowerCase();
      if (f in map) { if (map[f] !== DICT[k]) clash[f] = 1; return; }
      map[f] = DICT[k];
    });
    Object.keys(clash).forEach(function (f) { delete map[f]; });
    return map;
  })();

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
    // 图层开关的 aria-label：`${图层名}: ON|OFF`
    [/^(.+): (ON|OFF)$/, function (_m, name, st) {
      return lookup(name) + '：' + (st === 'ON' ? '开' : '关');
    }],
    // 面板披露控件
    [/^Collapse (.+) panel$/, function (_m, n) { return '折叠' + lookup(n) + '面板'; }],
    [/^Expand (.+) panel$/, function (_m, n) { return '展开' + lookup(n) + '面板'; }],
    [/^Close (.+)$/, function (_m, n) { return '关闭' + lookup(n); }],
    [/^Open (.+)$/, function (_m, n) { return '打开' + lookup(n); }],
    /* 读数占位：值可能是 `--`、数字或角度，标签要翻、值要原样留下。
       这些在字典里也有「光标签」的条目（HDG/FOV/RANGE…），字典先命中，
       带值的形式落到这里。 */
    [/^DEST (.+)$/, '目标 $1'],
    [/^HDG (.+)$/, '航向 $1'],
    [/^PITCH (.+)$/, '俯仰 $1'],
    [/^FOV (.+)$/, '视场角 $1'],
    [/^RANGE (.+)$/, '距离 $1'],
    [/^HGT (.+)$/, '高度 $1'],
    [/^CAL · (.*)$/, '标定 · $1'],
    [/^📍 Location: (.*)$/, '📍 定位：$1'],
    [/^Landmark: (.*)$/, '地标：$1'],
    // 视觉风格切换按钮的提示，中间嵌着风格名 —— 风格名再查一次字典
    [/^Current style: (.+) — click for next$/,
      function (_m, n) { return '当前风格：' + lookup(n) + ' —— 点击切换下一个'; }],
    [/^Current cockpit vision style: (.+)\. Activate for next style\.$/,
      function (_m, n) { return '当前驾驶舱视觉风格：' + lookup(n) + '。按一下切换下一个。'; }],
    /* 披露控件的宽版本。必须排在上面带 `panel` 的两条**后面** —— 先匹配者胜，
       否则 `Expand Radio panel` 会被这条吃掉，翻成「展开Radio panel」。 */
    [/^Expand (.+)$/, function (_m, n) { return '展开' + lookup(n); }],
    [/^Collapse (.+)$/, function (_m, n) { return '折叠' + lookup(n); }],
  ];

  /** 字典未命中时，尝试锚定正则；都不中就原样返回 null。
      替换目标可以是字符串（用 $1 引用捕获组）或函数（用于需要再查字典的场合）。 */
  function translateComposite(key) {
    for (var i = 0; i < PATTERNS.length; i++) {
      var re = PATTERNS[i][0], to = PATTERNS[i][1];
      if (!re.test(key)) continue;
      return typeof to === 'function' ? key.replace(re, to) : key.replace(re, to);
    }
    return null;
  }

  /** 查字典（含折叠大小写），查不到就原样返回 —— 用于组合串里嵌的图层名/面板名。 */
  function lookup(name) {
    if (Object.prototype.hasOwnProperty.call(DICT, name)) return DICT[name];
    var f = String(name).toLowerCase();
    return f in FOLDED ? FOLDED[f] : name;
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

  /** 统一查找：先查字典（整串精确），再试锚定正则。查不到返回 null。
      文本节点与属性必须走同一条路径 —— 否则新增规则容易只接进一半。 */
  function translate(key) {
    if (Object.prototype.hasOwnProperty.call(DICT, key)) return DICT[key];
    var f = key.toLowerCase();
    if (f in FOLDED) return FOLDED[f];
    return translateComposite(key);
  }

  /** 查表用的键：去首尾空白，再把内部连续空白折成一个空格。
      HTML 本来就这么折叠空白 —— 屏幕上看到的是折叠后的那一串，所以字典按
      折叠后的形式写。不折叠的话，模板里换行缩进的文案（`<span>\n  FOO\n</span>`）
      会因为键里带换行而永远查不到。 */
  function normalizeKey(raw) {
    return raw.replace(/^\s+|\s+$/g, '').replace(/\s+/g, ' ');
  }

  /** 只在整段文字完整命中时替换，并保留原有首尾空白。 */
  function translateTextNode(node) {
    var raw = node.nodeValue;
    if (!raw) return;
    var key = normalizeKey(raw);
    if (!key) return;
    var hit = translate(key);
    if (hit === null || hit === undefined || hit === key) return;
    if (inSkippedSubtree(node)) return;
    var edges = /^(\s*)[\s\S]*?(\s*)$/.exec(raw);
    node.nodeValue = edges[1] + hit + edges[2];
  }

  function translateAttrs(el) {
    if (inSkippedSubtree(el)) return;
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      if (!el.hasAttribute || !el.hasAttribute(a)) continue;
      var v = normalizeKey(el.getAttribute(a));
      var hit = translate(v);
      // 命中且确有变化才写回；相等时写回会让 MutationObserver 无谓地再跑一轮
      if (hit !== null && hit !== undefined && hit !== v) el.setAttribute(a, hit);
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

  /* 覆盖率闸门用的钩子：verify-i18n-coverage.mjs 会把构建产物 index.html 里所有
   * 作者写死的界面文案抽出来，逐条问这里「查得到中文吗」。这样「面板里还有英文」
   * 不再靠截图发现 —— 它是 CI 里一条确定性的断言。 */
  window.OoglexGlobeI18n = Object.freeze({ translate: translate, size: Object.keys(DICT).length });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
