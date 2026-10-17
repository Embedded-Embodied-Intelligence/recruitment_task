**A1.** After dropping 60 exact duplicate rows, there are 3,000 unique `batch_id`s.

**A2.** 226 batches have no valid humidity. 55 are blank and 171 have the sentinel value −1.

**A3.** Total defective units divided by total produced units over the 3,000 batches is 0.05503.

**A4.** The median actual mold temperature is 211.72 °C, after three cleaning steps:
- Line L3 reports in °F, so I converted it.
- Zero readings are invalid, so I dropped them.
- Line L1 reads about 7 °C too high after its sensor was replaced on 2025-04-14. The temperature regression gave 7.0 °C, and the defect-rate cross-check gave about 8 °C, so I subtracted 7 °C.

**B1.** A binomial GLM with line fixed effects shows direct effects for `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift`. The other three candidates are not direct drivers:
- `ambient_temp_c` (p = 0.5) works only through `mold_temp`.
- `machine_age_years` (p = 0.25) has no effect; it only looks important because L4's presses are old.
- `operator_id` has no effect once line is controlled for, because operators work on one line each. The likelihood-ratio test is only borderline (p ≈ 0.04), and the within-line operator residuals look like noise.

**B2.** `qc_inspection_min` and `rework_cost_eur` rise with the number of defects, so they are consequences of the outcome and must not be used as predictors.

**B3.** L2 shifts abruptly on 2025-06-16: its log-odds of a defect jump by about 0.66, which no process variable explains. L3's recorded defects drop after 2025-07-21, but `qc_inspection_min` falls from about 22 to 14 minutes on the same day. That points to less thorough inspection, not a better process, so I excluded those L3 batches when fitting.

**C1.** I set every batch to each supplier in turn, kept the batch's own deviation from the recipe cycle time, and used the fitted humidity curve for that supplier. Gamma gives the lowest overall rate, about 0.0501. Beta gives 0.0543 and Alpha gives 0.0628.

**C2.** For Alpha batches the fitted humidity curve is U-shaped, with a minimum at about 30%. A spline fit puts it at 29.5%, so I report 30.

**C3.** Defect risk rises linearly with days since the last cleaning, by about 2% in odds per day. I simulated a forced cleaning whenever 14 days had passed, which caps days-since-cleaning at 13. That lowers the expected plant rate to about 0.0534, from a modelled 0.0570. It is a true-process estimate, so it does not include the L3 under-detection after 2025-07-21.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.72,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0534
}
```
