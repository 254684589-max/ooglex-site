const BASE = process.env.GLOBAL_CAMS_LIVE_URL || 'https://www.ooglex.com/apps/global-cams/';
const ATTEMPTS = Number(process.env.GLOBAL_CAMS_VERIFY_ATTEMPTS || 18);
const DELAY_MS = Number(process.env.GLOBAL_CAMS_VERIFY_DELAY_MS || 5000);

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function markerSummary(html, app) {
  return {
    htmlV11: html.includes('环球实景 <span>V1.1</span>'),
    oldReturnTokyo: html.includes('回到东京'),
    oldRandomTop: html.includes('id="randomTop"'),
    oldRandomWindow: html.includes('id="randomWindow"'),
    viewerControls: html.includes('viewer-controls'),
    appMarkerSync: app.includes('getScreenCoords'),
    appViewerControls: app.includes('buildViewerControls'),
    appExitControl: app.includes("['close', '退出放大'"),
    appKeyboardNav: app.includes("event.key === 'ArrowLeft'") && app.includes("event.key === 'ArrowRight'"),
    appSwipeNav: app.includes("viewer.addEventListener('touchstart'") && app.includes("viewer.addEventListener('touchend'"),
    oldTopListener: app.includes("$('#randomTop')")
  };
}

function valid(summary) {
  return summary.htmlV11 &&
    !summary.oldReturnTokyo &&
    !summary.oldRandomTop &&
    !summary.oldRandomWindow &&
    summary.viewerControls &&
    summary.appMarkerSync &&
    summary.appViewerControls &&
    summary.appExitControl &&
    summary.appKeyboardNav &&
    summary.appSwipeNav &&
    !summary.oldTopListener;
}

let last = null;

for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
  const token = Date.now() + '-' + attempt;
  const pageUrl = new URL(BASE);
  pageUrl.searchParams.set('deploy_verify', token);
  const appUrl = new URL('./app.js', pageUrl);
  appUrl.searchParams.set('deploy_verify', token);

  try {
    const headers = {
      'User-Agent': 'Ooglex Global Cams Live Verify/1.1',
      'Cache-Control': 'no-cache, no-store, max-age=0',
      'Pragma': 'no-cache'
    };
    const [pageRes, appRes] = await Promise.all([
      fetch(pageUrl, { headers, redirect: 'follow' }),
      fetch(appUrl, { headers, redirect: 'follow' })
    ]);
    const [html, app] = await Promise.all([pageRes.text(), appRes.text()]);
    const summary = markerSummary(html, app);
    last = {
      attempt,
      pageStatus: pageRes.status,
      appStatus: appRes.status,
      pageAge: pageRes.headers.get('age'),
      appAge: appRes.headers.get('age'),
      pageCache: pageRes.headers.get('cache-control'),
      appCache: appRes.headers.get('cache-control'),
      pageEtag: pageRes.headers.get('etag'),
      appEtag: appRes.headers.get('etag'),
      summary
    };
    console.log('Global Cams live verify', JSON.stringify(last));

    if (pageRes.ok && appRes.ok && valid(summary)) {
      console.log('Global Cams live V1.1 verification passed:', pageUrl.origin + pageUrl.pathname);
      process.exit(0);
    }
  } catch (err) {
    last = { attempt, error: String(err && err.message || err) };
    console.warn('Global Cams live verify attempt failed:', JSON.stringify(last));
  }

  if (attempt < ATTEMPTS) await sleep(DELAY_MS);
}

console.error('Global Cams live V1.1 verification failed after retries:', JSON.stringify(last));
process.exit(1);
