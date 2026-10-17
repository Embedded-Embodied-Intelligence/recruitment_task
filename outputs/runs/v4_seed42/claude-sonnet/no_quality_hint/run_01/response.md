Answers below; everything was computed in Python on the cleaned data.

**Data cleaning**
- I dropped 60 exact duplicate rows.
- Dates came in mixed ISO, MM/DD and DD/MM formats. I resolved the ambiguous ones using the 2025-01-06 to 2025-09-30 range and neighbouring rows. A few dates may still be off.
- Shift and supplier labels were normalised.
- Humidity of −1 (or blank) is invalid.
- A mold temperature of 0 is invalid.
- Line L3 reports mold temperature in °F, so I converted it to °C.
- The L1 mold temperature readings jump by about +6.8 °C on 2025-04-14, the day the sensor was replaced. Defect rates did not move with it, so I treated that as a measurement artifact and subtracted the offset.
- The L3 jump of about +5.7 °C on 2025-05-19 is real, because defect rates followed it.

**Part A**
- **A1.** There are 3000 unique `batch_id`s.
- **A2.** 226 batches have missing humidity (56) or the invalid −1 value (170).
- **A3.** 0.05503: total defective units divided by total units over the unique batches.
- **A4.** The median actual mold temperature is 211.9 °C, after the °F conversion, removing zeros, and correcting the L1 offset. The uncorrected median is 212.8 °C.

**Part B**
- **B1.** The direct drivers are `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift`.
  - I used a quasi-binomial model with line, supplier and days since cleaning as controls.
  - Ambient temperature only looked significant until I allowed for the L2 regime shift in B3. After that its effect was about zero, so it acts through mold temperature.
  - Machine age is mostly a proxy for line L4 and is not significant within lines.
  - Operator effects are not significant within lines (F-test p≈0.10).
  - `cycle_time_s` matters as its deviation from the grade's recipe, with slower-than-recipe cycles giving fewer defects.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are determined by the outcome. Rework cost is about 4.2 € per defective unit, and QC minutes rise with the defect rate.
- **B3.** Line L2 shifts up from 2025-06-19. There is a persistent jump of about +0.66 in log-odds, with matching QC and rework records, that the process variables do not explain.
  - Line L3 also shows a recorded drop from 2025-07-21. There the QC minutes fall and rework cost per defect doubles, so that looks like under-recorded defects rather than a real change. I excluded it from the answer and from the model fit.

**Part C**
- **C1.** Gamma would give the lowest overall defect rate: 0.0481, against 0.0520 for Beta and 0.0602 for Alpha. This sets every batch to each supplier in turn, with the recipe cycle time.
- **C2.** About 30% humidity. The Alpha-only quadratic puts the minimum at about 29.6 to 30.0, and a cubic or quartic gives the same.
- **C3.** About 0.0522. Days since cleaning raises defects by about 1.9% per day in odds. I reset days-since-cleaning at 14 and rescaled each batch's defects by the change in fitted probability. Capping at 14 instead of resetting would give about 0.0538.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-19"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0522
}
```
