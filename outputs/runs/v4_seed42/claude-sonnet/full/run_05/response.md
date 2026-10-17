**A1.** 3,000 unique batches. The file has 3,060 rows. 60 are exact duplicate rows, so I kept one row per `batch_id`.

**A2.** 226 batches have no valid humidity reading: 55 are blank and 171 hold the sentinel -1.

**A3.** The overall defect rate is 86,003 / 1,561,450… no, over all 3,000 unique batches it is 94,671 / 1,720,295 = 0.05503. Dates came in mixed ISO and MM/DD vs DD/MM formats, and shift and supplier-code labels were messy. I normalised those first.

**A4.** The median actual mold temperature is about 211.7 °C.
- Line L3 reports in °F, so I converted it.
- 49 zero readings are invalid, so I dropped them.
- After the L1 sensor replacement on 2025-04-14, readings run about 7 °C high. I corrected that offset, estimated at 6.3 to 8.3 °C depending on method, so the median is approximate: 212.8 °C without the L1 correction.

**B1.** The direct drivers are `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift`. All four stay highly significant in a binomial model that also controls for line, supplier, days since cleaning and the regime shifts. `ambient_temp_c` only drives mold temperature, and `machine_age_years` is just a proxy for line L4. Neither has an effect once the other variables are in the model. `operator_id` is nested within line, and its borderline p of 0.012 does not hold up, so I excluded it.

**B2.** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count, not inputs to it.

**B3.** Line L2 shifts abruptly upward from 2025-06-16, by about +0.66 on the log-odds scale, and stays there. Line L3's drop from 2025-07-21 is not a production change. It coincides with `qc_inspection_min` falling from about 24 to 13, which points to a change in inspection. L1 has no unexplained shift.

**C1.** Gamma is best. With every batch re-assigned to one supplier and run at that grade's recipe cycle time, predicted plant-wide rates are Gamma 0.048, Beta 0.052 and Alpha 0.061.

**C2.** Alpha batches have a U-shaped humidity response. A quadratic and a cubic fit both minimise at 29.5 %, and splines give 26 to 30 %.

**C3.** The expected rate is about 0.0519 (0.0518 to 0.0519 depending on method). Cleaning whenever 14 days have passed cuts the days-since-cleaning term, which adds about 0.02 log-odds per day. That lowers the plant-wide rate by about 5.8 %.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.7,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.5,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
