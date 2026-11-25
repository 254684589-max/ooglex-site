# Nasdaq-100 CDS V4 — valuation qualification (2026-11-25)

## Official method and sources
- https://cdsmodel.com/ — source availability, standard upfront/spread conversion.
- https://www.cdsmodel.com/cds-disclaimer.html — licensing terms and explicit assent form. Official source was not installed or copied; no assent submitted.
- https://cdsmodel.com/fee-computations.html — standard North American corporate coupons 100/500 bps and senior recovery assumption 40%; T-1 locked risk-free levels, constant hazard fitting; contract group matters.
- https://www.cdsmodel.com/rfr-test-grids.html — independent official RFR test grids, including USD holiday-calendar cases.
- https://www.sec.gov/rules-regulations/staff-guidance/trading-markets-frequently-asked-questions/frequently-asked-questions-regulation-sbsr — fixed rate and other payment fields (including upfront) needed to compute conventional spread.
- https://www.sec.gov/files/dmdr_technical_specification_20250313.pdf — daily report price-format reference (not proof of price semantics for a given record).

## Implemented
scripts/cds-research-converter-v4.js: independent idealized 5-year research calculation, flat nonnegative discount rate, constant hazard, 20 equal quarterly periods, immediate default settlement and premium accrual within period. Signed clean upfront fraction is positive when the protection buyer pays. The model solves upfront = protection PV - fixed coupon * risky annuity by bounded bisection, then computes the model-implied spread. Only explicit synthetic research inputs are accepted; no market quotes, real calendars, full date handling, settlement lag or curve bootstrap. No external library or official model is represented as installed or certified.

Validation: 11 executable test groups passed in the JS runtime with a minimal assert adapter, including 48 roundtrip combinations, analytical checks, sign, monotonicity and rejection tests. The initial negative-discount-rate cases revealed a nonmonotonic bracket; the supported domain was narrowed to nonnegative flat rates and negative inputs are rejected. Native Node and official grids have not been run. Local command: node tests/test-cds-research-converter-v4.js.

## Production admission
Require source-use rights, exact legal reference entity, verified product and contract type, actual notional (not a capped substitute), signed clean upfront or enough fee/accrual data to derive it, documented units, trade/value/settlement/step-in/maturity dates, coupon schedule and conventions, verified locked USD RFR curve, recovery and official model version. Explicitly distinguish conventional spread computed from actual trades from a dealer mid or closing market quote. Validate against official reference grids before publication. Tradeweb and DTCC raw downloads failed DNS resolution in the current execution environment. No additional real trade observations, reference entity mappings or official spreads are admitted. Preserve previous data publication lock. No paid subscriptions.
