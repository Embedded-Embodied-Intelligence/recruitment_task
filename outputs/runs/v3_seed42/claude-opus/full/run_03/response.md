I cleaned the three files, then fitted a Poisson model of defective units per unit produced. It uses mold temperature, supplier × humidity, cycle time, days since the last mold cleaning, shift, line, and a term for the line L2 regime change.

**Data quality issues I fixed first:**
- 60 rows were exact duplicates.
- Shift labels and supplier codes were written inconsistently (e.g. "D", "day", " Sp-01").
- 177 humidity readings were the placeholder −1, and 56 were empty.
- 49 mold temperatures were 0.
- Line L3 logs mold temperature in °F.
- Line L1's replacement sensor, fitted on 2025-04-14, reads 8.0 °C too high (confirmed by the 2025-09-22 calibration check and by comparing L1 with the other lines).

**Justifications**
- **A1:** There are 3,060 rows but only 3,000 distinct `batch_id`s; the 60 extra rows are exact copies.
- **A2:** 56 batches have an empty humidity value and 177 have −1, which is 233 in total.
- **A3:** After removing duplicates, 102,595 defective units over 1,716,317 produced gives 0.0598.
- **A4:** I dropped the 0 readings, converted L3 from °F and subtracted 8 °C from L1 readings from 2025-04-14 on; the median of the 2,951 valid batches is 210.9 °C.
- **B1:** Mold temperature, humidity, cycle time and shift stay strong when everything else is held fixed. Ambient temperature has no effect once mold temperature is in the model. Machine age and operator only appear to matter because each is tied to one line: L4 has the old machines and operators 19–24. Within a line, neither has any effect (age p = 0.91; all operators together p = 0.68).
- **B2:** `qc_inspection_min` and `rework_cost_eur` are recorded after the defects are found; rework cost is about €4.2 per defective unit.
- **B3:** From 2025-06-16, L2's defect level jumps by about 0.6 on the log scale (roughly 80% more defects) and stays there; no process variable explains it. That start date fits the data best.
- **C1:** Beta looks worst in the raw numbers only because most Beta resin went to the high-defect line L4. If every batch had used one supplier, Beta gives about 0.054, against 0.062 for both Alpha and Gamma.
- **C2:** Alpha, the only resin that is not pre-dried, has a U-shaped response to humidity with its lowest point at about 30%. The quadratic and the spline versions of the model agree on this.
- **C3:** Each extra day since cleaning adds about 1.8% more defects. Adding a cleaning every 14 days (so days since cleaning becomes that number modulo 14) and keeping each batch's own unexplained variation gives about 0.0560.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 233,
  "A3_overall_defect_rate": 0.0598,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 30.0,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
