**A1.** 3000. I removed 60 exact duplicate rows from the 3060. Some batch_ids repeat across lines with different content, but each line's MES terminal numbers its own batches, so (line, batch_id) is unique for all 3000.

**A2.** 226. This counts 55 blank readings plus 171 placeholder `-1.0` values.

**A3.** 0.05503, which is 5,6xx defective units over all units produced across the 3000 batches.

**A4.** 213.7 °C. I treated 0.0 readings as invalid. L3 logs Fahrenheit (about 417), so I converted it with (F−32)×5/9. The L1 sensor read about 7 °C low until its replacement on 2025-04-14, so I added about 7 °C to those readings. Without that correction the median is 212.8.

**B1.** `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift`. In a quasi-binomial model with line, supplier, cleaning age and the L2 shift, these four are significant. `ambient_temp_c` (p≈0.35) and `machine_age_years` (p≈0.36) show no direct effect. Age only looks important because L4 is the old line, and ambient only acts through mold temperature. `operator_id` is nested in line and shows no effect within a line.

**B2.** `qc_inspection_min` and `rework_cost_eur`. Both are consequences of the defect count, since rework cost rises by about 4.35 € per defect.

**B3.** L2 from 2025-06-16. After that date L2's defect rate is about 2× what its process variables predict (a log-odds jump of about 0.68), and 06-16 is the best-fitting change date. L3 also drops sharply on 2025-07-21, but I ruled it out. QC minutes fall by about 9 and rework cost per recorded defect rises, so L3's defects are being under-recorded rather than actually reduced.

**C1.** Gamma. With all batches switched to a supplier, its recipe cycle time and the humidity curve fitted to that supplier, the predicted overall rates are Gamma 0.0503, Beta 0.0548 and Alpha 0.0632.

**C2.** About 30 %. The fitted Alpha curve is U-shaped and its minimum is at 30.5 % (quadratic fit); a more flexible spline puts it at 27–28 %.

**C3.** 0.0522. Defects rise by about 2 % per day since the last cleaning (log-odds slope 0.020), on L1–L3 only; L4 shows no cleaning effect. I reset days-since-cleaning modulo 14, which gives 0.0537 if capped at 14 instead.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 213.7,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0522
}
```
