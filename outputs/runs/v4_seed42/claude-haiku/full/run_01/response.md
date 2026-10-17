## Answers

**A1. 3000 unique batches.** The file has 3,060 rows, and 60 are exact duplicates of other rows. No `batch_id` has conflicting values.

**A2. 226 batches.** 171 have the sentinel `-1` and 55 are blank.

**A3. 0.055032.** This is 94,671 defective units over 1,720,295 produced.

**A4. 211.7 °C.** L3 reports mold temperature in Fahrenheit, so I converted it. The L1 sensor was replaced on 2025-04-14 and afterwards reads about 7 °C high, so I corrected those readings. The uncorrected median is 212.8 °C. The corrected median is 211.5–211.8 for offsets of 6–8 °C.

**B1. mold_temp, humidity_pct, cycle_time_s, shift.** Each has a large quasi-F effect (p < 1e-30) with all other measured variables held fixed. Ambient temperature (p = 0.44) and machine age (p = 0.44) have no effect. Operator has no effect beyond line (p = 0.055, borderline); operators are nested within lines, and the within-line differences are small.

**B2. qc_inspection_min, rework_cost_eur.** QC minutes are about 20 + 0.078 × defective units, and rework cost is about 4.2 € per defective unit. Both are recorded because of the defects, so they cannot be predictors.

**B3. L2, 2025-06-15.** L2's defect rate steps up from 0.041 to 0.094. The process model fitted before that date predicts 0.051, and the rework-cost evidence agrees with the recorded counts. L3 also shows a drop from 2025-07-21, but QC inspection time falls at the same point and rework cost per recorded defect doubles. That points to under-counting, and the rework-implied true rate (0.076) matches the process prediction (0.073).

**C1. Gamma.** With each supplier's batches run at its recipe cycle time (Gamma 36 s, Alpha and Beta 30 s), the expected rates are Gamma 0.0495, Beta 0.0546 and Alpha 0.0625. The humidity effect depends on supplier (p < 1e-200), so I fitted it per supplier.

**C2. 27.5 %.** Alpha's humidity effect is U-shaped, with the lowest adjusted bins at 22.5–32.5 %. Spline fits put the minimum between about 25 and 30 %, so the answer is approximate.

**C3. 0.0535.** Adding a clean whenever 14 days pass lowers the average days since cleaning from 8.4 to 5.7. This is the expected true-process rate. Carrying the recorded L3 under-counting through instead gives 0.0519.

## Caveats
- A4 and C3 depend on assumptions: the L1 offset (about 7 °C, estimated from the data) and the use of true-process rates for L3.
- The shared `/tmp/claude-0` scratch area was overwritten by another session while I worked, so I moved all analysis into my scratchpad: `/tmp/claude-0/-tmp-edabench-claude-qla960oa/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/` (`eda_prep.py`, `eda_model.py`, `eda_cf.py`).

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.7,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 27.5,
  "C3_rate_with_regular_cleaning": 0.0535
}
```
