I worked from 3,000 unique batches after removing 60 exact duplicate rows. Before analysing, I fixed several problems in the raw files:
- **Dates:** line L1 writes dates as month/day/year and L4 as day/month/year; the other lines use ISO dates.
- **Labels:** shift and supplier codes were spelled inconsistently.
- **Mold temperature:** line L3 records it in °F, and readings of 0 are sensor dropouts.
- **L1 sensor:** after the sensor replacement on 2025-04-14, L1 reads about 6.4 °C higher than the other lines once ambient temperature is accounted for.
- **Humidity:** values of −1 are not real measurements.

I then fitted a binomial regression of the defect rate on the process variables. Its inputs were mold temperature, humidity by whether the resin was pre-dried, cycle time, supplier, days since the last mold cleaning, shift and line, plus two step changes on lines L2 and L3.

**A1.** There are 3,060 rows but only 3,000 unique `batch_id`s; the 60 extra rows are exact duplicates.

**A2.** 226 batches have no valid humidity: 55 are blank and 171 hold the placeholder −1.

**A3.** Total defective units divided by total produced units over the unique batches is 0.05503.

**A4.** The median actual mold temperature is 211.8 °C (2,951 valid batches). This is after converting L3 from °F, dropping the 0 readings and removing the +6.4 °C offset on L1 after the sensor swap. It is 212.8 °C without that last correction.

**B1.** Mold temperature, humidity, cycle time and shift all have strong effects with everything else held fixed; humidity's effect is U-shaped and stronger for Alpha's resin, which is not pre-dried. Ambient temperature has no effect once mold temperature is in the model. Machine age has no effect within a line (its link to defects is just that L4 has the old presses). Operator effects within a line were no larger than when I shuffled operators at random.

**B2.** `qc_inspection_min` and `rework_cost_eur` are both produced by the defects themselves, so they cannot be predictors; rework cost correlates 0.95 with the defect count.

**B3.** Yes: line L2, from 2025-06-16. On that date its defect rate jumps (about +0.66 on the log-odds scale), its inspection time rises with it, and the process variables don't explain it. L3 also drops sharply from 2025-07-21, but I treated that as a recording change rather than a real one: inspection time falls from about 22 to 13 minutes and rework cost per recorded defect doubles.

**C1.** Gamma comes out best at about 0.047, against 0.051 for Beta and 0.059 for Alpha, using each grade's standard cycle time (30 s for Alpha and Beta, 36 s for Gamma). This ranking stays the same whether or not L3's under-recording is corrected.

**C2.** For Alpha batches, the expected defect rate is lowest at about 29 % hall humidity (the fitted curve bottoms out at 28.6–29 %) and rises steeply above about 45 %.

**C3.** Cleaning every mold as soon as 14 days have passed would bring the overall rate from 0.0550 to about 0.0519. I calculated this by adding the model's predicted change for each batch to the recorded defects. I kept L3's under-recording as it is, since the question says everything else stays unchanged.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.0550,
  "A4_median_mold_temp_c": 211.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
