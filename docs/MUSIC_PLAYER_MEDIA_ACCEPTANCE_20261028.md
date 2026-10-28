# 流光播放器：自动连播与外部媒体控制验收报告

日期：2026-10-28（Asia/Shanghai）
仓库：`254684589-max/ooglex-site`
基线：`cb7e3a2b58eb6ab2dee3edd9dc9590056503ec3d`
修复分支：`fix/music-playback-media-session`
结论：网页逻辑与真实 Chrome 回归通过；Android 已实现原生适配并通过 Java/API 类型编译检查。最终源码 `068bf7ec769305bf5b80b36b5917e017c87cebfe` 的独立分支 APK 构建、签名校验和产物上传通过；硬件验收仍为 PENDING。草稿 PR：[372](https://github.com/254684589-max/ooglex-site/pull/372)。未部署生产环境。

## 1. 回退基线与只读范围

在空的隔离副本展开指定基线，确认工作区无用户改动后，创建本地标签 `baseline/music-playback-20261028` 和独立修复分支。先阅读根目录 AGENTS、项目简报、路线图、更新日志和播放器 README，再检查 player.js、store.js、网页入口、MainActivity、Manifest、全部 Android Gradle 配置、Android APK 工作流及网站发布工作流。没有改动稳定分支、已发布 APK 或线上配置。

## 2. 实际故障与证据

下列行号均指基线文件，可用 `git show cb7e3a2:<path>` 核对。

| 缺陷 | 基线证据与可复现行为 | 修复后 |
|---|---|---|
| 换歌期间旧音频仍能推进新索引 | player.js:1595–1611 先移动索引，再 await resolveSrc，期间旧 src 仍在播放；1741–1757 的 ended 按新索引推进。延迟 IndexedDB 解析后触发旧曲结束，目标索引 1 实际变成 2 | 换歌先停止并卸载旧源；独立音源编号、播放尝试编号及 loading/ended 检查；旧事件与旧 promise 不得推进队列或覆盖状态 |
| 暂停无法取消未完成的换歌 | playIndex 在异步解析完成后无条件 play；toggle 在 src 为空时又创建请求。回归中暂停后原请求仍可播放或挂起 | 暂停撤销继续播放意图；晚到的音源可以就绪，但不能重新出声 |
| 坏地址卡住自动连播 | 1760–1763 的 error 只显示提示；音频 error 不会正常走 ended；失效曲停在原位 | 区分网络、解码、格式、主动中断；按现有模式有界跳过失败曲。单曲循环遇坏源停止，全部失败停止，避免无限重试 |
| 播放失败原因误报 | 1580–1586 除 AbortError 外均提示“点一下播放”，NotSupportedError 也被当成权限问题 | 只有 NotAllowedError 给权限提示；捕获同步异常和 promise rejection；最新请求的 AbortError 提示重试，过时请求忽略 |
| 系统媒体状态不完整 | 1620–1632 只写 metadata；全文没有 playbackState 更新；1780–1788 用同一个 try 注册全部动作，前项抛错会跳过后项 | metadata（优先使用曲目实际专辑名）、播放/暂停状态、时长和进度同步；每个动作独立注册，支持 play/pause/prev/next/seek/stop |
| APK 无独立系统媒体控制链路 | MainActivity 只有 WebView；Manifest 无媒体服务；Gradle 无媒体依赖；没有原生 MediaSession、回调和 MediaStyle 通知 | 增加单一原生 MediaSession，系统回调复用 JS 原有命令和队列；不添加第二个音频引擎 |

基线已存在 `setMediaPlaybackRequiresUserGesture(false)`，也已对部分过时 play 请求编号。不能把“再次添加这些函数”当作本次修复，更不能仅据此宣布后台、蓝牙、车辆已通过。仅凭现有日志无法断言用户设备上每次中断都来自同一根因；上述是本次实际复现的代码缺陷及确定缺失的 APK 控制链路。

## 3. 最小实现与支持范围

- 继续复用一个 HTMLAudioElement、现有 step/playIndex、循环/随机和收藏逻辑。普通 URL 同步进入 play 调用，本机 IndexedDB 才等待异步结果。废弃 blob URL 回收，重复脚本加载不会再次初始化。
- 顺序自然结束：下一首，末尾停止；列表循环：末尾回第一首；单曲循环：重播当前；随机：延续既有持续随机行为，并保留上一首历史；手动上一首/下一首仍跨列表边界。当前播放队列与展示对象分离，收藏变化不修改已选队列；全球曲库“加载更多”仍扩展同一队列对象。
- 网络明确离线时保留当前曲目和进度，联网后重试；用户暂停可取消自动恢复。等待/停滞 20 秒无进度时按失败策略处理。权限被浏览器或系统拒绝时停止并给出实际提示，不反复请求、不扫完整队列。
- 网页端：使用标准 Media Session。真实 Chrome 已验证；其他浏览器、蓝牙转发、移动系统后台调度仍取决于浏览器实现。不能保证 iOS/Safari 或厂商内置浏览器解除其播放限制。
- 新 APK：仅带 `OoglexMedia/1` 标记的外壳使用原生会话，网页不再为它注册另一套显式 Media Session。onJsPrompt 状态桥同时校验调用页面与主页面的 HTTPS 域名、端口和播放器路径，并限制包长；不向所有 frame 暴露 Java 对象。原生只收元数据/状态，系统控制经固定命令回到 JS；没有任意 JavaScript/系统命令接口。
- MediaPlaybackService 只在播放/缓冲时提升为 mediaPlayback 前台服务；暂停、终止失败或队列结束时退出前台并 stopSelf，仅在拥有 WebView 的 Activity 存在时保留绑定会话，便于恢复。页面离开、Activity 销毁、移除任务时清理；无开机启动、START_STICKY、轮询保活、唤醒锁或第二播放器。缓冲 30 秒原生兜底释放。音频焦点继续由实际播放音频的 WebView 管理，断开耳机广播请求暂停。
- 这不是 Android Auto 的可浏览媒体应用：没有新增 MediaBrowserService 或 Android Auto 内容目录。目标是普通蓝牙 A2DP/AVRCP、媒体按键及锁屏/通知控制；实际车机必须验收。Activity 被销毁/进程被系统终止后不承诺继续播放或从耳机重启。
- 复用 Android 系统 API，不增加 Media3/三方库，不改 minSdk 22、target/compileSdk 34、Java17、AGP8.5.2 或现有 Gradle 配置。Media3/独立原生音频引擎会扩大状态同步和队列迁移范围，本次没有引入。

## 4. 修改文件

| 文件 | 变化 |
|---|---|
| `apps/music-player/js/player.js` | 取消/事件/队列/失败恢复、网页媒体状态和原生命令桥 |
| `apps/music-player/index.html` | 仅升级 player.js 缓存版本到 20261028c |
| `android/music-player/app/src/main/java/com/ooglex/music/MainActivity.java` | 服务绑定、受限状态桥、生命周期清理、恢复失败回首页 |
| `android/music-player/app/src/main/java/com/ooglex/music/MediaPlaybackService.java` | 原生会话、回调、MediaStyle 通知和随播放运行的服务 |
| `android/music-player/app/src/main/AndroidManifest.xml` | 私有 mediaPlayback 服务及两项前台媒体服务权限 |
| `android/music-player/app/src/main/res/drawable/ic_media_notification.xml` | 系统媒体通知图标 |
| `tests/music-player/playback.test.mjs` | 无新增依赖的确定性故障/队列回归 |
| `tests/music-player/browser-smoke.mjs` | 使用真实 Chrome 和 HTTP 音频的本地冒烟测试 |
| `apps/music-player/README.md` | 支持边界、失败策略和测试命令 |
| `CHANGELOG.md` | 本次修复、原生适配与未部署状态 |
| `docs/MUSIC_PLAYER_MEDIA_ACCEPTANCE_20261028.md` | 本报告 |

## 5. 测试结果

环境：macOS x86_64；Node v24.14.0；真实无头 Chrome 156.0.8078.48；Temurin JDK 17 + 官方 AOSP Android34 API 桩。Chrome 使用独立临时用户目录和 HTTP 测试音频，不修改生产曲库、不访问用户浏览器存储、不假冒 Jamendo 实测。

| 项目 | 状态 | 实际证据/边界 |
|---|---|---|
| 网页语法与 git diff --check | PASS | 实际运行并退出 0 |
| 逻辑回归 17 项 | PASS | `node --test tests/music-player/playback.test.mjs`，17/17；涵盖旧 ended、晚到音源/拒绝、十次倒序异步解析、blob 回收、模式、失效队列、错误类型、离线恢复/暂停取消、媒体动作、收藏队列、路由竞态 |
| Chrome 正常结束自动下一首 | PASS | 实际 2 秒 WAV 自然结束，未合成 ended |
| Chrome 顺序/随机/单曲/列表循环 | PASS | 真实音频播放，末尾自然 ended 与循环重播；跳到末尾加快部分用例 |
| Chrome 十次快速切歌 | PASS | 最终停在第十次目标，只有一个 audio，无未处理 JS 异常或误报 |
| Chrome 真实断网/联网恢复 | PASS | DevTools 网络离线，等待联网后恢复原曲 |
| Chrome 真实 HTTP 404 | PASS | 后续失效地址有界遍历并停止，不无限循环 |
| Chrome Media Session 状态/元数据 | PASS | 检查实际播放/暂停时属性；不等同于系统锁屏 UI 通过 |
| Chrome 重复脚本与收藏存储 | PASS | 重复加载后下一曲只前进一步；收藏添加/取消仍用原键 |
| Chrome UI 三档宽度 | PASS | 360/768/1280，无横向溢出；截图人工检查 |
| Java 原生源码编译/API 类型检查 | PASS | javac --release 17 -encoding UTF-8，Android34 官方 API 桩；临时 R 只提供新增图标编号；6 项弃用警告，无错误。不是 APK 打包或运行测试 |
| Android XML 解析 | PASS | 全部原生 XML 解析；Manifest 服务声明与权限人工检查 |
| APK assemble / 签名验证 / 产物上传 | PASS | [最终 CI 40693078801](https://github.com/254684589-max/ooglex-site/actions/runs/40693078801)，最终源码 068bf7e；release 签名 1.0.8 / versionCode 8。生产 Release 步骤 SKIPPED |
| 现有网站 PR 构建 | PASS | [PR 构建 40693047623](https://github.com/254684589-max/ooglex-site/actions/runs/40693047623)，build 成功，deploy 为 SKIPPED |
| APK 安装 / Android lint | PENDING | 无连接真机；现有工作流仅 assemble 与签名验证，不包含 lint。没有把源码编译冒充安装运行 |
| 蓝牙耳机上一曲/下一曲/暂停/恢复 | PENDING | 无连接的 Android 真机与耳机；原生命令映射和 JS 回归通过不能冒充硬件通过 |
| Android 锁屏/通知栏元数据和控制 | PENDING | 需安装新 APK，核对标题/艺人/专辑/时长/状态与实际音频一致 |
| 蓝牙汽车音响/方向盘切歌 | PENDING | 无车辆/车机；应同时验证 AVRCP、连续点按、重复 key-down 防重复 |
| Android 息屏/后台/回前台 | PENDING | 无真机；需至少连续播放三首，并测试暂停、恢复、失败与任务移除后的服务退出 |
| 不同 Android/WebView 版本 | PENDING | 建议 API22/23、26/28、31/32、33/34、35/36；每项记录系统与 WebView 完整版本。旧 WebView 不保证支持现有 JS 语法；本次没有虚构覆盖 |
| Android 原生桥来源/后台限制/断耳机/音频焦点 | PENDING | 代码约束已检查；需真机验证，特别是 Android12+ 后台恢复限制与厂商省电策略 |
| Jamendo 实际在线长曲与中途断流 | PENDING | 本次使用隔离 HTTP 测试音频；接口代码/配置未变；还需真实 Jamendo 曲目端到端验证 |

同分支自动触发的重复 Android 构建因并发规则被取消，已由上述最终手动构建成功替代，不是测试 PASS 的依据。

截至本报告，已运行测试没有未解决 FAIL；PENDING 不是 PASS，原生硬件验收完成前不能宣称专项全量通过。

可复现命令（仓库根目录）：

```sh
node --check apps/music-player/js/player.js
node --test tests/music-player/playback.test.mjs
node tests/music-player/browser-smoke.mjs
# Chrome 可用 CHROME_BIN 指定；截图目录可用 MUSIC_TEST_OUTPUT 指定
# 具备 Android SDK/JDK17/Gradle8.7 后：
cd android/music-player
gradle --no-daemon assembleDebug lintDebug
```

真机验收：手动点第一首后自然播完三首；逐个切换模式并测试末曲；耳机/方向盘分别操作四种按键；锁屏、通知栏、熄屏 10 分钟、后台其他应用再返回；十次快速切歌；飞行模式后恢复和 404 音频；暂停后不自动复播；移除任务后不残留声音/前台服务。每次记录机型、系统版本、WebView 版本、耳机/车机型号、实际结果和日志。

## 6. 测试 APK 与联调前提

- 最终测试包：release 签名，包名 `com.ooglex.music001`，版本 `1.0.8` / `8`，180,323 字节；源码提交 `068bf7ec769305bf5b80b36b5917e017c87cebfe`。
- APK SHA-256：`5b4d7e51e4a4e35b6475df8a2d1950596f4171f25516a91e727d9780050f4eba`；下载后已重新计算，与 CI 元数据一致。
- 签名证书 SHA-256：`ed9e21a65adcd8453a8ebfd6b721a77f49c7914a6a8eda230c86506f6b2792bb`。这是公开证书摘要，不含签名私钥。
- **此 APK 仍打开线上 www.ooglex.com。配套网页脚本未部署，因此直接安装后不能据旧网页判定新原生桥已经联调成功。** 真机应在获授权的配套网页环境中验收；未授权不切换线上代码。CI 元数据的 `url` 仍是原生产下载位，不能据此认为线上文件已更新；请使用本次独立交付的测试文件。
- 覆盖安装前核对已装应用的签名和 versionCode；不要为测试卸载稳定应用或清除存储，以免丢失设备上的收藏。必要时使用备用测试设备。

## 7. 发布、数据影响与回退

- **需要重新编译 APK：是。** 新原生会话、通知和服务必须进入新安装包，保留应用 ID `com.ooglex.music001`，沿用原签名和递增 versionCode，避免卸载导致本机收藏丢失。不能仅发布网页就声称旧 APK 已获得可靠蓝牙控制。
- **需要重新部署网页：是，获得上线授权并验收后。** 新 APK 打开线上网页，新网页也必须包含新的状态桥；应协调发布两者。当前仓库的实际发布工作流是 GitHub Pages，并没有据此证明 Cloudflare Pages 是当前生产源。如果用户确实另外使用 Cloudflare Pages，则相同静态变更也需部署到对应站点；此次均未部署，不改路由/域名/Secrets。
- **现有网站：** 只影响播放器播放逻辑和 APK；不改其他栏目或 UI/CSS，不改 URL、曲库、音频文件、收藏键及结构、发行流程、主题、分享、播放列表数据。
- **Jamendo：** workers/jamendo-proxy、global.json、API 参数、白名单与许可规则均未变；修复只消费既有音频 URL，不新增代理、存储或接口依赖。发生坏源时可能按队列请求下一首，这是预期恢复行为。
- **用户收藏：** 不迁移、不清空、不覆盖用户存储，新增回归已检查原存储键。安装升级须保持签名；卸载清数据仍会丢失本机收藏，这是已有存储边界。
- **回退：** 未上线时关闭修复 PR 即可。上线后对本 PR 的合并提交执行 revert（如保留多个提交，则逆序 revert 本 PR 的全部提交）并按原发布流程部署；APK 使用原签名且更高 versionCode 构建回退版本，不能直接强装低 versionCode。网页与 APK 需要协调回退。固定基线标签及交付补丁保留原始证据，不重置或覆盖生产分支。

## 8. 官方依据

- [Android MediaSession](https://developer.android.com/reference/android/media/session/MediaSession)：系统媒体控制回调与会话。
- [Notification.MediaStyle](https://developer.android.com/reference/android/app/Notification.MediaStyle)：通知关联媒体会话 token。
- [媒体前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types#media)：Android14 对类型/权限的要求。
- [后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)：后台被拒绝时不能承诺静默恢复。
- [媒体通知权限豁免](https://developer.android.com/develop/ui/compose/notifications/notification-permission)：本次不为媒体会话通知额外索取普通推送通知权限。
- [WebChromeClient.onJsPrompt](https://developer.android.com/reference/android/webkit/WebChromeClient)：回调提供调用页面 URL，桥只确认固定状态消息。
- [W3C Media Session](https://www.w3.org/TR/mediasession/)：网页元数据、动作及播放状态契约；不能据 API 存在推断硬件支持。
