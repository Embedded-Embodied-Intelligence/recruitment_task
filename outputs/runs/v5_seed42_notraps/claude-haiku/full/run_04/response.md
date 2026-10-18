**A1.** 3000 unique batches; `batch_id` has no duplicates and every ID matches the expected format.

**A2.** 226 batches have a blank `humidity_pct`. All non-blank values fall between 12.1 and 72.3 %, so no other readings are invalid.

**A3.** 69,909 defective units out of 1,604,078 produced gives 0.04358.

**A4.** The median of the 2,951 non-blank `mold_temp` readings is 210.0 °C. The values are plausible Celsius throughout, and the L1 sensor replacement on 2025-04-14 shows no detectable offset in the defect relationship.

**B1.** A binomial GLM with dispersion-adjusted likelihood-ratio tests gives significant direct effects for mold temperature, humidity, cycle time and shift. Machine age and ambient temperature are null, and operator adds nothing once line is in the model (p=0.14).

**B2.** No batch column is determined by the outcome. The predictors are mutually uncorrelated, and units produced is unrelated to the defect rate.

**B3.** A step-change scan over every line and start date finds no shift larger than about 0.1 on the log-odds scale (chi-square ≈ 8 on one degree of freedom, not significant after correcting for the number of dates tested).

**C1.** Setting every batch to the recipe cycle time (30 s) and swapping the supplier gives Beta 0.0372, Gamma 0.0426 and Alpha 0.0475, so Beta is lowest.

**C2.** The Alpha humidity curve falls monotonically across the observed range, so the minimum is at the top end, 72.3 %. No quadratic or interaction term is significant, so there is no interior optimum.

**C3.** Days since cleaning has no significant effect in any line (interaction p=0.63), so the expected rate is essentially unchanged from A3. The estimated overdue effect is about 0.04348, but it is not distinguishable from zero.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.04358,
  "A4_median_mold_temp_c": 210.0,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": [],
  "B3_regime_change": null,
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 72.3,
  "C3_rate_with_regular_cleaning": 0.04358
}
```
