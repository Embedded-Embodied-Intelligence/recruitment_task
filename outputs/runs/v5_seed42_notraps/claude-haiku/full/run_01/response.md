The defect share is driven by mold temperature, humidity, cycle time, shift, supplier, and line, and the best counterfactual supplier is Beta. The cleaning schedule and the L1 sensor swap have no detectable effect, and the apparent operator effect disappears once overdispersion is accounted for.

**Data checks:** 3,000 batches with unique IDs and no duplicates. Humidity has 226 blanks and mold temperature has 49, with no sentinel values or stuck sensors. Operators are nested within lines, and the defect counts are overdispersed (Pearson dispersion about 2.27), so I used dispersion-scaled tests throughout.

**Part A**
- **A1:** 3000 unique batch IDs, no duplicates.
- **A2:** 226 batches have a blank humidity reading; all non-blank values are in the physical range 12.1–72.3%.
- **A3:** 69,910 defective units out of 1,604,080 produced gives 0.043582.
- **A4:** Median mold temperature over the 2,951 valid readings is 210.0 °C. The L1 sensor replacement on 2025-04-14 shows no detectable level offset (coefficient 0.2 ± 0.5 °C), so I used the recorded values.

**Part B**
- **B1:** Mold temperature (+0.029 logit per °C), humidity (−0.030 per %), cycle time (−0.040 per s), and shift (Night +0.16) are all significant after adjusting for everything else. Machine age and ambient temperature are null. Operator is not significant once dispersion is accounted for (LR 60.5 on 20 df, quasi-p = 0.14).
- **B2:** No batch column is determined by the outcome. Cycle time is a controllable input, and `units_produced` is uncorrelated with the defect rate (r = −0.002).
- **B3:** No line shows a persistent abrupt shift. The best change-point scan gives a dispersion-scaled statistic of 7.5 at most (L1, 2025-08-15), which is within noise for about 200 candidate dates. The L1 sensor date gives no break (statistic 0.02).

**Part C**
- **C1:** Beta gives the lowest counterfactual rate (0.0370), versus Gamma (0.0424) and Alpha (0.0473), with every batch at cycle time 30 s.
- **C2:** For Alpha, the defect rate falls monotonically with humidity across the observed range (the quadratic term is not significant, and its vertex lies outside the range), so the minimum is at the top of the range, 72.3%.
- **C3:** The post-14-day cleaning effect is not significant (coefficient 0.010, SE 0.012), so regular cleaning changes the expected rate only marginally, from 0.043582 to 0.043525.

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
  "C3_rate_with_regular_cleaning": 0.043525
}
```
