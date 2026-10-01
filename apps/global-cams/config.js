window.OOGLEX_GLOBAL_CAMS = Object.freeze({
  // LIVE camera API. Windy API key remains server-side in Cloudflare Secret.
  apiBase: "https://ooglex-global-cams-api.zlq6600e.workers.dev",

  // WINDOW catalog + video delivery from Ooglex-owned Cloudflare R2/Worker CDN.
  // The browser falls back to ./windows.json if the CDN is temporarily unavailable.
  windowCdnBase: "https://windows-cdn.ooglex.com"
});
