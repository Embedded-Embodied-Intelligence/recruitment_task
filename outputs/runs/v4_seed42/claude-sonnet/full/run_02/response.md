**Answers**

- **A1.** The file has 3,060 rows but only 3,000 unique `batch_id`s, because 60 rows are exact duplicates.
- **A2.** 226 unique batches have no valid humidity: 55 are blank and 171 hold the sentinel value -1.
- **A3.** The overall defect rate is 0.05503, which is the total defective units divided by the total units over the 3,000 de-duplicated batches.
- **A4.** The median actual mold temperature is about 211.6 °C. Line L3 logs °F, so I converted it, and I dropped the 49 zero readings as invalid. The L1 sensor read about 7.5 °C too high after its replacement on 2025-04-14, so I subtracted that offset from those readings. Before the replacement, L1 matched L2 and L4, and the defect model gave a similar offset. Without that correction the median is 212.8.
- **B1.** In a binomial model with line, supplier, maintenance and the line shifts controlled, `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift` are significant. Ambient temperature acts only through mold temperature (p=0.64 once mold temperature is in). Operator is not significant (F≈1.3, 20 df). Machine age has no effect within a line (p≈0.4). It looks significant overall only because it is almost the same as the line: L4 is the old line.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count (rework cost vs defects R²≈0.89), so they must not be used as predictors.
- **B3.** L2 shows an abrupt, persistent step up in the defect rate from 2025-06-16, with a residual jump of about +0.035 and no change in the process variables. L3 also drops from 2025-07-21, but its `qc_inspection_min` falls from 22.6 to 13.7 at the same time, so that is less inspection, not better production.
- **C1.** With every batch switched to one supplier, all on that grade's standard recipe, the overall rates are Alpha 0.0605, Beta 0.0518 and Gamma 0.0479. Gamma is lowest.
- **C2.** For Alpha batches the defect rate follows a U shape in humidity, with a minimum at about 29.7% (95% interval 28.9–30.4).
- **C3.** Defects rise linearly by about 2% per day since the last cleaning, with no kink at 14 days. Resetting each mold's days-since-cleaning to its value modulo 14 gives about 0.0519.

**Data issues I fixed**
- Duplicate batch rows.
- Mixed date formats: L1 is MM/DD/YYYY and L4 is DD/MM/YYYY.
- Messy `shift` and `supplier_code` labels.
- Humidity of -1 and mold temperature of 0 treated as missing.
- L3 mold temperatures converted from °F to °C.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
