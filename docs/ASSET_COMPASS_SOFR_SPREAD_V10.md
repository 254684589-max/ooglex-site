# Ooglex SOFR V10｜正式日更最近成功状态（2026-11-23）

## 背景
- V8（PR #453）在GitHub Actions真实联网验证CheckMySwap与美国财政部完整六期限日期匹配，返回 `no_new_day`。
- V9（PR #454）正式日更证据记录机制经过独立CI，已合并main。
- 截至V10启动，仓库查询到的最近100条Actions记录中仍无SOFR日更工作流正式成功执行记录；生产历史只有2026-11-20一条。
- PR自动测试成功、V8只读联网成功，不等于schedule任务曾执行。预计首次下一计划运行是2026-11-24 UTC 03:35，GitHub可能延迟。

## V10实现
- `scripts/publish_swap_spread_health.py` 只接收正式采集生成的V9证据。仅 `ingestionExitCode==0` 且标记为 `new_observation` 或 `no_new_observation` 时，输出无报价的 `macro/swap-spreads-health.json`。
- `.github/workflows/asset-compass-sofr-spreads.yml`：正式采集成功后生成上一条成功采集状态，并连同真实历史文件变更一起暂存；使用 `git diff --cached --quiet` 正确识别首个未跟踪的状态JSON。失败时不会更新。原始报价文件不可被此心跳脚本写入。
- `macro/swap-spreads-health.js`：网页读取公开状态文件；显示最后一次**成功**时间、数据日期、归档观测数。状态文件未生成（404）时明确标示无已验证正式采集；超过3个日历日未成功则提示检查Actions。状态不代表没有后续失败。
- `macro/swap-spreads.html`：增加上述只读状态行，保留现有V2–V4曲线与研究内容。
- `tests/test_swap_spreads_health.py`：成功但无新日、成功追加、失败拒绝、模糊状态拒绝、非法证据拒绝和不包含报价校验。
- `.github/workflows/asset-compass-sofr-v10-check.yml`：PR回归CI。

## 权限及发布安全
只有main分支正式日更有write权限；PR测试 read-only。不会在PR提交行情文件，不会为展示UI制造任何模拟市场数据。首次真正成功日更后，生成 `swap-spreads-health.json`；此前网站显示未验证。GitHub后续失败无法更新此marker，超过3日会出现提醒，但不能保证及时揭露所有失败；检查GitHub Actions仍是权威执行记录。

## 下一验收步骤
1. PR专项CI通过后才合并。
2. 确认主分支下次 `schedule` / 手动 `workflow_dispatch` 真实运行结论、Artifact、产生的JSON与Actions时间一致。
3. 对比新老观测日期是否增加；相同日期应显示 `no_new_observation`，而不是声称实时更新。
4. 浏览器核对GitHub Pages/自定义域名是否部署新HTML和JSON，并完成360/768/1280像素布局验收。
5. CheckMySwap曲线为指示性估值，非可执行报价；历史批量回填与许可审核为独立事项。

## 状态
仅开发PR，尚未通过CI验收或生产合并。不将本阶段等同于日更已成功执行。
