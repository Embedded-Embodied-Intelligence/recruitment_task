## Data cleaning

- **Dates:** L2 and L3 use ISO dates. L1 uses `MM/DD/YYYY` and L4 uses `DD/MM/YYYY`, which resolves the apparent ambiguity.
- **Duplicates:** 60 exact duplicate rows were removed, leaving 3,000 batches. `batch_id` repeats across lines, so the key is (`line`, `batch_id`).
- **Codes:** `shift` (Day/D/DAY/ day…) and `supplier_code` (case and whitespace) were normalised.
- **Sentinels:** humidity `-1` and blanks are missing; mold temperature `0.0` is missing.
- **Units:** L3 mold temperature is in °F and was converted to °C.
- **Sensor:** L1 readings after the 2025-04-14 sensor replacement run about 7.7 °C high, so I corrected them.
- **Recording:** from 2025-07-21, L3's recorded defect counts are about half the true count, which I inferred from rework cost.

## Answers

**A1.** 3,000 unique batches. The 3,060 rows contain 60 exact duplicates, and `batch_id` is reused across lines, so the key is (line, batch_id).

**A2.** 226 unique batches have a blank or sentinel (`-1`) humidity reading.

**A3.** 94,671 defective units over 1,720,295 produced units gives 0.055032.

**A4.** The median corrected mold temperature is 211.6 °C over the 2,951 batches with a valid reading. Without the L1 correction it would be 212.8 °C.

**B1.** Mold temperature, humidity (nonlinear), cycle time and shift all stay significant after dispersion-scaled tests, and shift holds in every line. Machine age (p ≈ 0.19) and operator (p ≈ 0.13) drop out once line is controlled. Ambient is excluded: its residual effect is absent in L1 and L3 and only appears when lines are pooled, so it is most likely a mold-temperature artefact. This is the least certain item.

**B2.** `rework_cost_eur` is about €4.2 per recorded defective unit (R² ≈ 0.97), and `qc_inspection_min` tracks defect counts (R² ≈ 0.53). Both are recorded after the outcome.

**B3.** L2's defect rate roughly doubles from 2025-06-16 (about 4.2% to 9.4%). The shift stays after controlling for all process variables, and L2's rework cost per defect stays flat, so the counts are real. L3 also shifts (on 2025-07-21), but that is a recording change, not a production change.

**C1.** Gamma gives the lowest counterfactual rate, about 4.8%, against about 5.2% for Beta and 6.0% for Alpha. Gamma's standard recipe is 36 s, and longer cycles reduce defects. The result holds across three model specifications.

**C2.** About 28% relative humidity minimises Alpha's expected defect rate. Alpha is not pre-dried, and its humidity curve is U-shaped; the minimum falls between 26% and 31% depending on the spline or quadratic specification, so this is the least precise numeric answer.

**C3.** About 0.0520, against 0.0551 actual. I scored each batch with the model's days-since-cleaning effect under a cleaning every 14 days, applied as a ratio to the recorded defect counts. Using model predictions alone instead gives 0.0545.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 28,
  "C3_rate_with_regular_cleaning": 0.0520
}
```
