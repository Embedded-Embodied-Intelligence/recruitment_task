Here are the results. I executed every step in Python, and the numbers below come from those runs.

**Data cleaning (applied before all answers)**
- 60 rows were exact duplicates, which left 3,000 unique batches.
- Shift labels were normalised (`D`/`day`/` Day` → Day, `N`/`night` → Night), and supplier codes were stripped and upper-cased (`sp-01`, ` Sp-02` → `SP-xx`).
- Humidity `-1` is a sentinel and was treated as invalid, along with blank entries.
- Mold temperature `0` was treated as missing.
- Line L3 is logged in Fahrenheit, so I converted it to °C.
- L1 reads about +8 °C high from the 2025-04-14 sensor replacement onward (weekly comparison against the other lines), so I corrected those readings by −8 °C.

**Part A**
- **A1:** 3,000 unique batches remain after removing the exact duplicates.
- **A2:** 226 batches have missing or invalid humidity (55 blank, 171 at −1).
- **A3:** Total defects divided by total units over all 3,000 batches is 0.05978.
- **A4:** The median corrected mold temperature over the 2,951 valid readings is 210.9 °C. This depends on the L3 and L1 corrections above.

**Part B**
- **B1:** A binomial GLM with supplier-specific humidity curves and an L2 step term gives significant direct effects for mold temperature, humidity (U-shaped), cycle time and shift. Machine age (LR p ≈ 0.10) and ambient temperature (p ≈ 0.7) are not significant once the L2 shift is modelled. Operator is borderline: within-line differences give p ≈ 0.02 uncorrected and ≈ 0.06 with line-day clustered errors, and no single operator stands out, so I did not count it as direct.
- **B2:** `rework_cost_eur` is almost exactly 4.2 × defective units (R² 0.98). `qc_inspection_min` is also driven by defect count (R² rises from 0.13 to 0.56 when it is added), so both are outcome-determined.
- **B3:** L2 has a sharp residual step after controlling for the process variables. The best-fitting step date is 2025-06-16 (deviance 11,846, against 11,949 for 06-15).

**Part C**
- **C1:** Counterfactual single-supplier model: Beta gives the lowest overall rate (0.0537), against 0.0624 for Alpha and 0.0619 for Gamma.
- **C2:** Alpha's humidity curve has its minimum at 29.8%. Cubic and quartic terms add nothing (p = 0.51 and 0.77), so the quadratic is adequate.
- **C3:** Forcing a cleaning whenever 14 days have passed lowers the model-based overall rate from 0.0598 (model with actual cleanings, matching the observed 0.0598) to 0.0560. I simulated the forced cleanings per line from the maintenance log.

Assumptions: missing humidity and mold temperature were imputed for the counterfactuals (averaged over the observed humidity distribution, and line median for mold temperature). The final model was a quasi-binomial fit with Pearson dispersion of 2.87, and the operator result is the least certain part of B1.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05978,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.05603
}
```
