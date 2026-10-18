These answers come from code I ran on the data after cleaning it. The cleaning steps were:
- I removed 60 exact duplicate rows.
- L1 uses MM/DD dates, L4 uses DD/MM, and L2 and L3 use ISO dates.
- Shift and supplier labels came in mixed spellings, so I standardized them.
- I treated humidity of -1 and mold temperature of 0 as missing.
- L3 reports mold temperature in °F, so I converted it to °C.
- L1's sensor was replaced on 2025-04-14, and its readings jump by about 6.5 °C that day with no change in defect rate. I read that as a sensor offset and removed it. This offset is my estimate. With it, A4 is 211.8. Without it, A4 is 212.8.

**A1.** There are 3000 unique batches. The export held 3060 rows, and 60 were exact duplicates. Some batch IDs recur across different lines, but those are distinct batches.

**A2.** 226 unique batches have a missing or invalid humidity reading. 170 are the `-1` placeholder and 56 are blank.

**A3.** The overall defect rate is 0.055032 (total defective units over total produced units, after de-duplication).

**A4.** The median actual mold temperature is 211.8 °C, over 2951 batches with a valid reading.

**B1.** `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift` have direct effects in the binomial model, with line, supplier, days since cleaning and the regime shifts controlled.
- Machine age shows no effect within a line. Line L4 is both the oldest and the worst, so age only looks important across lines.
- Operators are nested within lines and show no effect beyond the line.
- Ambient temperature has no effect once mold temperature is controlled. It acts only through mold temperature.

**B2.** `qc_inspection_min` and `rework_cost_eur` are consequences of the defects, so they leak the outcome.

**B3.** Line L2 shifts upward from 2025-06-16. The defect odds rise by about 0.66 on the logit scale, and the deviance scan picks that date. L3 shows an apparent drop from 2025-07-21, but `qc_inspection_min` falls from about 23 to about 14 the same week. That points to a change in inspection, not in what the line produces, so I excluded it.

**C1.** Gamma gives the lowest defect rate. I used supplier-specific models for humidity, mold temperature and cycle time, and set every batch to each supplier's standard cycle time. Predicted rates were Gamma 0.0478, Beta 0.0518 and Alpha 0.0602.

**C2.** Alpha's defect rate is lowest at about 30% humidity. Alpha is not pre-dried, and its quadratic humidity fit puts the minimum at 30.4%. Adding a hinge for high humidity left it at 30.4%, but a flexible spline put it nearer 27%.

**C3.** The expected defect rate with regular cleaning is about 0.0519. I reset days since cleaning to `ds mod 14` (the days-since-cleaning count) and scaled each batch's recorded defects by the model's predicted ratio. L4 has no logged cleaning between 2025-02-01 and 2025-04-11. I took the log at face value, so that gap drives part of the effect.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
