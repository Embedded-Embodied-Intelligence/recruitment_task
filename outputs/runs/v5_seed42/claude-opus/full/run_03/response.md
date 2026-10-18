All ten answers come from Python run on the three files, after cleaning the data. The analysis script is in `/tmp/edabench_claude_lf2q_a96/an/`.

**Data quality issues I found and corrected**
- **Duplicates:** 60 rows were exact duplicates. Batch numbers repeat across lines because each line's MES terminal assigns its own, so a batch is identified by line plus `batch_id`.
- **Dates:** L1 writes dates as MM/DD/YYYY, L4 as DD/MM/YYYY, and L2/L3 as ISO dates.
- **Text fields:** `shift` and `supplier_code` were written inconsistently (case and stray spaces).
- **Mold temperature:**
  - L3 records it in °F.
  - A value of 0.0 means no reading.
  - L1's new sensor, fitted on 2025-04-14, reads about 8 °C too high. Both the comparison with the other lines and the defect model point to an offset of about 8.
- **Humidity:** values of −1 and blanks are invalid. L2's sensor was also stuck at 50.2 from 2025-03-03 to 2025-04-13.
- **Inspection change:** from 2025-07-21, L3's QC inspection time dropped from about 22 to about 13 minutes, and its recorded defect rate halved. That is a change in how defects are counted, not in production.
- **Maintenance log:** L4 has no cleanings logged from 2025-02-01 to 2025-04-11, yet its defect rates in that window look like normal, regularly cleaned operation. The log is probably missing entries, so I left that window out when estimating the cleaning effect.

**Justifications**
- **A1:** After removing the 60 exact duplicate rows, 3,000 distinct line + `batch_id` combinations remain.
- **A2:** 55 readings are blank, 171 are −1, and 123 are L2's stuck 50.2 value, giving 349.
- **A3:** 94,671 defective units out of 1,720,295 produced gives 0.0550.
- **A4:** I converted L3 from °F to °C, dropped the 0.0 readings and subtracted 8 °C from L1 readings after 2025-04-14; the median is 211.5 °C. Without the L1 correction it would be 212.8 °C.
- **B1:** In a defect-rate model controlling for line, supplier, cleaning and the issues above, mold temperature (up), humidity (U-shaped, different for each resin), cycle time (down) and night shift (up) all matter strongly. Machine age, ambient temperature and operator add nothing once line and the corrected mold temperature are included (operator: p≈0.02 over 20 operators, with effects within each line about the size of the noise).
- **B2:** `rework_cost_eur` is about €4 per defective unit (correlation 0.95 with defects), and `qc_inspection_min` grows with the defects found, so both are determined by the outcome.
- **B3:** L2's unexplained defect level jumps by about 0.65 on the log-odds scale and stays there; a change-point search puts the start at 2025-06-16. L3's drop is the inspection change described above, not a change in what it produces.
- **C1:** With every batch on one supplier at its grade's standard cycle time (30 s for Alpha and Beta, 36 s for Gamma), the expected defect rates are Gamma 0.0529, Beta 0.0566 and Alpha 0.0666. Beta only looks bad in the raw data because it runs mostly on L4, the worst line.
- **C2:** For Alpha (not pre-dried) the expected defect rate is lowest at about 30% hall humidity; spline and quadratic fits both put the minimum between 29.5% and 30.5%.
- **C3:** Each extra day since the last cleaning adds about 0.020 to the log-odds of a defect. Capping the days since cleaning by cleaning every 14 days gives about 0.0518, against 0.0550 recorded.

**Judgement calls that affect the numbers**
- **C3 and the L4 log gap:** I assumed L4 really was cleaned during its unlogged window, so extra cleanings change nothing there. If those batches are treated as uncleaned, the C3 answer drops to 0.0512.
- **Operator:** the p≈0.02 result is weak, so I left `operator_id` out of B1. Someone could reasonably argue for including it.

**What this means for management**
- Cleaning molds every 14 days would cut defects by about 6% (0.0550 to 0.0518).
- Running Alpha resin at about 30% humidity minimises its defects.
- L2's jump from 2025-06-16 needs investigating on the shop floor.
- The L1 temperature sensor needs recalibrating.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 349,
  "A3_overall_defect_rate": 0.0550,
  "A4_median_mold_temp_c": 211.5,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
