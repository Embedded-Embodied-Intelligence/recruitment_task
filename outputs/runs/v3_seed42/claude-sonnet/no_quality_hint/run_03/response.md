Every answer below comes from code I ran on the data. Before analysing, I removed 60 duplicate rows. I standardised the `shift` and `supplier_code` labels (case and whitespace). I set humidity values of −1 to missing and mold temperatures of 0 to missing. Line L3 reports mold temperature in °F, so I converted it to °C. Line L1's sensor reads 8 °C too high from its 2025-04-14 replacement on, so I corrected for that.

**Part A**
- **A1.** There are 3000 unique `batch_id`s among 3060 rows, so 60 rows are exact duplicates.
- **A2.** 55 batches have a blank humidity and 171 have the invalid reading −1, which gives 226.
- **A3.** Total defective units divided by total produced units over the 3000 unique batches is 0.059775.
- **A4.** After the unit and sensor corrections, the median actual mold temperature is 210.9 °C (49 invalid zero readings excluded).

**Part B**
- **B1.** In a binomial model with line, supplier, days since cleaning and a step for L2's regime change, mold temperature, humidity, cycle time and shift all have clear effects. Ambient temperature, machine age and operator drop out once the model allows for overdispersion and the operator–line nesting (each operator works on one line only). Those three have no direct effect.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are recorded after the fact and scale with the number of defects, so they leak the outcome.
- **B3.** Line L2 steps up abruptly on 2025-06-16, with an odds-ratio of about 1.9. A scan over candidate dates puts the best break there, and the process variables don't account for it.
- **C1.** Beta has a worse raw rate only because it mostly ran on L4, the worst line. Switching all batches to each supplier in the adjusted model gives 0.0538 for Beta, 0.0616 for Gamma and 0.0624 for Alpha.
- **C2.** For Alpha, which is not pre-dried, the fitted humidity curve is U-shaped. Quadratic, cubic and quartic fits all put the minimum at 29.5–30 %.
- **C3.** Days since last cleaning has a clear positive effect on the defect rate. Resetting it to the remainder after dividing by 14 whenever it reaches 14 or more, and re-predicting, gives about 0.0560. This holds across linear, quadratic and binned versions of that effect.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
