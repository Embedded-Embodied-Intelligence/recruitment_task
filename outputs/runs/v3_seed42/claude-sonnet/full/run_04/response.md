**Justifications**

- **A1.** 3,060 rows hold 3,000 unique `batch_id`s, because 60 rows are exact duplicates. I removed those before every later step.
- **A2.** 171 batches have the sentinel value -1 and 55 have a blank humidity, so 226 batches have no valid reading.
- **A3.** Total defective units divided by total units over the 3,000 unique batches gives 0.059775.
- **A4.** Line L3 logs mold temperature in °F (about 400–450), so I converted it to °C. L1's sensor was replaced on 2025-04-14, and the 2025-09-22 calibration note says it reads 8 °C above the reference thermometer. A jump of about 8 °C in L1's weekly median from mid-April matches this, so I subtracted 8 °C from L1 readings from 2025-04-14. I dropped the 0 readings (49 batches) as invalid. The median is 210.9 °C.
- **B1.** I fitted a binomial GLM and ran F-tests that correct for overdispersion. Humidity, mold temperature, cycle time and shift are strong effects (F ≈ 200–900 for the last three). Ambient temperature, machine age and operator are not significant (F ≈ 0.02, 2.7 and 1.8).
- **B2.** `qc_inspection_min` and `rework_cost_eur` scale with the number of defects found, so they are consequences of the outcome. Neither can be used as a predictor.
- **B3.** After adjusting for the process variables and for mold cleaning, L2 shows a persistent step up. A changepoint scan puts the best likelihood at 2025-06-16, with a log-odds jump of about 0.66.
- **C1.** I predicted the whole period with each supplier swapped in. Beta (SP-02) gives about 0.0530, against 0.0614 for Alpha and 0.0612 for Gamma, so Beta is lowest.
- **C2.** In the Alpha-only fit, the defect rate is lowest at about 29.6% humidity. Quadratic, cubic and spline fits all land at 29.4–29.7%, inside the observed range of 12.1–72.3%.
- **C3.** Days since last cleaning has a roughly linear effect of about +2% in odds per day. I reset it to days mod 14 for every batch and rescaled each batch's actual rate by the model's predicted change. The result is about 0.0560 over all batches. The 0.0562 figure is the same calculation on complete rows only.

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
  "C2_optimal_humidity_pct": 29.6,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
