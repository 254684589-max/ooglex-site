# Nasdaq-100 CDS V5 — incremental regulatory-report audit
## Scope
SEC 17 CFR 242.825(c)(3) requires the designated daily report to be machine-readable, free and without usage restrictions. https://www.law.cornell.edu/cfr/text/17/242.825
Tradeweb's regulatory reporting link: https://www.tradeweb.com/our-markets/market-regulation/sef/
Only the previously identified Tradeweb SBSEF DMDR XML path is attempted. DTCC, ICE and DSB are not scraped or archived. HTTP redirects are rejected, retrieval bounded to 8 MiB, a 20-second socket timeout, recent past dates and a maximum 31-day batch. No raw report, trade price or notional is stored or printed. XML is validated with V2 parser; date, size, encoding, classification counts and report identity checked.
## Storage
macro/nasdaq100-cds-audit.json is a public append-only-by-version audit history (not a private market-price database). Each report date contains unique SHA-256 versions, first retrieval and report generation times, row classification totals and provisional exact label candidate identifiers. Reports with the same hash are not duplicated; revisions retain prior versions. Failures leave prior successful reports intact. A missing report is not zero trading. Weekend skips are calendar heuristics, not official holiday calendars.
## Automation
.github/workflows/cds-regulatory-audit.yml runs tests on pull requests, and test-gated collection on main relevant pushes, manual dispatch, and 14:15 UTC Mon–Sat (22:15 Asia/Taipei). Default looks back seven calendar days excluding weekends, including previous trading-day candidates. Collector uses read-only HTTP, GitHub token limited to repository contents write for the collector job. Only the audit JSON is committed, no credentials or raw data. The workflow never enables quote publication. No force push. Actual Actions execution, branch protection, download success and live-site deployment require verification. Bot commits may not trigger GitHub Pages workflows; deployment must be tested separately.
## Local usage
python3 -m unittest discover -s tests -p 'test_tradeweb_cds_v*.py' -v
python3 scripts/collect_tradeweb_cds_v5.py --days 7
Initial ledger is empty and last_run null until an actual run. No synthetic test rows are written into it.
## Unresolved
No verified real spread, no official pricing-engine validation, no permitted private raw history infrastructure, no DTCC reuse permission. Full price history, rankings and alerts remain blocked. Direct raw.githubusercontent.com lookup from this runtime failed DNS resolution; native test execution must be established via Actions or local checkout.
