**Justifications**

- **A1:** The file has 3,060 rows, and 60 of them are exact duplicate rows of another batch. Dropping them leaves 3,000 unique `batch_id`s.
- **A2:** 55 batches have an empty humidity value, and 171 have the sentinel value −1, which is not a real measurement. That makes 226 batches.
- **A3:** I divided total defective units by total units produced over the 3,000 unique batches, giving 0.055032.
- **A4:** Some `mold_temp` values are in °F (about 380–465), so I converted them, and I treated 0 as a failed reading. Line L1's sensor read about 6.4 °C too low before its replacement on 2025-04-14, so I added 6.4 to L1 readings before that date. The median actual temperature is 213.6 °C, or 212.8 °C without the L1 correction.
- **B1:** In a binomial model with line, supplier, a cleaning-age term and the regime shifts below, four variables have clear effects. They are mold temperature, humidity (U-shaped), cycle time (longer is better) and shift (night is worse). Ambient temperature (p = 0.58) and machine age (p = 0.66) have no effect once mold temperature and line are controlled. Operator is nested within line and adds nothing.
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the number of defects found, so they must not be used as predictors.
- **B3:** L2 shifted abruptly and persistently on 2025-06-15, and the process variables don't explain it. L3's drop on 2025-07-21 coincides with a step cut in QC inspection time that is independent of the defect rate. I read that as less thorough inspection rather than a real change in what L3 produces, so I did not report it.
- **C1:** I fitted a model with a separate humidity curve per supplier and set each supplier's cycle time to its recipe. The predicted overall rates are Alpha 0.0606, Beta 0.0519 and Gamma 0.0479, so Gamma is lowest. Gamma's edge comes mainly from its longer 36 s cycle.
- **C2:** For Alpha batches the humidity curve is U-shaped, and the quadratic fit has its minimum at about 29.8%. Fits over narrower humidity ranges also give about 29.7–29.9%. I rounded to 30%.
- **C3:** Defect risk rises about 2% per day since the last cleaning. I reset days-since-cleaning to its value modulo 14 and recomputed the plant rate, which comes to 0.0519, about 5.8% lower than the observed rate. The model uses the observed defect counts, so L3's undercounting after 2025-07-21 is not corrected for.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 213.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
