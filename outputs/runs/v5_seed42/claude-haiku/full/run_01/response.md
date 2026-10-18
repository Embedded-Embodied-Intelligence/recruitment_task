All answers are computed from the data. Three things needed care: the batch key, the unit and sensor corrections, and the decoy breaks in B3.

**Part A**
- **A1 (3000):** `batch_id` repeats across lines, so the batch key is `(batch_id, line)`. That removes 60 exact duplicate rows from 3060.
- **A2 (226):** 56 humidity cells are blank and 177 readings are −1 (a sentinel), so 226 of the 3000 batches have no valid humidity.
- **A3 (0.055032):** total defective units divided by total produced units over the 3000 batches.
- **A4 (213.9 °C):** L3 logs mold temperature in °F, so I converted those readings. Zero marks no reading (49 rows excluded). L1's sensor was replaced on 2025-04-14, and the earlier readings read low by about 8.4 °C, estimated from the defect model's likelihood. The mold-temperature regression gives 6.4–7.7 °C, so the answer is sensitive to this choice. Without the sensor correction the median is 212.8.

**Part B**
- **B1:** Mold temperature, humidity (strongly U-shaped), cycle time, ambient temperature and shift all have direct effects in a spline binomial model that accounts for overdispersion (p ≤ 0.016). Machine age (p = 0.79) and operator within line (p = 0.16) do not.
- **B2:** `rework_cost_eur` tracks defective units (r ≈ 0.95), and `qc_inspection_min` rises by about 0.09 min per defect. Both are recorded after inspection, so they are outcomes.
- **B3:** L2, from 2025-06-15. The shift persists at equal cleaning age, and L2's inspection time does not change. The L1 break (2025-04-12) is the sensor swap, and the L3 break (2025-07-21) coincides with a step drop of about 9 minutes in inspection time at an unchanged defect slope, so it is a recording artifact.

**Part C**
- **C1:** Gamma (SP-03). Expected defect rates with standard recipe cycle times are Gamma 4.8%, Beta 5.3%, Alpha 6.1%.
- **C2:** 27 %. Alpha's supplier-specific humidity curve bottoms out between about 25 % and 30 % across spline settings. The quadratic fits worse (deviance 7966 vs 7858), so I used the spline.
- **C3:** 0.0517. I applied a 14-day cleaning rule per line and scaled the recorded defect counts by the model's predicted change.

Assumptions: each line is treated as one mold. Ambiguous `DD/MM` vs `MM/DD` dates (337 rows) were resolved from neighbouring rows in file order. Supplier and shift codes were normalised.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 213.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "ambient_temp_c", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 27.0,
  "C3_rate_with_regular_cleaning": 0.0517
}
```
