I answered all ten questions from the executed analysis. Two judgement calls are flagged below: which shifted line to report in B3, and that C2 and C3 are model estimates.

**Data cleaning applied (affects every answer)**
- Removed 60 exact duplicate rows (3,060 → 3,000 batches). No conflicting duplicate IDs.
- Dates use a different format per line: L1 is mm/dd, L4 is dd/mm, L2 and L3 are ISO. Parsing by line removes the ambiguity.
- Normalised `shift` (Day/D/DAY/day → Day, and likewise Night) and `supplier_code` (case and whitespace).
- `mold_temp`: 0.0 treated as missing (49 rows). All L3 readings are Fahrenheit (all above 300), so I converted them to °C.
- `humidity_pct`: blanks and the -1.0 sentinel treated as missing.

**Answers**

- **A1.** 3,000 unique batches after removing exact duplicates.
- **A2.** 226 unique batches have a blank or -1.0 humidity reading.
- **A3.** 94,671 defective units out of 1,720,295 produced gives 0.05503.
- **A4.** Median of 212.8 °C over 2,951 valid readings, using the converted values. This does not correct for the L1 sensor replacement, which shifted recorded mold temperature by about +14 °C on 2025-04-14.
- **B1.** Mold temperature, humidity (with a supplier-specific curve), cycle time and shift each have a strong, line-consistent effect. Machine age (p = 0.11) and ambient temperature (p = 0.80) have no direct effect once line and regime terms are included. Operator is not significant within any single line (p = 0.07–0.26).
- **B2.** `qc_inspection_min` and `rework_cost_eur` are recorded after inspection and scale with defects (rework is about €4.2 per defect).
- **B3.** L3's recorded rate fell from 0.051 to 0.035 on 2025-07-21, and inspection time dropped at the same moment. Rework cost per defect doubled, so rework implies about 2.2× as many defects as recorded. The actual rate therefore rose to about 0.077 (inferred from rework, not directly observed). No measured process variable explains the shift at matched values, and it appears at every days-since-cleaning level. L2 also rose from about 0.042 to 0.095 starting mid-June, but its onset is more gradual and I did not report it. This answer is a judgement call.
- **C1.** With cycle time set to each grade's recipe, Gamma (SP-03) gives 0.0480, against Beta 0.0518 and Alpha 0.0606.
- **C2.** The supplier-specific quadratic gives a vertex of 29.7 % humidity for Alpha, and the spline gives a minimum near 29 %.
- **C3.** Extra cleanings at 14 days drop mean days since cleaning from 8.4 to 5.7. The predicted rate falls from 0.05508 to 0.0519 under linear, binned and spline days terms.

The analysis scripts, including the cleaning module, are in `/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/`.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 212.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L3", "date": "2025-07-21"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
