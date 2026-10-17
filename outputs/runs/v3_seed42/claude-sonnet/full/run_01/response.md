**Justifications**

- **A1.** The file has 3,060 rows but 3,000 unique `batch_id`s. The other 60 rows are exact duplicate exports, which I dropped.
- **A2.** 226 unique batches have no usable humidity: 55 are blank and 171 hold the sentinel value -1.
- **A3.** The rate is 0.059775: total defective units divided by total units over the 3,000 unique batches.
- **A4.** Line L3 logs mold temperature in °F (about 412), so I converted it to °C. Zero readings are invalid and were dropped. After the L1 sensor was replaced on 2025-04-14, it read 8 °C high (confirmed by the 2025-09-22 calibration check), so I subtracted 8 from L1 readings from 2025-04-14 on. The median is 210.9 °C.
- **B1.** In a binomial GLM that controls for line, supplier and cleaning age, mold temperature, humidity, cycle time and shift are all highly significant. Machine age (p≈0.10) and ambient temperature (p≈0.73) are not. Operators are nested within lines, and their effect is weak and inconsistent (p≈0.02), so I treated it as noise.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count (correlations of 0.46 and 0.62 with the rate). They are not available before the outcome is known.
- **B3.** After controlling for the process variables, L2 shows a persistent jump of about +93% in the odds-scale term (coefficient 0.656) starting at 2025-06-16. This was the best-fitting change date, and the other lines show no such break.
- **C1.** I predicted every batch under each supplier using the model with supplier-by-humidity interactions. Beta gives 0.0537, against 0.0625 for Alpha and 0.0619 for Gamma.
- **C2.** For Alpha, the fitted quadratic in humidity bottoms out at about 29.8%. A cubic fit gives about 29%, so the optimum is near 29–30%.
- **C3.** Defect odds rise by about 2% per day since the last cleaning, so I reset days-since-cleaning modulo 14 and re-predicted. That cuts the model-predicted defects by 6.2%, which takes 0.05977 to about 0.0560. The change is computed on the 2,774 batches with complete humidity and mold temperature, then applied to the full-plant rate.

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
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
