# Nasdaq-100 CDS V2 — source audit (2026-11-25)
## Verified public evidence
- DTCC SEC dashboard: https://pddata.dtcc.com/ppd/secdashboard . Daily credit ZIP candidate: https://pddata.dtcc.com/ppd/api/report/cumulative/sec/SEC_CUMULATIVE_CREDITS_2026_11_24.zip . Direct retrieval failed in the research runtime (DNS); no raw rows or actual DTCC coverage certified. General terms https://www.dtcc.com/terms restrict redistribution and database use. Regulatory disclosure under https://www.law.cornell.edu/cfr/text/17/242.902 does not itself resolve the terms issue.
- Alternate source: https://reports.tradeweb.com/public/sbsefdownloads/ . Tradeweb confirms its SBSEF registration: https://www.tradeweb.com/our-markets/market-regulation/sef/ .
- SEC 17 CFR 242.825(c)(3): https://www.law.cornell.edu/cfr/text/17/242.825 . The specified Daily Market Data Report must be downloadable, machine-readable, free and without usage restrictions. This is a stronger basis for examining these particular reports, not a blanket DTCC permission.
- Official XML files inspected: https://reports.tradeweb.com/DownloadSbSef.adl?file=/TWSBSEF-CDS-Report_2026-11-23.xml and https://reports.tradeweb.com/DownloadSbSef.adl?file=/TWSBSEF-CDS-Report_2026-11-24.xml .
- 2026-11-23 includes candidate labels META and MSFT with UPI, P5Y, USD and spread-price formatting. Both report close matching the coupon label; neither is admitted as a par spread. Other rows show conflicts between stated tenor and name, invalid/missing prices, and alternative price notation. UPI is a product identifier, not proof of legal reference-entity identity.
## Implementation
`python3 scripts/audit_tradeweb_cds_v2.py --xml /path/to/downloaded.xml --date 2026-11-23`
Only local official XML files are accepted. The audit counts exact candidate ticker labels, rejects mismatched name/tenor/currency, missing identifiers and unusable prices, flags coupon collision and never emits par spreads. It does not assert coverage based on ticker labels, reconstruct upfront amounts, or write public market data.
`python3 -m unittest discover -s tests -p test_tradeweb_cds_v2.py`
Synthetic tests are not actual data coverage. Full-file automated execution on original bytes is pending; manual web source inspection is not an automated import.
## Next
Obtain price methodology and upfront-payment data, establish verified reference entity mapping, then measure actual eligible daily observations. Do not count trade reports as market quotes or map by stock ticker alone. No paid subscription, live data collection, or public historical quote series is activated.
