# Tech Leaders Free V2

## Default architecture

The public page now defaults to the zero-X-API-cost path:

X official profile timeline Embed -> visitor browser -> Ooglex page.

The default page does **not** call:

- `/v1/tech-leaders/status`
- `/v1/tech-leaders/feed`

Therefore normal Free mode page views do not consume the Ooglex X API credits.

## 100-profile catalog

Leader metadata is stored in:

`apps/tech-leaders/leaders.json`

The catalog schema has a capacity of 100 profiles. The page reads this file and supports search across name, Chinese name, handle, company/role and tags.

To add another Free-mode profile, append one object to `leaders.json`. No page JavaScript change is required.

The current catalog contains six verified/curated entries. Jensen Huang continues to use the NVIDIA official account until a separately verified personal account is intentionally selected.

## Free mode

Free mode is the default when the URL has no `mode` parameter.

Example:

`/apps/tech-leaders/?leader=musk`

Only the selected person's official X timeline is loaded. Switching leaders performs a clean page navigation so only one timeline is active at a time.

Free mode can still fail when the visitor's browser/network cannot reach X, because the content is rendered by X's official third-party widget.

## Optional data mode

The existing paid backend remains intact as an explicit manual mode:

`/apps/tech-leaders/?leader=musk&mode=api`

Only this mode checks the backend and calls the X API feed.

Architecture:

X API -> Cloudflare Worker -> private R2 cache -> Ooglex-rendered cards.

The existing Worker secret remains:

`X_BEARER_TOKEN`

Do not commit the token to GitHub or Wrangler configuration.

Current data-mode backend whitelist remains the original six profiles. Expanding Free mode does not automatically expand the paid API whitelist; that should be done deliberately if/when those profiles need structured data, translation, summaries or analytics.

## Cost behavior

- Free mode: no Ooglex X API calls, so no X API Credits consumed by normal page browsing.
- Data mode: uses the existing 15-minute R2 cache and incremental `since_id` refresh logic.
- The X API secret can remain configured in Cloudflare. It is not used merely because it exists; the frontend must be explicitly opened in `mode=api` before the page calls the paid backend.
