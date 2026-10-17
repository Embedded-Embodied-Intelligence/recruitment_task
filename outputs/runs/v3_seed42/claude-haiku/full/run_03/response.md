I've run the full analysis and all answers are computed from the data. The answers and their justifications are below, with the data fixes first since several answers depend on them.

**Data cleaning applied before analysis:**
- 60 exact duplicate rows removed, leaving 3000 batches.
- Shift labels merged (`D`/`day`/`DAY`/` Day` → Day; `N`/`night`/`NIGHT` → Night). Supplier codes trimmed and upper-cased.
- Humidity: blanks and the `-1` sentinel treated as invalid.
- Mold temperature: L3 is logged in °F (converted to °C); 49 zero readings treated as missing; L1 corrected by −8 °C from 2025-04-14, per the sensor replacement and the 8 °C calibration offset.

**Part A**
- **A1:** 3000 unique batches after removing the 60 duplicate rows.
- **A2:** 226 batches have blank or invalid humidity (blank, or the `-1` sentinel).
- **A3:** Total defective units divided by total produced units over the 3000 batches gives 0.059775.
- **A4:** The median corrected mold temperature is 210.9 °C over the 2951 valid readings.

**Part B**
- **B1:** Mold temperature (quadratic), humidity (U-shaped, with a stronger effect for Alpha than the others), cycle time, shift (Night +0.008), and ambient temperature are direct drivers. Ambient is the weakest: its effect is small (~0.0004 per °C) but holds across every robustness check I ran. Operator is not (joint F-test p = 0.58), and neither is machine age (p = 0.59).
- **B2:** `rework_cost_eur` is almost exactly €4.2 per defective unit (r = 0.99), and `qc_inspection_min` is recorded after the inspection that counts defects. Both are outcome-determined, so they cannot be predictors.
- **B3:** L2 steps up on 2025-06-15 by about +0.037 in defect rate (t ≈ 13) after controlling for the process variables. L1 has a weaker, more gradual pattern, not a clean step.

**Part C**
- **C1:** The counterfactual plant-wide rate is lowest for Beta (0.0535), against about 0.0616 for both Alpha and Gamma. This used a supplier × humidity model, and the ranking holds with complete-case data.
- **C2:** Alpha's defect rate is U-shaped in humidity. The minimum is at 29.7 %, and a linear model and a binomial GLM agree.
- **C3:** Defect rate rises about 0.0013 per day since cleaning, and a 14-day cleaning rule lowers the average days-since from 8.4 to 5.7. That gives 0.0598 − 0.0013 × 2.8 ≈ 0.0561.

**Assumptions:** I treated cleanings as line-level, since the log has no per-mold records. I also assumed the L1 sensor offset persisted to the end of the period, because the calibration note does not say it was fixed.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "ambient_temp_c", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0561
}
```
