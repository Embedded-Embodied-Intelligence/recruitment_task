Answers are below. I deduplicated, cleaned and modelled the data in Python before answering each one.

- **A1.** The file has 3,060 rows but 3,000 unique `batch_id`s. The other 60 rows are exact duplicates, which I dropped.
- **A2.** 226 batches have no valid humidity: 55 are NaN and 171 hold the sentinel value −1.
- **A3.** After deduplication, total defective units divided by total produced units is 0.059775.
- **A4.** Line L3 reports mold temperature in °F (values around 410), so I converted it. Zeros are invalid readings, so I dropped them (49 batches). The maintenance log says L1's sensor reads 8 °C too high. The L1 readings step up by about 8 °C on 2025-04-14, the sensor replacement date, so I subtracted 8 from L1 from that date on. The median over the 2,951 valid batches is 210.9 °C.
- **B1.** I fitted a binomial model (batch counts, with the overdispersion scale estimated) that corrects the data issues and adds the shift and line effects. It includes days since the last cleaning, and a term for the L2 shift found in B3. Mold temperature, humidity, cycle time and shift are significant. Machine age (p≈0.12), ambient temperature (p≈0.78) and operator (p≈0.05, no consistent pattern) are not. Machine age looks important only because L4 is old and has a high rate. Ambient temperature acts through mold temperature and cleaning interval, which are already in the model.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are recorded after inspection and scale with the defect count. That makes them outcome-determined.
- **B3.** Line L2's residual defect rate jumps by about 3.5 percentage points and stays there. A changepoint search puts the break at 2025-06-16, and no process variable explains it.
- **C1.** Forcing every batch to one supplier in the model gives Beta 0.0538, Gamma 0.0620 and Alpha 0.0625. Beta is lowest.
- **C2.** For Alpha batches, the defect rate is U-shaped in humidity. Quadratic and spline fits put the minimum at about 28–30%, so I used 29%.
- **C3.** I reset days-since-cleaning to the remainder after dividing by 14 for every batch at 14 days or more, and rescaled each batch's actual defects by the model's predicted ratio. That gives an overall rate of about 0.0560. Treating only batches over 14 days as overdue gives 0.0564.

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
  "C2_optimal_humidity_pct": 29,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
