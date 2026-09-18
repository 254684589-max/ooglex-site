# Tech Leaders Free V3

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

After de-duplicating against the existing catalog and tagging existing qualifying entries, the 标普500 CEO layer currently contains 21 profiles.

Each qualifying entry can include ticker, sp500_ceo=true, index_tags, verified_personal_x=true, verified_at, and categories[].

The Free Embed path remains the default. Expanding this catalog does not itself increase X API cost.
