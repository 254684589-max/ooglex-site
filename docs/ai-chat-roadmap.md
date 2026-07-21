# 万象智聊 · AI 聊天产品路线图

> 目标：把 `apps/ai-chat` 打造成 Ooglex 的旗舰 AI 产品——挂在网站上、可安装成
> App（PWA，同环球电波）、打开即聪明、并拥有别处没有的独家能力（站内实时数据）。
>
> 节奏：每天用闲置额度推进一小步，每一步独立可上线。

## 总体架构：一个产品壳，三个可插拔的大脑

| 大脑 | 说明 | 成本 |
| --- | --- | --- |
| A · 浏览器内模型 | WebLLM/WebGPU 在用户浏览器里跑开源小模型（Qwen-1.5B 等），免密钥、可离线 | 0 |
| B · 大模型 API | 现有 BYOK 模式 + Cloudflare Workers 免费代理（内置免费 key，如 glm-4-flash），普通访客打开即聊 | ≈0 |
| C · 离线小智 | 现有规则引擎，断网兜底彩蛋 | 0 |

差异化：给 AI 加**工具调用**，读取本站每日自动刷新的数据
（whats-latest 新闻、econ-calendar 财经日历、fear-greed 情绪、companies 市值、
radio 电台……），成为「Ooglex 的 AI 导游 + 财经助手」。

## 阶段一：产品化打底（PWA 与体验）

- [x] PWA 改造：manifest + service worker + 图标，可安装成 App（照 radio 模式）
- [x] Markdown 渲染完善（列表、表格、标题、链接、引用、分割线、代码块）
- [x] 多会话管理（抽屉列表、新建/切换/删除、自动标题、旧历史自动迁移）
- [x] 消息操作：复制、重新生成、编辑重发
- [x] 移动端细节打磨（发送按钮挤压、安全区、100dvh、键盘弹起贴底）
- [x] 首页卡片与 README 更新，突出新形态

## 阶段二：免密钥即用

- [x] WebLLM 接入：浏览器内跑 Qwen 小模型（WebGPU 检测、下载进度、流式生成、可停止、国内镜像源）
- [x] Cloudflare Workers 免费代理：代码与部署指南就绪（`workers/ai-proxy/`）。
      ⚠️ 待站长部署：按 README 十分钟部署后把 `apps/ai-chat/shared-config.json`
      置 `enabled: true` 即全站生效
- [x] 三大脑自动降级策略：共享通道 → 本地模型（已就绪才接手）→ 离线小智

## 阶段三：站内数据工具调用（独家能力）

- [x] 工具调用框架（OpenAI function calling，流式 tool_calls 拼装、多轮循环、
      不支持 tools 的服务商自动去工具重试）
- [x] 工具：今日要闻（whats-latest）
- [x] 工具：财经日历（econ-calendar）
- [x] 工具：市场情绪（fear-greed）
- [x] 工具：市值排行（companies）
- [x] 站内导航（navigate_ooglex）：AI 能介绍并带用户去任意小应用（含电台）

## 阶段四：训练实验（学习向，选做）

- [ ] 数据工程：把每日财经/新闻数据整理成指令微调数据集，存入仓库逐日积累
- [ ] 用 Colab/Kaggle 免费 GPU 对小模型做 LoRA 微调，产出「自己调教的模型」
- [ ] 微调后的模型转 WebLLM 格式，放回大脑 A 在浏览器里跑
- [ ] （纯学习）nanoGPT 字符级玩具模型，走通训练全流程

## 工作约定

- 每次会话完成 1~2 个勾选项，小步提交；完成后把本文件对应项打勾
- 纯静态 + 免费服务，不引入需要付费维护的后端
- Service Worker 绝不拦截跨域请求（LLM API / 数据接口），避免缓存坑
