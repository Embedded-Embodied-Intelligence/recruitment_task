I cleaned the data before computing anything. I removed 60 exact duplicate rows and standardised the inconsistent `shift` and `supplier_code` spellings. I treated `humidity_pct = -1` and `mold_temp = 0` as missing. Line L3 logs mold temperature in °F, so I converted it to °C. On L1, the sensor fitted on 2025-04-14 reads 8 °C too high (per the 2025-09-22 calibration check), so I subtracted 8 °C from that date on. I then fitted an overdispersed binomial model of defects on the process variables, line, shift, supplier×humidity and days since the last mold cleaning (taken from the maintenance log).

**A1.** There are 3,060 rows but 60 are exact duplicates, which leaves 3,000 unique `batch_id`s.

**A2.** 56 batches have no humidity value and 170 more carry the placeholder −1, so 226 in total.

**A3.** Total defective units divided by total units produced over the 3,000 unique batches is 0.05978.

**A4.** After the °F conversion and the L1 −8 °C correction (the model fits best with exactly that offset), the median over 2,951 valid readings is 210.9 °C.

**B1.** With everything else held fixed, mold temperature, humidity (U-shaped for Alpha, falling for the pre-dried resins), cycle time and shift (night is worse) have clear effects. Ambient temperature only acts through mold temperature: its effect disappears once the L2 shift is modelled (p = 0.86). Within a line, operator (p = 0.84) and machine age (p = 0.11) have no effect.

**B2.** `qc_inspection_min` and `rework_cost_eur` are set by the number of defective units (rework cost is about €4.2 per defective unit), so they must not be used as predictors.

**B3.** From 2025-06-16, L2 runs about 0.65 higher on the log-odds scale than the model predicts (roughly double the defects), and it stays there to the end of September. That date gives the best model fit (2025-06-15 fits almost as well) and nothing in the measured variables explains the jump.

**C1.** Alpha looks best in the raw numbers only because Beta goes mostly to the old, high-defect line L4. If Beta had supplied all the resin, the expected rate would be about 0.053, against about 0.062 for Alpha or Gamma.

**C2.** For Alpha resin, which is not pre-dried, the defect rate is U-shaped in humidity. The lowest point is around 29–30% (29.8% with a quadratic fit, 29.2–29.4% with higher-order fits), and rates rise steeply above 50%.

**C3.** Each extra day since the last cleaning adds about 0.02 to the log-odds of a defect, roughly linearly. Cleaning whenever 14 days had passed would have changed 507 batches and lowered the expected overall rate from 0.0598 to about 0.0560 (0.0560–0.0597 depending on model form).

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
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
