**Data cleaning.** I dropped 60 exact duplicate rows and normalised the `shift` and `supplier_code` labels (case, whitespace and abbreviations). Humidity of −1 is a sentinel for a failed reading. Line L3 reports mold temperature in °F. A mold temperature of 0 is a missing reading. Line L1's sensor reads 8 °C too high from 2025-04-14, the date the sensor was replaced; the 2025-09-22 calibration note gives the 8 °C offset. Before that date L1 tracks the other lines, and afterwards it sits about 7.7 °C above them.

- **A1.** There are 3000 unique batches, after removing 60 duplicate rows.
- **A2.** 226 batches have no valid humidity: 171 are the −1 sentinel and 55 are blank.
- **A3.** The overall defect rate is 0.05978 (total defective units divided by total units over the 3000 batches).
- **A4.** The median actual mold temperature is 210.9 °C. I converted L3 from °F, removed the +8 °C offset on L1 from 2025-04-14, and excluded the zero readings.
- **B1.** The direct drivers are `mold_temp`, `humidity_pct` and `shift`. In a binomial regression these are strongly significant: the mold temperature coefficient is about 0.03 per °C, humidity has a U-shaped effect, and night shift is about 0.17 higher on the log-odds scale. Ambient temperature, cycle time and machine age are not significant once the other variables are in the model. The ambient-temperature correlation is just seasonality (it correlates 0.85 with time). Operator effects are not significant once line is controlled for, because operators OP-19 to OP-24 only work on L4.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are recorded after inspection and are driven by the number of defects, so they must not be used as predictors.
- **B3.** Line L2 shows a step of about +0.65 on the log-odds scale (roughly a doubling of the defect odds). It is persistent and unexplained by temperature, humidity, shift, supplier or cleaning age. A scan over candidate dates puts the start at 2025-06-15, but 06-12 and 06-14 are close behind. In my first scan 06-12 narrowly came out best, so the exact date is somewhat uncertain.
- **C1.** Beta would give the lowest overall defect rate, at 0.0530. Alpha would give 0.0627 and Gamma 0.0624.
- **C2.** For Alpha batches, a quadratic fit of defect rate against humidity has its minimum at about 29.7 %.
- **C3.** The expected overall rate is 0.0559. Each extra day since the last cleaning raises the defect odds by about 2.1 %, with no extra kink after 14 days. I reset the cleaning age to zero every 14 days. If the age were only capped at 14 days instead, the rate would be 0.0579.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05978,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0559
}
```
