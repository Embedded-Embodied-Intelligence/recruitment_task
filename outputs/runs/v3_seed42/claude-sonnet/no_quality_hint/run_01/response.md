**Justifications**

- **A1.** 3,060 rows contain 60 exact duplicate rows, which leaves 3,000 unique `batch_id`s.
- **A2.** After de-duplication, 56 batches have a blank humidity and 171 have the sentinel value −1. That gives 226 batches with no valid reading.
- **A3.** Total defective units divided by total units over the 3,000 unique batches is 0.05978.
- **A4.** L3 reports mold temperature in °F (about 411), so I converted it to °C. I dropped the 49 zero readings as invalid. I also subtracted 8 °C from L1 from 2025-04-14, the date of the sensor replacement. The 2025-09-22 calibration note says the sensor reads 8 °C high, and L1's median jumped by about 8 °C in mid-April. The median over the 2,951 valid readings is 210.9 °C.
- **B1.** I fitted a binomial model (quasi-likelihood for overdispersion) with line fixed effects. Mold temperature, humidity (U-shaped), cycle time, ambient temperature and shift were all significant (|t| ≈ 8–26).
  - Operators are nested within lines, and within a line their effects are about 0.2 percentage points or less. Machine age is essentially a line attribute (L4 is about 16 years old, the others about 5) and is not significant within lines (t ≈ −1.6).
  - I therefore excluded both. The model also found days since cleaning to be significant, but it is not on the B1 candidate list.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are consequences of the defects (correlation with the rate 0.46 and 0.62). They must not be used as predictors.
- **B3.** L2 shows an abrupt upward shift of about +0.66 in log-odds that the process variables don't explain. The best changepoint is 2025-06-16. 2025-06-15 fits almost as well (log-likelihood difference ≈ 2), so the exact date is slightly uncertain.
- **C1.** I set the supplier to each option for every batch in the fitted model, including the humidity interaction. The predicted overall rates are Beta 0.0537, Gamma 0.0619 and Alpha 0.0625, so Beta is lowest.
- **C2.** Alpha's humidity effect is quadratic. The predicted defect rate bottoms out at about 29.8 % humidity, within the observed range of 12.1–72.3 %.
- **C3.** Days since cleaning raises the log-odds of a defect by 0.0202 per day, and the effect is linear with no kink at 14 days. I reset each batch's days-since-cleaning to its value mod 14 and shifted each batch's log-odds accordingly. The expected overall rate falls from 0.0598 to 0.0560.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.0597752,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "ambient_temp_c", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
