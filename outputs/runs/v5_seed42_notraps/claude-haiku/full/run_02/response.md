Results from the analysis (all computed in Python from the three CSVs; no files were written to the project directory):

1. **A1:** 3,000 rows, and all `batch_id` values are unique even after normalizing case and whitespace.
2. **A2:** 226 humidity cells are empty. No sentinel, negative, or out-of-range values exist; five readings at exactly 12.1 look plausible and are kept.
3. **A3:** 69,909 defective units out of 1,604,078 produced gives 0.043582.
4. **A4:** Median of the 2,951 recorded mold temperatures is 210.0 °C. A likelihood-profile test on L1 before its 2025-04-14 sensor replacement found no offset, so no correction was applied.
5. **B1:** In a binomial GLM with units as trials, mold temperature (+0.029 logit per °C), humidity (−0.030 per %), cycle time (−0.040 per s), and night shift (+0.16) are significant. Machine age and ambient temperature are not (p > 0.6). Operator within line is not significant once overdispersion (about 2.3) is accounted for (p ≈ 0.15).
6. **B2:** No `batches.csv` column is computed from the defect outcome, so the list is empty. `units_produced` is the denominator and is not affected by defects.
7. **B3:** Scanning each line for an intercept shift on a date, controlling for process variables, the largest candidate (L2 from 2025-05-27) falls within the simulated null distribution (p ≈ 0.15), so there is no regime change.
8. **C1:** Under the 30 s recipe, Beta (SP-02) gives an expected overall rate of 0.0372, versus 0.0426 for Gamma and 0.0475 for Alpha.
9. **C2:** Humidity has a monotone effect with no quadratic term or supplier interaction, so Alpha's expected rate is lowest at the top of the observed range, 72.3%.
10. **C3:** Days since cleaning has no detectable effect (LR p ≈ 0.5; observed/expected ≈ 1.0 in every bin), so adding 14-day cleanings leaves the rate at the A3 value. The model's point estimate of a 0.00007 drop is within noise and I did not use it.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.043582,
  "A4_median_mold_temp_c": 210.0,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": [],
  "B3_regime_change": null,
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 72.3,
  "C3_rate_with_regular_cleaning": 0.043582
}
```
