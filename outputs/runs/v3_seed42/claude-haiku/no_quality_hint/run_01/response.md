## Answers

**A1 — 3000.** The file has 3,060 rows, but 60 are exact duplicates of other rows, so I dropped them.

**A2 — 226.** 55 humidity values are blank and 171 are the sentinel `-1.00`, which is not a valid reading.

**A3 — 0.059775.** Total defective units divided by total produced units across the 3,000 unique batches.

**A4 — 210.9 °C.** L3 mold temperatures are logged in °F, so I converted them. Zero readings (49) are treated as missing. The L1 sensor was replaced on 2025-04-14 and the calibration check found it reads 8.0 °C high, so I subtracted 8 °C from L1 readings from that date on. The median is 210.9 whether the correction starts on 14 or 15 April.

**B1 — mold_temp, humidity_pct, cycle_time_s, shift.** I fitted a binomial model with all candidates together and tested each with a dispersion-adjusted F-test; these four have p < 1e-40. Ambient temperature drops out once the L2 step is in the model (p = 0.86); its earlier apparent effect was the summer step leaking into a seasonal variable. Machine age (p = 0.11) and operator (p ≈ 0.11 across operators within line) show no direct effect.

**B2 — rework_cost_eur, qc_inspection_min.** Rework cost is about 4.21 × `defective_units` (R² = 0.98), so it is set by the outcome. QC inspection time tracks the defect count (r = 0.75) and does not vary with process settings, so it is downstream of the outcome too.

**B3 — L2 from 2025-06-15.** Adding a step on L2 to the model cuts deviance by about 2,500, against at most ~170 for any other line or date, and a step fits better than a ramp. The break falls on a mold-cleaning day for L2; the log does not explain the cause.

**C1 — Beta.** With all resin from one supplier, the plant defect rate would be 0.0537 for Beta, versus 0.0620 for Gamma and 0.0623 for Alpha. The model reproduces the actual plant rate (0.05976 vs 0.05978).

**C2 — about 26 %.** The Alpha curve is flat near its minimum, and spline fits with 8–20 terms put the optimum between 24.8 and 27.5. A quadratic gives 29.8 but fits clearly worse, so I report 26 with a plausible range of 25–28.

**C3 — 0.05592.** Forced cleaning every 14 days lowers mean days since cleaning from 8.4 to 5.7 (maximum 13), and the expected plant rate falls from 0.0598 to 0.0559. A 12-term spline gives 0.05594.

**Choices and caveats:**
- The fitted model is overdispersed (dispersion ≈ 2.8), so I scaled the standard errors and used dispersion-adjusted tests.
- The 226 missing-humidity batches and 49 missing-mold-temperature batches were handled by averaging predictions over the observed distribution (humidity) and by using the line median (mold temperature). Humidity is independent of the other inputs, so averaging is a sound approach.
- Spline flexibility was chosen by AIC (8 terms). C1 and C3 are stable across 8–12 terms.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["rework_cost_eur", "qc_inspection_min"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 26.0,
  "C3_rate_with_regular_cleaning": 0.05592
}
```
