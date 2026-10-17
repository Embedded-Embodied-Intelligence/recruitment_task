I'll start by loading the data and checking its quality.
Found several issues already: duplicate batch IDs, messy shift and supplier labels, a -1.0 humidity sentinel, and mold_temp that looks like mixed units on L3. I'll dig into each.
`b.shift` collides with the DataFrame method; I'll use bracket access.
Part A is settled on cleaned data: 3,000 unique batches, 200 invalid humidity, rate 0.04762, median mold temp 211.0 °C. Now the modeling for Parts B and C.
statsmodels isn't installable here, so I'll check what is available and fit a binomial GLM myself if needed.
scipy and numpy are available, so I'll write a small binomial IRLS GLM with standard errors.
L2 shows a clear step between May and June. I'll locate the exact date with a likelihood scan over candidate change points, controlling for the process variables.
Data quality issues I fixed before using any number: 60 exact duplicate rows were dropped; `shift` and `supplier_code` had inconsistent case, whitespace and abbreviations; `humidity_pct` used -1 as a missing-value sentinel; `mold_temp` used 0 as a sentinel; and line L3 reports `mold_temp` in °F (about 410 vs 210), which I converted to °C.
A1. 3,060 rows contain 60 exact duplicates, which leaves 3,000 unique `batch_id`s.
A2. After deduplication, 43 batches have a blank humidity and 157 have the -1 sentinel (161 in the raw rows, including duplicates), 200 in total.
A3. Total defective units divided by total produced units over the 3,000 unique batches is 0.047621.
A4. After converting L3 from °F to °C and excluding the 0 sentinels (54 batches), the median mold temperature is 211.0 °C.
B1. I fitted a binomial GLM with line, supplier, a line-L2 step and the candidate variables, and tested each by likelihood ratio. Mold temperature, humidity (U-shaped), cycle time and shift are strongly significant (p < 1e-40). Machine age (p = 0.44) and ambient temperature (p = 0.25) add nothing: age is just the L4 line effect, and ambient's apparent effect came from seasonality coinciding with the L2 shift. Operators within a line are jointly not significant (p = 0.12); the raw operator differences come from the line differences.
B2. `rework_cost_eur` is about 4.24 € per defective unit (R² = 0.98 against `defective_units`), so it is a direct consequence of the outcome. `qc_inspection_min` rises with the defect count at constant volume (about 0.08 min per defective unit), so inspection time is driven by the defects found and not the other way around.
B3. A scan of candidate change dates on each line, controlling for process variables, finds a strong step on L2 starting 2025-06-16 (likelihood ratio about 1,300, odds up about 97%). The other lines show no comparable step (likelihood ratios 5 to 22).
C1. At equal line, shift and process conditions, Beta has the lowest defect rate (log-odds -0.27 vs Alpha, against -0.12 for Gamma). The ordering is the same on all four lines and does not depend on humidity (p ≈ 0.16). Raw rates show Gamma as best only because Beta is concentrated on the worst line, L4.
C2. The fitted quadratic puts the minimum at 36.8% humidity (SE about 0.2). Binned estimates give a flat minimum between about 35 and 45%, and a cubic term is not significant.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 200,
  "A3_overall_defect_rate": 0.047621,
  "A4_median_mold_temp_c": 211.0,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["rework_cost_eur", "qc_inspection_min"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 36.8
}
```
