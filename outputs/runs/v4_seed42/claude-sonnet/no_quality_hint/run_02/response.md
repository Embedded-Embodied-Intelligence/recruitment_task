**Justifications**

- **A1:** The file has 3,060 rows. 60 are exact duplicates by `batch_id`, which leaves 3,000 unique batches.
- **A2:** Humidity is NaN in 55 unique batches and holds the sentinel −1.0 in 171 more, so 226 batches have no valid reading.
- **A3:** Total defective units divided by total units produced over the 3,000 unique batches is 0.055032.
- **A4:** Line L3 logs mold temperature in °F, which I converted to °C. Line L1 reads about 7.7 °C too high after the 2025-04-14 sensor replacement, which I subtracted. Zeros are invalid and were dropped. The median of the 2,951 valid readings is 211.6 °C. I didn't confirm the sensor offset against an independent measurement.
- **B1:** I fitted a binomial model (quasi-likelihood standard errors) with line effects and the pre-processing above. Mold temperature (+0.029 log-odds per °C), humidity, cycle time (the deviation from the grade's recipe cycle time) and shift (night worse) are significant. Ambient temperature (F≈0.01) and machine age (p≈0.15) are not, once mold temperature and line are controlled. Operators are nested within lines, and their within-line differences are small; the joint test is borderline (F=1.75, 20 df) and I treated it as no effect.
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count (rework cost R² of 0.90 against defective units), so they must not be used as predictors.
- **B3:** Line L2 steps up by about +0.66 log-odds from 2025-06-16, with a scan best-fit date of exactly that day. It is independent of the process variables and persists to the end of the data. Line L3 drops from 2025-07-21, but its QC minutes fall and rework cost per defective doubles from 4.2 to 9.7 at the same date. That looks like an inspection change, not a real change in defect share, so I excluded it. The L1 shift on 2025-04-14 is a sensor artifact.
- **C1:** I set each supplier's recipe cycle time and kept all other conditions as observed. The model-predicted overall rates are Gamma 0.0473, Beta 0.0510 and Alpha 0.0595, so Gamma is lowest.
- **C2:** For Alpha batches the humidity effect is a quadratic. The minimum is at about 29.7%, which is inside the observed range of 12–72%. A binned check agrees.
- **C3:** Defect odds rise by about 2% per day since the last cleaning. Resetting days-since-cleaning at 14 gives about 0.0518, down from 0.0550.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.0550,
  "A4_median_mold_temp_c": 211.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
