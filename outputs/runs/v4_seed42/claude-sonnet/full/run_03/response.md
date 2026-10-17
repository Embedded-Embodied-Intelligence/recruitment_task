Everything below comes from code I ran on the files. Tolerances on C2 and C3 depend on the modelling choices noted in each answer.

**Data cleaning**
- **Duplicates:** 60 duplicate batch rows were removed.
- **Dates:** The date format differs by line. L1 uses MM/DD/YYYY, L4 uses DD/MM/YYYY, and L2 and L3 use ISO.
- **Labels:** The `shift` and `supplier_code` labels were inconsistent and I normalised them.
- **Humidity:** The −1 values are a missing-reading code, not a measurement.
- **Mold temperature:** L3 reports in °F. A value of 0 means no reading. After the L1 sensor was replaced on 2025-04-14, L1 reads about 7.6 °C too high, which I corrected.

**Answers**
- **A1:** 3000 unique `batch_id`s remain after removing exact duplicate rows.
- **A2:** 226 unique batches have no valid humidity reading: 55 are blank and 171 are −1.
- **A3:** 0.05503 (total defective units divided by total produced units over the 3000 batches).
- **A4:** 211.6 °C, after converting L3 from °F, dropping the 0 readings and removing the L1 post-replacement offset. The median is 212.8 °C without the L1 correction.
- **B1:** A binomial model with line fixed effects gives these results.
  - **Direct drivers:** Mold temperature, humidity, cycle time and shift all have direct effects.
  - **Machine age:** It has no effect within any line. Its apparent effect is just line L4, whose machines are old.
  - **Ambient temperature:** It acts only through mold temperature (p=0.9).
  - **Operator:** It is not a driver. Operators work on one line only, and within-line tests are non-significant.
- **B2:** `qc_inspection_min` and `rework_cost_eur` both rise with the number of defects found, so they follow the outcome and can't be predictors.
- **B3:** L2 shows a persistent jump of about +0.6 in log-odds (roughly 1.8 times the expected defect rate) from 2025-06-16, which the process variables don't explain. L3's recorded rate falls from 2025-07-21, but that is not real. QC inspection time drops from about 24 to 14 minutes and the rework cost per defect more than doubles on that date, so I treated it as an inspection change, not a change in production.
- **C1:** Gamma. I set every batch to each supplier in turn, with cycle time at that grade's recipe value and the humidity that supplier's resin needs. Predicted overall rates were Gamma 0.0504, Beta 0.0545 and Alpha 0.0635.
- **C2:** About 29.7%. Alpha (not pre-dried) has a U-shaped humidity effect, and the fitted minimum is 29.7%, which lies within the observed range.
- **C3:** About 0.0518. Defect odds rise by about 2% per day since the last cleaning, so I reset the days-since-cleaning count at day 14 in the model.

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
  "C3_rate_with_regular_cleaning": 0.0518
}
```
