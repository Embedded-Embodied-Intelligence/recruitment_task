**Part A: data description**

- **A1:** 3,060 rows, of which 60 are exact duplicates, leaving 3,000 unique `batch_id`s.
- **A2:** 226 batches have no valid humidity: 171 carry the sentinel `-1` and 55 are blank.
- **A3:** 102,831 defective units out of 1,720,295 produced, giving 0.059775.
- **A4:** I excluded 49 zero readings as missing. Line L3 is recorded in °F throughout, so I converted it. Line L1 reads about 8 °C high after the 2025-04-14 sensor replacement, which matches the September calibration note, so I corrected it. The median over 2,951 valid readings is 210.9 °C.

**Part B: salient features**

- **B1:** I fitted a binomial GLM with overdispersion scaling, holding all other measured variables fixed. Mold temperature, humidity (its effect differs by supplier and is curved), cycle time and shift are clearly significant. Ambient temperature (p = 0.72) and machine age (p = 0.16) are not. Operator is borderline (scaled LR p = 0.03, permutation p = 0.16), so I did not count it. Ambient looked significant until the L2 shift was modelled.
- **B2:** `qc_inspection_min` tracks defect count (t ≈ 39) and barely depends on process variables. `rework_cost_eur` is about €4.2 per defective unit (R² = 0.98).
- **B3:** L2 shows a step from about −24 % to +28 % residual defect rate on 2025-06-15. The step is flat across mold-cleaning age, and no other line shows a comparable shift.

**Part C: interpretation**

- **C1:** With everything else as observed, Beta gives the lowest overall rate (0.0538), against 0.0624 for Alpha and 0.0619 for Gamma.
- **C2:** Humidity has a curved effect for all suppliers, so Alpha's defect rate is lowest at about 29.7 %. A linear term would wrongly put the minimum at the lowest observed humidity.
- **C3:** Cleaning every 14 days lowers the modelled rate from 0.0598 to about 0.0560. The modelled baseline matches the actual total to within 0.1 %.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
