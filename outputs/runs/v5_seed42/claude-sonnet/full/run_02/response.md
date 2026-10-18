These answers come from executing the analysis. The data needed cleaning first.

**Data cleaning**
- Dates come in three formats. L1 uses MM/DD/YYYY, L4 uses DD/MM/YYYY, and L2 and L3 use ISO.
- `shift` and `supplier_code` have inconsistent labels and case, which I normalised.
- `humidity_pct` uses -1 as a sentinel for no reading, and `mold_temp` uses 0.
- L3 reports mold temperature in °F, so I converted it to °C.
- The L1 mold-temperature sensor reads about 7 °C higher after its replacement on 2025-04-14. I corrected for that.
- 60 rows are exact duplicates. Batch IDs are reused across different lines and dates, so only full-row duplicates count as the same batch.

**Part A**
- **A1:** 3,000 unique batches. There are 3,060 rows, and the 60 exact duplicate rows were dropped.
- **A2:** 226 batches have a missing or invalid humidity, counting the -1 sentinel.
- **A3:** The overall defect rate is 0.055032, which is total defects divided by total units over the unique batches.
- **A4:** The median actual mold temperature is about 211.7 °C. That is after converting L3 from °F, dropping the 0 readings, and removing the ~7 °C post-replacement offset on L1.

**Part B**
- **B1:** In a binomial model with line, supplier, days since cleaning and a L2 regime-shift term, four variables are significant. These are mold temperature (+), humidity (U-shaped), cycle time relative to the recipe (more is better), and shift (night is worse). Ambient temperature acts through mold temperature (its coefficient is ~0 once mold temperature is corrected). Machine age is ~0 within a line, so the apparent age effect is really a line effect. Operator is not significant (F-test p=0.33).
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count, so they must not be predictors.
- **B3:** L2 shifts from 2025-06-16. Its defect rate roughly doubles from that date, and the changepoint scan peaks there. This is not explained by process variables, and cleanings stayed regular around that date. L3's recorded defects drop on 2025-07-21, but that coincides with QC inspection time falling from ~23 to ~13 minutes. It is a measurement change, not a change in what the line actually produces.
- **C1:** Gamma is lowest, with an expected plant rate of about 0.049, against about 0.053 for Beta and 0.062 for Alpha. This sets cycle time to each resin's recipe and uses a supplier-specific humidity response.
- **C2:** Alpha's expected defect rate bottoms out at about 30.5% humidity, from the quadratic fit on Alpha batches.
- **C3:** I reset days since cleaning to zero every 14 days and rescaled each batch's recorded defects by the model's predicted risk ratio. That gives about 0.0473. The estimate is 0.0480 with a linear days-since-cleaning term, and 0.0488 if the days are capped at 14 instead of reset.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.7,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30.5,
  "C3_rate_with_regular_cleaning": 0.0473
}
```
