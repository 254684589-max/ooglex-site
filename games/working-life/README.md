# 《打工》WORKING LIFE 1.0

第三人称 3D **赛博朋克都市人生模拟**游戏。2088 年，你带着 ¥2000、一部旧手机和一个行李箱走出新澜市中央火车站：
没有背景、没有工作、没有住处。先活过今晚——然后找工作、上班、学习、升职、租房、交朋友、投资、创业，
从「活下去」一步步走到「选择自己的人生」，达成五种结局之一，再继续无限人生。

- 引擎：**Godot 4.7.x 标准版** · GDScript · Compatibility 渲染器（WebGL 2 / OpenGL 3.3）
- 网页版：`/games/working-life/`（介绍页）→ `/games/working-life/play/`（游戏本体）
- 版本：**1.0.0**（`version.txt`、`godot/project.godot` 的 `config/version`）

## 启动方法

### 浏览器直接玩
打开网站 `games/working-life/`，点「开始游戏」。首次下载约 42 MB（压缩传输约 12 MB），之后浏览器缓存。
本地预览（仓库根目录）：
```bash
python3 -m http.server 8000     # 浏览器打开 http://localhost:8000/games/working-life/
```

### Godot 编辑器（macOS Apple Silicon 优先）
1. 安装 [Godot 4.7.x 标准版](https://godotengine.org/download)（macOS 版是 Universal，原生支持 Apple Silicon）。
2. 编辑器「导入」→ 选 `games/working-life/godot/project.godot` → F5 运行。
3. 命令行：`godot --path games/working-life/godot`（macOS 上是 `/Applications/Godot.app/Contents/MacOS/Godot`）。

### VS Code
装 `godot-tools` 插件，填好 Godot 可执行文件路径，打开 `games/working-life/godot/`。脚本缩进用 Tab。

### 自动化测试
```bash
GODOT=godot games/working-life/tools/run_tests.sh            # 语法检查 + 303 项自动化测试
GODOT=godot games/working-life/tools/run_tests.sh economy save_load   # 只跑某几组
```

### 导出
```bash
GODOT=godot games/working-life/tools/build_web.sh            # 测试 → Web 导出 → play/（文件名带内容哈希）
GODOT=godot games/working-life/tools/build_desktop.sh macos  # build/macos/WorkingLife.app（Universal，ad-hoc 签名）
GODOT=godot games/working-life/tools/build_desktop.sh windows linux
```
需要同版本导出模板（编辑器「编辑器 → 管理导出模板」下载）。`build/` 不入库。macOS 在非 Mac 主机上只能导出
ad-hoc 签名的 .zip（脚本会解压成 .app）；正式分发需要在 Mac 上用 Developer ID 签名并公证。

## 操作
| 按键 | 作用 | 按键 | 作用 |
|---|---|---|---|
| WASD | 移动 | Shift | 奔跑（耗体力） |
| 空格 | 跳跃 | 鼠标 / 滚轮 | 镜头 / 远近 |
| E | 主要交互（对话、购物、上班、面试、开门、睡觉） | F | 使用 / 拿起 / 放下 |
| 鼠标左键 | 执行当前动作 | Tab | 手机 |
| M | 城市地图 | I | 背包 |
| J | 任务 | C | 人物 |
| T | 时间 1× / 2× | Esc | 暂停菜单 / 关闭窗口 |

触屏：左下摇杆移动、右半屏拖动转视角、右下「交互 / 使用 / 跑 / 跳」、右上「手机 / 地图 / 菜单」。

## 玩法
- **主线 7 章**：活下来 → 第一份工作 → 真正的职业 → 选择方向 → 职业发展 → 财富积累 → 人生选择。
- **八条职业**（每条都有自己的小游戏）：便利店员工（收银）、餐厅服务员（上菜）、仓库员工（分拣）、建筑工人（3D 搬运）、
  办公室职员（文件归档）、程序员（找 Bug）、金融分析师（图表与方案）、公司管理者（管理决策）。
  申请 → 面试 → 录用 → 按时上班（迟到 / 请假 / 旷工）→ 评分 → 工资 / 奖金 / 绩效 → 升职 / 降职 → 辞职 / 解雇 / 跳槽。
- **六项技能** Lv.0～10：电脑、沟通、体能、管理、金融、技术。上课、读书、上班、在家练习、健身、聊天、任务都能涨。
- **属性**：体力、饱腹、心情、健康、压力（影响效率与速度），声望。饿、累、病过头会昏倒或住院。
- **住房五级**、**银行**、**投资**（虚构资产，游戏内经济周期驱动）、**创业**（招人、接项目、预算、分红、破产）。
- **17 位 NPC**：日程、关系（-100～100）、闲聊、送礼、任务、帮助（内推、打折、直接录用……）。
- **52 个任务**（17 主线 + 35 支线 / NPC / 职业任务）、**36 种随机事件**、昼夜、晴阴雨天气、公交 / 地铁 / 出租车。
- **五种结局**：普通人生、职业经理人、技术专家、创业成功、财务自由。在中央公园观景台播放结局，之后进入无限人生模式。
- **存档**：3 个存档位，每天睡醒自动保存，暂停菜单手动保存 / 读取。网页版存在浏览器 IndexedDB。

## 开发者工具
调试构建（编辑器里运行）或网页地址加 `?dev=1` 时，按 **F1** 打开开发者面板：加钱、改时间 / 天气、传送、改属性和技能、
完成当前任务、NPC 关系、入职任意职业、公司注资与模拟。正式发布（Release 导出）默认关闭。`?touch=1` 强制触屏界面。

## 工程结构（详见 ARCHITECTURE.md）
```
games/working-life/
├── index.html  img/            网站介绍页与截图
├── play/                       网页导出（build_web.sh 生成，勿手改）
├── tools/                      run_tests.sh · build_web.sh · build_desktop.sh · stamp_web_build.py · build_font.py · gen_audio.py
├── README.md CHANGELOG.md ARCHITECTURE.md GAME_DESIGN.md TEST_REPORT.md version.txt
└── godot/                      Godot 工程
    ├── autoload/  core/  player/  camera/  world/  buildings/  npc/  jobs/  quests/  events/
    ├── economy/  skills/  housing/  items/  investment/  business/  transport/  phone/  ui/  audio/  save/
    ├── data/  (*.json 全部内容数据)   scenes/  assets/  web/  tests/
```

## 素材与替换接口
- 美术：全部由代码生成（`world/city_builder.gd` + `buildings/building_kit.gd` + `world/mats.gd`）。换正式模型：
  人物保留 `CharacterModel` 的关节接口，或在模型里放 `AnimationPlayer` 并提供 Idle/Walk/Run/Interact/Carry/Sit/Work 动画，
  `AnimationController` 会自动改用它。
- 音频：`tools/gen_audio.py` 合成；按 `music_* / amb_* / sfx_*` 命名覆盖 `godot/assets/audio/` 下同名 wav 即可替换，缺文件不会报错。
- 字体：思源黑体子集（OFL），新增生僻字后运行 `tools/build_font.py`。

## 已知问题
- 画面是程序化低多边形占位风格，人物没有骨骼动画（程序化摆动）。
- 网页版首次加载较大（约 42 MB）；手机实机帧率未在真实 GPU 上测过（本环境只有软件渲染）。
- 室内较小时镜头会贴近人物；NPC 进出建筑是「走到门口 → 直线走到站位」，偶尔会穿过柜台。
- 网页版不支持遮挡剔除（导出模板未编译），桌面版中 / 高画质开启。
- 只有中文界面。每月按 30 天计（游戏日历）。
