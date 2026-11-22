# Ooglex SOFR OIS historical data — redistribution clearance and reconciliation (V17)

## Source facts (checked 2026-11-23)
- CheckMySwap curve explorer: https://www.checkmyswap.com/rates
- Methodology: https://www.checkmyswap.com/methodology
- USD archive begins 2026-03-19; absent snapshot returns HTTP 404 and **does not silently substitute another date**.
- Current USD pricing points use DTCC public records, filtering rules and close-window weighted medians; `close`, `close-thin`, `derived`, and `all-day` are **not interchangeable**. Older snapshots may have used different methodologies.
- A dated stored snapshot can be overwritten by later processing. The date alone is not immutable evidence of the first-published quote.
- The site permits free viewing and JSON download, but the pages inspected do **not expressly grant Ooglex the right to systematically store and re-publish historical curve values or derived Treasury-OIS spreads**.
- U.S. Treasury official CMT: https://home.treasury.gov/policy-issues/financing-the-government/interest-rate-statistics/ . Official U.S. Treasury historical data availability does not confer rights over CheckMySwap constructed curves.

## Current production evidence
- Ooglex published SOFR historical archive contains only 2026-11-20.
- V15 10-day live sample: nine new technically valid six-tenor candidates and one `archive_conflict` on 2026-11-20. Six tenors on that date have differences in `swap` and `spreadBp`, while `treasury` and `method` remain identical.
- Original raw response hash for the 2026-11-20 published record is absent. It is therefore **not proven** whether CheckMySwap later revised its snapshot, the initial snapshot used another version, or an ingestion mistake occurred. No existing observation should be overwritten without a separately approved reconciliation record.

## What to ask the upstream provider
1. May the Ooglex public finance website store, reproduce and display historical USD SOFR OIS curve values on charts, alongside the Treasury's CMT and derivative swap spreads?
2. Does the permission cover automated retrieval, persistent archival, public display of 2Y/3Y/5Y/7Y/10Y/30Y derived swap spreads, paid products/advertising, and user-accessible historical data downloads? Are there restrictions or attribution requirements?
3. Is separate written licensing or an API commercial plan required? What rate limits and retention requirements apply? Can a third-party website display data without republishing raw curve values?
4. Can the provider document the pipeline/version lineage for the 2026-11-20 USD snapshot and whether it has been recalculated? Are historical revision timestamps or immutable files available?
5. Are historical points `close-thin` considered eligible for onward sharing as indicative measurements? Is a published range of 2026-03-19 to today permitted to be indexed or stored?

## Copy-ready permission request (English)
Subject: Permission request — historical USD SOFR OIS curves and derived spreads on Ooglex

Hello CheckMySwap team,

I operate Ooglex, a public financial research website, and am evaluating your dated USD SOFR OIS curve archive for a historical analytics page.

I would like written clarification of whether Ooglex may (1) retrieve and persist archived 2Y, 3Y, 5Y, 7Y, 10Y and 30Y par rates through your dated API; (2) display those values and daily differences against official U.S. Treasury CMT yields, including derived swap spreads and charts; and (3) offer that historical display on a public website, including potential commercial/advertising use.

Please advise on any licensing terms, attribution, API/rate limits, retention periods, and restrictions on redistributing either raw data or derived spread series. If a different API tier or written agreement is required, please share the available options. We will not bulk re-publish your history before confirming permitted use.

We also observed that a fresh API request for the dated 2026-11-20 USD curve does not match values previously stored on our side across six tenors, while the Treasury reference values and method labels are unchanged. Can you confirm whether this snapshot was recalculated, whether earlier versions are accessible, and how to audit revision timestamps or pipeline versions?

Thank you.

Ooglex financial research project

## Release decision
`docs/data-rights/sofr-historical-publication.json` remains `publicationMode: blocked` and `historicalPublicationApproved: false`. No user reply or third-party licensing response has been received in this chat; do not imply a permission request has been sent.

Approval requires review of actual rights-holder documentation plus resolution of the 2026-11-20 conflict. A passing automated registry check can only support a manual decision, not replace the legal/contractual evidence review. If written permission is denied, seek an alternative licensed source or display externally linked archive pages without silently copying their historical rates.
