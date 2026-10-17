Everything below comes from code I ran on the three files.

**Data cleaning**
- There were 60 exact duplicate rows.
- Dates came in mixed formats: ISO, MM/DD on L1, DD/MM on L4.
- Shift and supplier codes had inconsistent spellings.
- Mold temperature on L3 was recorded in °F. Zeros were invalid readings.
- Humidity had NaN values and a −1 sentinel.
- The L1 mold sensor read about 6.4 °C too low until it was replaced on 2025-04-14. I estimated that offset from L1's mold temperature relative to the other lines at the same ambient temperature.

**Part A**
- **A1:** 3000 unique `batch_id`s remain after dropping 60 exact duplicate rows.
- **A2:** 226 batches have invalid humidity: 55 NaN and 171 with the −1 sentinel.
- **A3:** Total defective units divided by total produced units is 0.05503.
- **A4:** The median is 213.6 °C. This converts L3 from °F, drops the 49 zero readings, and adds the 6.4 °C offset to L1 readings before 2025-04-14.

**Part B**
- **B1:** Mold temperature, humidity, cycle time (relative to the grade's recipe) and shift have direct effects in a binomial model that controls for line, supplier, cleaning age and the two regime changes. Ambient temperature has no effect once mold temperature is included, since it only works through mold temperature.
- Machine age and operator have no clear direct effect. Machine age only varies widely on L4, and within L4 its slope is about zero. Operator is nested within line, and the within-line differences are small and not convincing.
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the defects. The first is about 20 + 0.083 × defective units, and rework cost is almost fully explained by units and defects (R² 0.97).
- **B3:** L2 shifts abruptly upward at 2025-06-15, and the best-fit step date is 06-15 over 06-16 by a very small margin. Its defect rate runs about 1.9 times higher afterwards (a +0.67 log step), which the process variables don't explain.
- L3 also shows a drop on 2025-07-21, but I treat it as a measurement artifact. Its QC inspection time fell from about 23 to 13 minutes on the same date, so fewer defects were being detected.

**Part C**
- **C1:** With every grade run at its recipe cycle time, the predicted overall rates are Gamma 0.0474, Beta 0.0512 and Alpha 0.0595. Gamma is lowest.
- **C2:** Alpha's humidity curve is U-shaped. A spline puts the minimum at about 26.5%, a hinge fit at 26–29%, and a quadratic fit at about 30%. I give 28%.
- **C3:** The cleaning-age effect is about 0.02 log-odds per day. Resetting days-since-cleaning every 14 days gives an expected overall rate of about 0.0518, down from 0.0550.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 213.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 28,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
