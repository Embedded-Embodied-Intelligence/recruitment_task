**A1.** The file has 3,060 rows but 3,000 unique `batch_id`s, because 60 rows are exact duplicates.

**A2.** After dropping duplicates, 226 batches have humidity that is NaN or the sentinel −1.

**A3.** Total defective units divided by total units over the 3,000 unique batches is 0.05978.

**A4.** Line L3 logs mold temperature in °F (median about 412), so I converted it to °C. Line L1's sensor was replaced on 2025-04-14 and reads 8 °C too high (per the 2025-09-22 calibration check), so I subtracted 8 °C from L1 readings from that date. I treated 0.0 as a missing reading. The median over valid readings is 210.9 °C.

**B1.** I fitted a binomial GLM with line, supplier, and a step for the L2 shift (see B3). Mold temperature, humidity, cycle time, and shift all have clear effects. Humidity also interacts with supplier.
- Ambient temperature is not significant once mold temperature and days since cleaning are in the model (p≈0.36).
- Machine age is not significant once line is in the model (p≈0.14); age mostly separates L4 from the other lines.
- Operator is nested within line and only borderline significant (p≈0.03), so I excluded it.

**B2.** `qc_inspection_min` and `rework_cost_eur` are recorded after the parts are inspected and scale with the number of defects, so they must not be used as predictors.

**B3.** Line L2 shows an unexplained step up of about +0.65 on the log-odds scale. The best-fitting start is 2025-06-15; the fit is nearly as good for 06-16, so the exact day is uncertain. No other line shows a comparable shift.

**C1.** I set every batch to each supplier in turn and predicted the overall rate, with humidity interacting with supplier. The rates are Beta 0.0539, Gamma 0.0620, and Alpha 0.0625, so Beta is lowest.

**C2.** For Alpha batches, with all else held at observed values, the predicted defect rate is lowest at about 29.5% humidity. It rises on both sides of that point.

**C3.** I computed days since last cleaning from the maintenance log and reset it with `days_since % 14`, which affects 507 batches. Scaling each batch's defects by the model's predicted rate ratio gives an expected overall rate of 0.0559.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05978,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.5,
  "C3_rate_with_regular_cleaning": 0.0559
}
```
