// 《铁冠之争》网页导出冒烟测试（TECH.md 第七节；结构沿用 games/emberfall3d/tools/smoke_web.js）。
// 在 1280 / 768 / 360 三个宽度下打开 play/：
//   1.1  引擎启动（IC_READY）、兼容渲染器、控制台无报错、页面无横向溢出、加载画面消失；
//   1.2  电脑：点击画面后按住 W 走动（IC_MOVED）、Esc 打开 / 关闭暂停菜单（IC_PAUSE）；
//        手机 / 平板：左半屏真实触屏拖动走动（IC_MOVED）、右半屏拖动转视角（IC_LOOK）、点「菜单」打开暂停菜单；
//        再打开 ?test=1 灰盒测试场，走几步截图。
//   2.3  霜渡镇 ?view=4（管家面前）：电脑按 E、按 1 两次接下主线，按 J 打开任务日志；手机 / 平板点右上角「任务」按钮打开任务日志（IC_QUEST），截图。
//   2.1  霜渡镇 ?view=3（更夫面前）：电脑按 E 打开对话、按 2 选第二个选项、Esc 结束；手机 / 平板真实点交互按钮与第一个选项（IC_DIALOG），截图。
//   3.1  酒馆 ?area=tavern&view=1（吧台前）：电脑按 E、手机 / 平板点交互按钮，和玛蒂尔达说话（IC_DIALOG open id=matilda），截图；
//        再打开 ?area=tavern&view=3（门内对着出口）：按 E / 点交互按钮走出酒馆，回到主街（IC_TRAVEL → IC_ARRIVE area=frostford），截图。
//   3.2  小教堂 ?area=chapel&view=1（奥尔本修士面前）：按 E / 点交互按钮和修士说话（IC_DIALOG open id=alban），截图；
//        墓园 ?area=churchyard&view=1（瓦伦家墓室门前）：按 E / 点交互按钮，铁门锁着（IC_INTERACT kind=door name=瓦伦家墓室的铁门），截图；电脑再在 view=0 截一张墓园全景。
//   2.4  霜渡镇 ?view=5（木桩假人面前）：电脑点击画面后按 F 两下（拔剑、轻击），再按一下左键出剑；手机 / 平板点两下「攻」按钮；要求打中木桩（IC_HIT），截图。
//   2.9  霜渡镇出生点：电脑按 V、手机 / 平板点「视角」切到第三人称（IC_CAMERA mode=third），截图。
//   A.1  切到第三人称后人物模型与动作库加载成功（IC_AVATAR loaded=true、IC_AVATAR role=idle）；电脑再按 F 拔剑、按住 F 蓄力（role=Sword_Attack 停在最高处）、按住 Q 格挡（role=block），各截一张图。
//   2.7  霜渡镇出生点：电脑按 K、手机 / 平板点右上角「角色」，打开角色面板（IC_CHAR open），截图。
//   2.8  霜渡镇：电脑按 F8 快速存档（IC_SAVE）→ 确认浏览器 localStorage 里有 ooglex.ironcrown.v1.quick → 刷新页面 → 按 F9 读档（IC_LOAD，场景重新载入）；
//        手机 / 平板点「菜单」→「存档 / 读档」打开存档面板（IC_SAVES open）；截图。
//   2.5  训练场 ?test=2：等敌人发现你、转入战斗（IC_ENEMY state=combat），电脑按住 Q、手机 / 平板真实按住「挡」，要求挡下一次攻击（IC_BLOCK），截图。
//   2.6  霜渡镇 ?view=6（破木箱前）：电脑按 E 打开搜刮面板（IC_LOOT open）、Esc 关上、按 I 打开背包（IC_BAG open）；
//        手机 / 平板先点右上角「背包」（IC_BAG open），再重新打开页面点交互按钮搜刮（IC_LOOT open）；截图。
//   1.3  测试场出生点对准灰盒 NPC（IC_TARGET）：电脑按 E、手机 / 平板点右下角交互按钮，要求和 NPC 说话（IC_INTERACT kind=npc），截图。
//
// 先在仓库根目录起静态服务器（gzip 传输，模拟线上 CDN）：
//   python3 games/ironcrown/tools/serve_gzip.py . 8765
//   node games/ironcrown/tools/smoke_web.js [截图目录] [地址]
// 需要全局安装的 playwright（云端开发环境自带 /opt/node22/lib/node_modules/playwright 与预装 Chromium）。
const path = require('path');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const outDir = process.argv[2] || '.';
const url = process.argv[3] || 'http://localhost:8765/games/ironcrown/play/';

async function waitLog(logs, prefix, tries = 40) {
  for (let i = 0; i < tries; i++) {
    const hit = logs.find(l => l.startsWith(prefix));
    if (hit) return hit;
    await new Promise(r => setTimeout(r, 250));
  }
  return '';
}

// 用 Chrome 调试协议发真实的触屏拖动（Playwright 的 touchscreen 只有点按）
async function touchDrag(cdp, id, x0, y0, dx, dy, ms) {
  const steps = 12;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0, id }] });
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x0 + dx * i / steps, y: y0 + dy * i / steps, id }] });
    await new Promise(r => setTimeout(r, 30));
  }
  await new Promise(r => setTimeout(r, ms));
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

(async () => {
  // 无头 Chromium 没有 GPU，用 SwiftShader 软件渲染 WebGL 2
  const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let failed = 0;
  for (const [w, h, name, mobile] of [[1280, 720, 'desk', false], [768, 1024, 'tab', true], [360, 740, 'phone', true]]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: mobile, hasTouch: mobile });
    const page = await ctx.newPage();
    const logs = [], errs = [];
    page.on('console', m => { logs.push(m.text()); if (m.type() === 'error') errs.push(m.text()); });
    page.on('pageerror', e => errs.push('pageerror ' + e.message));
    const t0 = Date.now();
    await page.goto(url);
    const ready = await waitLog(logs, 'IC_READY', 240);
    const bootSec = ((Date.now() - t0) / 1000).toFixed(1);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(outDir, `ic-${name}.png`) });
    const overlayGone = await page.evaluate(() => !document.getElementById('wl-loading'));
    const compat = !!ready && ready.includes('renderer=gl_compatibility') && ready.includes('web=true') && ready.includes('scene=frostford');
    const dpr = await page.evaluate(() => devicePixelRatio);
    let moved = '', look = 'n/a', pauseOpen = '', pauseClose = 'n/a';
    if (!mobile) {
      await page.mouse.click(w / 2, h / 2);             // 点击画面（尝试锁定指针）
      await page.keyboard.down('w');
      moved = await waitLog(logs, 'IC_MOVED', 16);
      await page.keyboard.up('w');
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-walk.png`) });
      await page.keyboard.press('Escape');
      pauseOpen = await waitLog(logs, 'IC_PAUSE open=true', 12);
      await page.waitForTimeout(400);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-pause.png`) });
      await page.keyboard.press('Escape');
      pauseClose = await waitLog(logs, 'IC_PAUSE open=false', 12);
    } else {
      const cdp = await ctx.newCDPSession(page);
      await touchDrag(cdp, 1, w * 0.22, h * 0.72, 0, -50, 1500);   // 左半屏：向上拖 = 向前走
      moved = await waitLog(logs, 'IC_MOVED', 12);
      await touchDrag(cdp, 2, w * 0.7, h * 0.45, 120, 0, 200);     // 右半屏：向右拖 = 转视角
      look = await waitLog(logs, 'IC_LOOK', 12);
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-walk.png`) });
      const ms = logs.find(l => l.startsWith('IC_MENU_SCREEN'));
      if (ms) {
        const [, mx, my] = ms.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
        await page.touchscreen.tap(mx / dpr, my / dpr);
        pauseOpen = await waitLog(logs, 'IC_PAUSE open=true', 12);
        await page.waitForTimeout(400);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-pause.png`) });
      }
    }
    // 对话（2.1）：更夫面前
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'view=3');
    let dOpen = '', dStep = '', dClose = 'n/a';
    if (await waitLog(logs, 'IC_TARGET name=更夫', 240)) {
      await page.waitForTimeout(400);
      if (!mobile) {
        await page.keyboard.press('e');
        dOpen = await waitLog(logs, 'IC_DIALOG open id=watchman', 12);
        await page.keyboard.press('2');
        dStep = await waitLog(logs, 'IC_DIALOG node=edric', 12);
      } else {
        const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
        if (us) {
          const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ux / dpr, uy / dpr);
        }
        dOpen = await waitLog(logs, 'IC_DIALOG open id=watchman', 12);
        await page.waitForTimeout(500);
        const opt = logs.filter(l => l.startsWith('IC_DIALOG_OPT')).pop();
        if (opt) {
          const [, ox, oy] = opt.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ox / dpr, oy / dpr);
        }
        dStep = await waitLog(logs, 'IC_DIALOG node=town', 12);
      }
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-dialog.png`) });
      if (!mobile) {
        await page.keyboard.press('Escape');
        dClose = await waitLog(logs, 'IC_DIALOG closed', 12);
      }
    }
    // 酒馆（3.1）：吧台前和玛蒂尔达说话；再从门内走出去回到主街
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'area=tavern&view=1');
    let tReady = '', tTalk = '', tOut = '';
    if (await waitLog(logs, 'IC_TARGET name=玛蒂尔达', 240)) {
      tReady = logs.find(l => l.startsWith('IC_READY') && l.includes('scene=tavern')) || '';
      await page.waitForTimeout(400);
      if (!mobile) {
        await page.keyboard.press('e');
      } else {
        const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
        if (us) {
          const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ux / dpr, uy / dpr);
        }
      }
      tTalk = await waitLog(logs, 'IC_DIALOG open id=matilda', 12);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-tavern.png`) });
    }
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'area=tavern&view=3');
    if (await waitLog(logs, 'IC_TARGET name=回到主街', 240)) {
      await page.waitForTimeout(400);
      if (!mobile) {
        await page.keyboard.press('e');
      } else {
        const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
        if (us) {
          const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ux / dpr, uy / dpr);
        }
      }
      tOut = await waitLog(logs, 'IC_ARRIVE area=frostford', 60);
      await page.waitForTimeout(1200);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-tavern-out.png`) });
    }
    // 小教堂与墓园（3.2）：和奥尔本修士说话；墓室铁门锁着
    async function useHere() {
      if (!mobile) {
        await page.keyboard.press('e');
      } else {
        const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
        if (us) {
          const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ux / dpr, uy / dpr);
        }
      }
    }
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'area=chapel&view=1');
    let cTalk = '', cCrypt = '';
    if (await waitLog(logs, 'IC_TARGET name=奥尔本修士', 240)) {
      await page.waitForTimeout(400);
      await useHere();
      cTalk = await waitLog(logs, 'IC_DIALOG open id=alban', 12);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-chapel.png`) });
    }
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'area=churchyard&view=1');
    if (await waitLog(logs, 'IC_TARGET name=瓦伦家墓室的铁门', 240)) {
      await page.waitForTimeout(400);
      await useHere();
      cCrypt = await waitLog(logs, 'IC_INTERACT kind=door name=瓦伦家墓室的铁门', 12);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-crypt.png`) });
    }
    if (!mobile) {
      logs.length = 0;
      await page.goto(url + (url.includes('?') ? '&' : '?') + 'area=churchyard&view=0');
      if (await waitLog(logs, 'IC_READY', 240)) {
        await page.waitForTimeout(2500);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-churchyard.png`) });
      }
    }
    // 任务日志（2.3）：管家面前
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'view=4');
    let qStart = 'n/a', qOpen = '';
    if (await waitLog(logs, 'IC_TARGET name=管家', 240)) {
      await page.waitForTimeout(400);
      if (!mobile) {
        await page.keyboard.press('e');
        await waitLog(logs, 'IC_DIALOG open id=steward', 12);
        await page.keyboard.press('1');
        await waitLog(logs, 'IC_DIALOG node=accept', 12);
        qStart = await waitLog(logs, 'IC_QUEST_EVENT started edric_missing', 12);
        await page.keyboard.press('1');
        await waitLog(logs, 'IC_DIALOG closed', 12);
        await page.waitForTimeout(300);
        await page.keyboard.press('j');
      } else {
        const qs = logs.find(l => l.startsWith('IC_QUEST_SCREEN'));
        if (qs) {
          const [, qx, qy] = qs.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(qx / dpr, qy / dpr);
        }
      }
      qOpen = await waitLog(logs, 'IC_QUEST open', 12);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-quests.png`) });
    }
    // 近战（2.4）：木桩假人面前
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'view=5');
    let atk = '', hit = '', mouseAtk = mobile ? 'n/a' : '';
    if (await waitLog(logs, 'IC_READY', 240)) {
      await page.waitForTimeout(800);
      if (!mobile) {
        // 先用 F 键（拔剑、轻击）验证打中木桩：无头 Chromium 在指针锁定状态下每次按鼠标都会补发一个 -640 像素的假位移，视角会被转走
        // （F 键不需要先锁定指针，所以先不点画面）
        await page.keyboard.press('f');                 // 拔剑
        await page.waitForTimeout(700);
        await page.keyboard.press('f');                 // 轻击
      } else {
        const as = await waitLog(logs, 'IC_ATTACK_SCREEN', 12);
        if (as) {
          const [, ax, ay] = as.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ax / dpr, ay / dpr);
          await page.waitForTimeout(700);
          await page.touchscreen.tap(ax / dpr, ay / dpr);
        }
      }
      atk = await waitLog(logs, 'IC_ATTACK kind=light', 16);
      hit = await waitLog(logs, 'IC_HIT target=木桩假人', 16);
      await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-melee.png`) });
      if (!mobile) {                                    // 再验证鼠标左键出剑（只看出招，不看命中）
        await page.waitForTimeout(1200);
        await page.mouse.click(w / 2, h / 2);           // 锁定指针
        logs.length = 0;
        // 软件渲染只有一两帧每秒，指针锁定可能晚一帧才生效（那一下又被当成「锁定」）：最多点两次
        for (let i = 0; i < 2 && !mouseAtk; i++) {
          await page.waitForTimeout(1200);
          await page.mouse.down();
          await page.waitForTimeout(60);
          await page.mouse.up();
          mouseAtk = await waitLog(logs, 'IC_ATTACK kind=light', 12);
        }
      }
    }
    // 背包与搜刮（2.6）：破木箱前
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'view=6');
    let lootOpen = '', bagOpen = '';
    if (await waitLog(logs, 'IC_TARGET name=破木箱', 240)) {
      await page.waitForTimeout(400);
      if (!mobile) {
        await page.keyboard.press('e');
        lootOpen = await waitLog(logs, 'IC_LOOT open id=frostford_crate', 12);
        await page.waitForTimeout(400);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-loot.png`) });
        await page.keyboard.press('Escape');
        await waitLog(logs, 'IC_LOOT closed', 12);
        await page.waitForTimeout(300);
        await page.keyboard.press('i');
        bagOpen = await waitLog(logs, 'IC_BAG open', 12);
      } else {
        const bs = logs.find(l => l.startsWith('IC_BAG_SCREEN'));
        if (bs) {
          const [, bx, by] = bs.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(bx / dpr, by / dpr);
        }
        bagOpen = await waitLog(logs, 'IC_BAG open', 12);
      }
      await page.waitForTimeout(400);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-bag.png`) });
      if (mobile) {
        logs.length = 0;
        await page.goto(url + (url.includes('?') ? '&' : '?') + 'view=6');
        await waitLog(logs, 'IC_TARGET name=破木箱', 240);
        const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
        if (us) {
          await page.waitForTimeout(400);
          const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(ux / dpr, uy / dpr);
        }
        lootOpen = await waitLog(logs, 'IC_LOOT open id=frostford_crate', 12);
        await page.waitForTimeout(400);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-loot.png`) });
      }
    }
    // 角色面板（2.7）
    logs.length = 0;
    await page.goto(url);
    let charOpen = '';
    let camMode = '', avatarLoad = '', avatarIdle = '', avatarArmed = 'n/a', avatarCharge = 'n/a', avatarBlock = 'n/a';
    if (await waitLog(logs, 'IC_CHAR_SCREEN', 240)) {
      await page.waitForTimeout(400);
      // 第三人称（2.9）：电脑按 V、手机 / 平板点「视角」
      if (!mobile) {
        await page.keyboard.press('v');
      } else {
        const vs = logs.find(l => l.startsWith('IC_CAMERA_SCREEN'));
        if (vs) {
          const [, vx, vy] = vs.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(vx / dpr, vy / dpr);
        }
      }
      camMode = await waitLog(logs, 'IC_CAMERA mode=third', 12);
      avatarLoad = await waitLog(logs, 'IC_AVATAR loaded=true', 40);
      avatarIdle = await waitLog(logs, 'IC_AVATAR role=idle', 20);
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-third.png`) });
      if (!mobile) {
        // 拔剑 → 按住 F 蓄力（剑举到最高处停住）→ 松开出重击 → 按住 Q 格挡；各截一张图
        await page.keyboard.press('f');
        avatarArmed = await waitLog(logs, 'IC_AVATAR role=idle_armed', 20);
        await page.waitForTimeout(600);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-third-armed.png`) });
        await page.keyboard.down('f');
        avatarCharge = await waitLog(logs, 'IC_AVATAR role=Sword_Attack', 20);
        await page.waitForTimeout(900);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-third-charge.png`) });
        await page.keyboard.up('f');
        await page.waitForTimeout(700);
        await page.keyboard.down('q');
        avatarBlock = await waitLog(logs, 'IC_AVATAR role=block', 20);
        await page.waitForTimeout(900);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-third-block.png`) });
        await page.keyboard.up('q');
        await page.waitForTimeout(500);
      }
      // 切回第一人称：视角会存进浏览器设置，不切回来后面几步就都在第三人称里跑
      if (!mobile) {
        await page.keyboard.press('v');
      } else {
        const vs2 = logs.find(l => l.startsWith('IC_CAMERA_SCREEN'));
        if (vs2) {
          const [, vx, vy] = vs2.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(vx / dpr, vy / dpr);
        }
      }
      camMode = camMode && await waitLog(logs, 'IC_CAMERA mode=first', 12) ? camMode : '';
      if (!mobile) {
        await page.keyboard.press('k');
      } else {
        const cs = logs.find(l => l.startsWith('IC_CHAR_SCREEN'));
        const [, cx, cy] = cs.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
        await page.touchscreen.tap(cx / dpr, cy / dpr);
      }
      charOpen = await waitLog(logs, 'IC_CHAR open', 12);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-char.png`) });
    }
    // 存档（2.8）
    logs.length = 0;
    await page.goto(url);
    let saved = 'n/a', stored = 'n/a', loaded = 'n/a', savesOpen = 'n/a';
    if (await waitLog(logs, 'IC_MENU_SCREEN', 240)) {
      await page.waitForTimeout(400);
      if (!mobile) {
        await page.keyboard.press('F8');
        saved = await waitLog(logs, 'IC_SAVE slot=quick', 12);
        stored = String(await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('ooglex.ironcrown.v1.')).join(',')));
        stored = stored.includes('ooglex.ironcrown.v1.quick') ? stored : '';
        logs.length = 0;
        await page.goto(url);
        await waitLog(logs, 'IC_MENU_SCREEN', 240);
        await page.waitForTimeout(400);
        await page.keyboard.press('F9');
        loaded = await waitLog(logs, 'IC_LOAD slot=quick', 12);
        // 读档会重新载入场景：等第二个 IC_READY
        for (let i = 0; i < 120 && loaded && logs.filter(l => l.startsWith('IC_READY')).length < 2; i++) await new Promise(r => setTimeout(r, 250));
        if (logs.filter(l => l.startsWith('IC_READY')).length < 2) loaded = '';
        await page.waitForTimeout(600);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-loaded.png`) });
      } else {
        const ms2 = logs.find(l => l.startsWith('IC_MENU_SCREEN'));
        const [, mx, my] = ms2.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
        await page.touchscreen.tap(mx / dpr, my / dpr);
        const ss = await waitLog(logs, 'IC_SAVES_SCREEN', 12);
        if (ss) {
          await page.waitForTimeout(300);
          const [, sx, sy] = ss.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          await page.touchscreen.tap(sx / dpr, sy / dpr);
        }
        savesOpen = await waitLog(logs, 'IC_SAVES open', 12);
        await page.waitForTimeout(500);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-saves.png`) });
      }
    }
    // 训练场（2.5）：敌人发现你 → 举剑格挡
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'test=2');
    let fight = '', guard = '';
    if (await waitLog(logs, 'IC_READY', 240)) {
      fight = await (async () => {
        for (let i = 0; i < 160; i++) {
          const hit = logs.find(l => l.startsWith('IC_ENEMY') && l.includes('state=combat'));
          if (hit) return hit;
          await new Promise(r => setTimeout(r, 250));
        }
        return '';
      })();
      await page.screenshot({ path: path.join(outDir, `ic-${name}-arena.png`) });
      if (!mobile) {
        await page.keyboard.down('q');
        guard = await waitLog(logs, 'IC_BLOCK', 120);
        await page.waitForTimeout(150);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-guard.png`) });
        await page.keyboard.up('q');
      } else {
        const gs = logs.find(l => l.startsWith('IC_GUARD_SCREEN'));
        if (gs) {
          const [, gx, gy] = gs.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
          const cdp = await ctx.newCDPSession(page);
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: gx / dpr, y: gy / dpr, id: 7 }] });
          guard = await waitLog(logs, 'IC_BLOCK', 120);
          await page.waitForTimeout(150);
          await page.screenshot({ path: path.join(outDir, `ic-${name}-guard.png`) });
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        }
      }
    }
    // 灰盒测试场
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'test=1');
    const range = await waitLog(logs, 'IC_READY', 240);
    const target = await waitLog(logs, 'IC_TARGET name=灰盒路人', 16);
    await page.waitForTimeout(500);
    let talk = '';
    if (!mobile) {
      await page.keyboard.press('e');
    } else {
      const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
      if (us) {
        const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
        await page.touchscreen.tap(ux / dpr, uy / dpr);
      }
    }
    talk = await waitLog(logs, 'IC_INTERACT kind=npc', 12);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(outDir, `ic-${name}-talk.png`) });
    if (!mobile) {
      await page.keyboard.down('w');
      await page.waitForTimeout(900);
      await page.keyboard.up('w');
    } else {
      const cdp = await ctx.newCDPSession(page);
      await touchDrag(cdp, 3, w * 0.22, h * 0.72, 0, -40, 700);
    }
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(outDir, `ic-${name}-range.png`) });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const ok = compat && overlayGone && !!moved && !!look && !!pauseOpen && !!pauseClose && range.includes('scene=test_range') && !!target && !!talk && !!dOpen && !!dStep && !!dClose && !!qStart && !!qOpen && !!hit && !!mouseAtk && !!fight && !!guard && !!lootOpen && !!bagOpen && !!charOpen && !!tReady && !!tTalk && !!tOut && !!cTalk && !!cCrypt && !!camMode && !!avatarLoad && !!avatarIdle && avatarArmed !== '' && avatarCharge !== '' && avatarBlock !== '' && !!saved && !!stored && !!loaded && !!savesOpen && errs.length === 0 && overflow <= 0;
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${w}x${h} | ${ready || '未启动'} | 加载画面${overlayGone ? '已消失' : '仍在'} | 走动：${moved || '没有移动'} | 转视角：${look || '没有转'} | 暂停：${pauseOpen || '没打开'} / ${pauseClose || '没关闭'} | 测试场：${range ? 'ok' : '未启动'} | 交互：${target ? '对准 NPC' : '没对准'}，${talk || '没说上话'} | 对话：${dOpen ? '打开' : '没打开'} / ${dStep || '选项没生效'} / ${dClose || '没结束'} | 任务：${qStart || '没接到'} / ${qOpen || '日志没打开'} | 酒馆：${tReady ? '进得去' : '没打开'} / ${tTalk ? '和玛蒂尔达说上话' : '没说上话'} / ${tOut || '没走出来'} | 教堂：${cTalk ? '和修士说上话' : '没说上话'} / 墓室：${cCrypt ? '铁门锁着' : '没对准'} | 近战：${atk ? '出剑' : '没出剑'} / ${hit || '没打中'} / 左键：${mouseAtk || '没出剑'} | 搜刮：${lootOpen || '没打开'} / 背包：${bagOpen || '没打开'} | 视角：${camMode || '没切换'} / 人物：${avatarLoad ? '加载' : '没加载'} / 待机 ${avatarIdle ? 'ok' : '无'} / 拔剑 ${avatarArmed === 'n/a' ? 'n/a' : avatarArmed ? 'ok' : '无'} / 蓄力 ${avatarCharge === 'n/a' ? 'n/a' : avatarCharge ? 'ok' : '无'} / 格挡 ${avatarBlock === 'n/a' ? 'n/a' : avatarBlock ? 'ok' : '无'} | 角色：${charOpen || '没打开'} | 存档：${saved || '没存上'} / ${stored ? '浏览器里有' : '浏览器里没有'} / ${loaded || '没读回'} / 面板：${savesOpen || '没打开'} | 训练场：${fight || '敌人没来'} / ${guard || '没挡住'} | 启动 ${bootSec}s | 溢出 ${overflow}px | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 3).join(' || ') : ''}`);
    await ctx.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
