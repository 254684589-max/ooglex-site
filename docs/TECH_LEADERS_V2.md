# Tech Leaders V2

## Goal

Replace fragile browser-side X embeds with an Ooglex-rendered feed:

X API -> Cloudflare Worker -> private R2 cache -> Ooglex frontend.

The browser talks only to `pro-api.ooglex.com` for the primary feed. If the X API secret is not configured, the page automatically falls back to the existing official X embed.

## Public endpoints

- `GET /v1/tech-leaders/status`
- `GET /v1/tech-leaders/feed?leader=musk&limit=8`

Supported leader ids:

- `musk` -> `@elonmusk`
- `huang` -> `@nvidia`
- `altman` -> `@sama`
- `su` -> `@LisaSu`
- `pichai` -> `@sundarpichai`
- `nadella` -> `@satyanadella`

## Cost controls

- Only whitelisted accounts are queryable.
- R2 cache TTL is 15 minutes.
- After the initial fetch, refreshes use `since_id` so the Worker requests only posts newer than the newest cached post.
- The latest 10 posts per leader are retained.
- If X is temporarily unavailable, cached data can be served for up to 7 days.

## Required secret

The Worker secret is:

`X_BEARER_TOKEN`

Do not commit the token to GitHub or Wrangler configuration.

Once the secret is present in the deployed `ooglex-pro-api` Worker, the frontend automatically switches from the official embed fallback to Ooglex-rendered cards. No frontend code change is required.
