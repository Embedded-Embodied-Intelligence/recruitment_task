**Part A**

- **A1:** 3000 batches. Batch IDs are unique and there are no duplicate records under other IDs.
- **A2:** 226 batches have a blank `humidity_pct`. All non-blank values are plausible (12.1 to 72.3%).
- **A3:** 69,909 defective units out of 1,604,078 produced gives 0.043582.
- **A4:** The median mold temperature is 210.0 °C over 2,951 valid readings. Values are in the Celsius range, and the L1 sensor replacement on 2025-04-14 shows no level shift in the residuals, so no correction is applied.

**Part B**

- **B1:** Using dispersion-scaled F-tests on a binomial GLM, `mold_temp` (p≈3e-157), `humidity_pct` (p≈0), `cycle_time_s` (p≈1e-137), and `shift` (p≈2e-35) have direct effects. `operator_id` is excluded because its apparent effect is just line membership, since operators are nested in lines (within-line p≈0.14). `machine_age_years`, `ambient_temp_c` are not significant.
- **B2:** No `batches.csv` column is determined by the defect outcome, so the list is empty.
- **B3:** A change-point scan of observed versus expected defects on each line, using the process-variable model, finds no abrupt persistent shift that survives correction for multiple testing.
- **C1:** Every resin has a 30 s recipe cycle time, so all batches are set to 30 s. Beta gives the lowest counterfactual defect rate (0.0372), ahead of Gamma (0.0426) and Alpha (0.0475).
- **C2:** Humidity lowers the expected defect rate monotonically across the whole range, so the minimum for Alpha is at the top of its observed range, 72.3%.
- **C3:** Adding a cleaning every 14 days lowers the model-based rate only slightly, from 0.04358 to 0.04340. The days-since-cleaning coefficient is not significant (p≈0.43), so this change is within noise.

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
  "C3_rate_with_regular_cleaning": 0.0434
}
```
