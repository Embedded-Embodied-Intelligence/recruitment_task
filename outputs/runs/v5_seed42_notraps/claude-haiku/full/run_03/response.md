**A1.** 3,000 unique batches; `batch_id` is unique and there are no duplicate rows.

**A2.** 226 batches have a blank `humidity_pct`. All non-blank values lie between 12.1 and 72.3, so none are invalid.

**A3.** 69,909 defective units out of 1,604,078 produced gives 0.043582.

**A4.** The median of the 2,951 valid mold-temperature readings is 210.0 °C. The L1 sensor replacement on 2025-04-14 showed no detectable offset (0.26 °C ± 0.51), so I used the recorded values as they are.

**B1.** A binomial model of defects with all candidate variables and the line, supplier and operator controls shows likelihood-ratio effects for mold temperature, humidity, cycle time, shift and operator (p < 0.001 for all except operator at p ≈ 6e-6, still significant). Machine age and ambient temperature have no effect (p = 0.71 and 0.65).

**B2.** No column is determined by the outcome: cycle time, batch ID and units produced show no relationship with the defect rate. The list is empty.

**B3.** A step-change scan on each line, adjusting for the process variables, is strongest on L2 from 2025-05-27 (LR 22.4, p ≈ 2e-6). The process-adjusted defect rate stays about 9% higher on L2 afterwards, while the raw rate is flat because humidity rose. L1 (2025-08-15) is weaker and not persistent.

**C1.** Setting cycle time to the standard 30 s recipe and assigning every batch to one supplier in the adjusted model gives Beta the lowest rate (0.0372), ahead of Gamma (0.0426) and Alpha (0.0475).

**C2.** Humidity has a monotonic negative effect on the logit defect rate (quadratic term is not significant, and the fitted vertex lies far outside the range). The Alpha expected rate is therefore lowest at the top of the observed range, 72.3%.

**C3.** Days since last cleaning has no detectable effect on defects, overall (p = 0.23) or per line. Extra cleanings therefore leave the recorded defect rate unchanged at 0.043582.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.043582,
  "A4_median_mold_temp_c": 210.0,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift", "operator_id"],
  "B2_leakage_columns": [],
  "B3_regime_change": {"line": "L2", "date": "2025-05-27"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 72.3,
  "C3_rate_with_regular_cleaning": 0.043582
}
```
