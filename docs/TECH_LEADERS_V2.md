# Tech Leaders Free V4.1

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

The catalog schema is now V4 with capacity for 180 profiles. The production catalog currently contains 108 curated leaders/accounts. The page supports name/handle/company/ticker search, multi-category membership, and a dedicated S&P 500 CEO layer.

To replace or maintain a Free-mode profile, edit one object in `leaders.json`. Each entry now includes a primary `category`, and the top-level catalog includes the nine supported categories. No page JavaScript change is required for ordinary catalog maintenance.

The current catalog contains 100 curated entries across nine primary filters: AI, semiconductors, cloud, robotics, space, consumer technology, software, fintech and venture capital. The UI exposes these as client-side category filters with counts. Jensen Huang continues to use NVIDIA's official account; selected leaders without a stable public personal account may similarly use the related company's official X account.

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

## Category filters

The public page includes these primary filters:

- 标普500 CEO
- AI
- 芯片
- 云计算
- 网络安全
- 软件
- 汽车
- 工业
- 消费零售
- 金融
- 医疗
- 能源
- 航空航天
- VC

The selected category is reflected in the URL via the `category` query parameter and combines with text search. The category filter is purely client-side and does not call the paid X API.


## Roster UI

The 100-profile directory is collapsed by default to 18 cards when viewing the unfiltered "全部" catalog. Users can expand all 100 or collapse back to 18. Category filters and text search show their matching results directly, so smaller result sets do not require an extra fold step.

Each leader card now shows:

- public X avatar when available
- deterministic initials fallback when the avatar cannot be loaded
- public X handle
- company / institution and title descriptor from the catalog `role` field

Avatar images are requested lazily from Unavatar's X avatar endpoint and use `referrerpolicy="no-referrer"`. This does not consume Ooglex X API credits. Unavatar attribution is included in the Tech Leaders footer, and the privacy page discloses the third-party avatar request.

The selected-profile panel also displays the same avatar/fallback and company/title descriptor.


## V3 S&P 500 CEO layer

V3 adds a quality-gated public-company CEO layer. The admission rule is intentionally strict:

1. current CEO
2. identifiable personal public X account
3. real posting history / usable public activity

The first verified V3 cohort adds eight new leaders:

- Jim Farley — Ford — @jimfarley98
- Chuck Robbins — Cisco — @ChuckRobbins
- Bill McDermott — ServiceNow — @BillRMcDermott
- Marvin Ellison — Lowe's — @MarvinREllison
- George Kurtz — CrowdStrike — @George_Kurtz
- Nikesh Arora — Palo Alto Networks — @nikesharora
- Albert Bourla — Pfizer — @AlbertBourla
- Mary Barra — General Motors — @mtbarra

After de-duplicating against the existing catalog and tagging existing qualifying entries, the 标普500 CEO layer currently contains 24 profiles; the broader S&P 500 decision-maker layer contains 26 CEO/founder profiles.

Each qualifying entry can include ticker, sp500_ceo=true, index_tags, verified_personal_x=true, verified_at, and categories[].

The Free Embed path remains the default. Expanding this catalog does not itself increase X API cost.


## V4 S&P 500 decision-maker audit — 2026-09-19

V4 changes the index layer from a CEO-only boolean into a decision-maker model while keeping backward compatibility with `sp500_ceo`.

- Catalog: 109 active production leaders; capacity 180.
- S&P 500 CEOs: 24.
- S&P 500 decision makers (CEO and/or founder): 26.
- Jensen Huang now uses the verified personal handle `@JensenHuang`, not the NVIDIA company account.
- Adena Friedman (`@adenatfriedman`, Nasdaq / NDAQ) is added as a verified S&P 500 Chair & CEO.
- Brian Chesky, Dara Khosrowshahi, Vlad Tenev, Jack Dorsey and Jeff Bezos are explicitly tagged with S&P 500 membership/leader-type metadata.
- Tony Xu remains `candidate`; Adam Foroughi remains `hold`. Neither is exposed in the production leader list until personal-X verification meets the same threshold.
- New fields include `sp500_member`, `sp500_ticker`, `leader_types`, `sector`, `themes`, `x_identity_verified`, `admission_status`, plus verification timestamps on audited records.
- Audit policy: role review every 90 days; downgrade after 180 days without substantive X activity; archive from the default flow after 365 days of inactivity.
- The frontend S&P filter is now “标普500 决策者” and distinguishes CEO vs Founder badges.
- Data mode checks the Worker-supported leader list before making a feed request, preventing an avoidable paid X API call for unprovisioned profiles.


## V4.1 avatar asset standardization — 2026-09-19

All 109 production leaders now have explicit avatar metadata: avatar_url, avatar_source, avatar_status, avatar_fallback and avatar_updated_at.

Source priority: explicit official portrait; public X profile avatar via Unavatar; local initials/silhouette SVG generated in the browser.

The frontend no longer hides a broken avatar image. If the remote avatar fails, the image is replaced with a local data-URI fallback, so cards, selected profile and API timeline always retain a visible avatar.

The roster UI includes an avatar audit control showing configured/total avatars and a 待补 filter. Expected configured count in this release: 109/109.


## V4.2 self-hosted avatar delivery — 2026-09-19

V4.2 removes the browser's runtime dependency on Unavatar for leader portraits.

Delivery path:

1. Browser requests `https://pro-api.ooglex.com/v1/tech-leaders/avatar?handle=...`.
2. The Ooglex Cloudflare Worker checks the private `PRO_DATA` R2 bucket.
3. On cache miss, the Worker fetches the public X-profile portrait server-side (or an explicit official override such as Jensen Huang), validates that the response is an image and is within the size limit, then stores the bytes in R2.
4. Subsequent visitors receive the portrait from Ooglex/R2 rather than directly from the third-party avatar host.
5. If a portrait cannot be fetched, the page still falls back to the local initials/silhouette SVG.

The catalog now points all 109 production leaders at the Ooglex avatar endpoint and records `avatar_status: "self_hosted"`.

The PRO API deployment workflow runs `scripts/tech-leaders/warm_avatars.py` after deployment. The warmup checks every active leader and fails the workflow unless all avatar endpoints return a real image. This turns the old metadata-only 109/109 count into a deployment-time HTTP verification.

The avatar endpoint is deliberately limited to valid X-style handles and only fetches from the fixed Unavatar X-profile endpoint plus explicit hard-coded official overrides; it does not accept arbitrary upstream URLs.


## Free Native Feed V1 — 2026-09-19

Free mode now tries a zero-X-API native timeline before loading the official X Embed.

Flow:

1. Browser requests `/v1/tech-leaders/free-feed?handle=...`.
2. The Cloudflare Worker requests X's public syndication timeline HTML.
3. The Worker extracts public timeline items from embedded JSON, normalizes text/media/metrics, and stores the result in R2.
4. All visitors reuse the cached result for 10 minutes; stale data may be served for up to 24 hours when the public source is temporarily unavailable.
5. This route never calls `api.x.com` and returns `uses_x_api: false`.
6. If public syndication yields no usable posts, the browser automatically falls back to the existing official X Embed.

This is intentionally an experimental free path because X public syndication is not a contractual API and its HTML/JSON structure can change. The paid `/v1/tech-leaders/feed` path remains separate and unchanged.


## Free Native Feed V2 — 2026-09-19

The first Cloudflare-to-X syndication smoke test returned HTTP 429, so the free experiment now uses a source ladder:

1. X public syndication (official embed data, no X API credentials).
2. FxEmbed/FxTwitter public API as a server-side fallback.
3. Existing X official Embed in the browser if both native sources fail.

The native route still never calls `api.x.com` and continues to return `uses_x_api: false`. The trial remains scoped to `@ZLQ6600E` before broader rollout.


## Free Mode Hard Isolation — 2026-09-19

Free mode is now structurally separated from the paid X Developer API path.

- `/v1/tech-leaders/free-feed` never calls `api.x.com`.
- `/v1/tech-leaders/free-profile` never calls `api.x.com`; it uses only public sources and a separate R2 cache namespace.
- The existing `/v1/tech-leaders/profile` and `/v1/tech-leaders/feed` remain available only for explicit Data mode.
- Initial native free-feed rollout: `@ZLQ6600E`, `@elonmusk`, `@JensenHuang`, and `@sama`.
- All remaining catalog entries stay on the official X Embed fallback until the native path is validated at broader scale.


## Free Profile Public Fallback — 2026-09-19

The first strict free-profile smoke test showed X public syndication/follow-button sources returning no usable profile metrics for the four pilot accounts. Free profile lookup now keeps the zero-X-API contract and adds FxEmbed/FxTwitter `GET /2/profile/{handle}` as a public fallback. The endpoint still never calls `api.x.com`.


## Native Free Feed Rollout 24 — 2026-09-19

After successful production validation on the initial four accounts, the native free-feed allowlist is expanded to 24 high-interest leaders:

`Zheng Yi, Elon Musk, Jensen Huang, Sam Altman, Lisa Su, Sundar Pichai, Satya Nadella, Tim Cook, Jeff Bezos, Andy Jassy, Demis Hassabis, Dario Amodei, Mustafa Suleyman, Yann LeCun, Andrew Ng, Fei-Fei Li, Ilya Sutskever, Mira Murati, Greg Brockman, Aravind Srinivas, Andrej Karpathy, Marc Benioff, Michael Dell, Marc Andreessen`.

The architecture remains on-demand: only the selected person's feed is fetched. Failure of the native public-source path still falls back to the official X Embed. Free mode remains hard-isolated from `api.x.com`.


## Native Free Feed Full Personal-Account Rollout — 2026-09-19

The native free-feed selection is no longer maintained as a hand-written allowlist. Free mode now automatically enables the Ooglex native feed for every catalog row that is active, has an X handle, and is explicitly confirmed as a personal X account (`x_identity_verified`, `verified_personal_x`, or the catalog's confirmed-personal-account note).

Current catalog coverage: 105 confirmed personal X accounts.

Five non-personal/special entries remain on the official X Embed path:

- Lip-Bu Tan → `@intel` company account
- Hock Tan → `@Broadcom` company account
- Christophe Fouquet → `@ASMLcompany` company account
- Sanjay Mehrotra → `@MicronTech` company account
- Boston Dynamics → `@BostonDynamics` official company account

Only the selected profile is fetched on demand, so enabling all 105 accounts does not trigger 105 upstream requests on page load. Production smoke tests sample 20 representative personal accounts while the catalog coverage check validates the full selection rule. Free mode remains hard-isolated from `api.x.com`.


## Tech Leaders Media Rendering Repair — 2026-09-19

Native free-feed media now uses a dedicated same-origin Cloudflare Worker proxy at `/v1/tech-leaders/media`.

Changes:

- Correct FxEmbed/FxTwitter media normalization to match its current API schema: photos use direct `url`; videos/GIFs use direct `url`, `thumbnail_url`, and `formats[]`.
- Proxy approved X/FxEmbed media hosts through `pro-api.ooglex.com` so visitors do not need direct browser access to `pbs.twimg.com` / `video.twimg.com`.
- Render photos as images and GIF/video media as HTML5 video with poster fallback.
- Retry the original direct URL if the proxy fails, then show a clean original-post fallback instead of a broken image icon.
- The media proxy is allowlisted to known media hosts and never calls `api.x.com`.
- Deployment smoke tests verify a live @sundarpichai media asset through the proxy when a media item is available.


## Free Feed Progressive Display — 2026-09-19

The native free timeline now follows a progressive display policy:

- Show the latest 10 posts by default.
- If more are available, keep a progressive `加载更多 10 条` / `Load 10 more` control until the returned set is exhausted.
- A single page session displays at most 100 posts per selected account.
- The browser requests up to 100 free-feed items for the selected account, while inserting only 10 at a time into the DOM to protect mobile performance.
- The free backend requests X public syndication and FxTwitter in parallel, de-duplicates by post ID, prefers the richer copy when the same post is returned by both sources, and sorts the merged result newest-first.
- FxTwitter list responses are cursor-paginated in 20-post pages; the backend follows `cursor.bottom` for up to five pages to reach the 100-post session ceiling when upstream data is available.
- No permanent post archive is created. R2 remains a replaceable cache, with a 10-minute fresh TTL and 12-hour stale fallback.
- The actual number available can be below 100 when upstream public sources expose fewer posts.
- Zheng Yi's `local_only` profile remains unchanged and continues to display only the first local Macro Pulse post.

## Per-post sharing — 2026-09-20

Each native Tech Leaders post now has an independent sharing flow:

- Every public post card exposes a `分享 ↗` action.
- The share sheet uses neutral product wording: `打开单帖`, `复制帖子链接`, and `生成分享卡片`.
- No channel-specific label such as “朋友圈” appears in the product UI.
- Shared links use the dynamic `/share/tech-leaders/<handle>/<post_id>` preview route, which emits server-side Open Graph metadata before redirecting human visitors to the standalone Ooglex post page.
- The social-card title is the original public post text (English remains English); it no longer uses the generic `科技领袖实时动态流 · Ooglex` page title. Pure reposts use the reposted source text.
- Recipients still land on `/apps/tech-leaders/post/?handle=<handle>&id=<post_id>`, so they see only the selected post rather than the full leader timeline.
- `/v1/tech-leaders/post` resolves a single post from the Ooglex free-feed cache first, then refreshes public sources when necessary. It never calls `api.x.com`.
- The share-card generator creates a 1080×1350 PNG client-side. The main feed attempts to include the first available media preview; the single-post page supports opening the share page, link copy, and share-card generation.
- Browser-native sharing is retained for generated share-card images. Available destination apps are controlled by the device/browser, not by Ooglex.
- The former `分享原文` text-only Web Share action was removed from both the main feed and standalone post page on 2026-09-20.
- `复制帖子链接` remains a separate action for users who explicitly want a clickable URL, while `生成分享卡片` remains the visual-image route.
- `微信分享` copies the dynamic single-post preview URL, tries to open WeChat from an external browser, and guides the user to open that link inside WeChat and use the top-right menu for further sharing. The product does not label this button as “朋友圈”.
- The dynamic `/share/tech-leaders/<handle>/<post_id>` route now stays open as the actual share page instead of immediately redirecting. When opened inside WeChat, it displays an in-page prompt for the top-right menu while preserving server-rendered Open Graph metadata whose title is the original post text.

