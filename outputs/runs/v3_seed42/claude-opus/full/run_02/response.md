Below is a short reason for each answer. The JSON object with all answers is at the end.

**Data quality.** I found and handled these problems before any analysis:
- 60 rows are exact duplicates, leaving 3,000 unique batches.
- `shift` and `supplier_code` are spelled inconsistently (case, stray spaces, short forms) and were normalised.
- In `humidity_pct`, −1 is a placeholder for "no reading", not a measurement.
- In `mold_temp`, 0 is a placeholder; line L3 records in °F; and line L1's replacement sensor (fitted 2025-04-14) reads 8 °C too high, per the maintenance log.

**Model.** I fitted a binomial regression of defects on the process variables, with line effects. I added a "days since last mold cleaning" feature built from the maintenance log.

- **A1:** After removing the exact duplicate rows, 3,000 unique batch IDs remain.
- **A2:** 226 batches have no usable humidity: 49 are blank and 177 carry the −1 placeholder.
- **A3:** Total defective units divided by total units produced over the unique batches is 0.05978.
- **A4:** I dropped the 49 zero readings, converted L3 from °F to °C, and subtracted the 8 °C bias from L1 readings after the sensor swap. The median of the remaining 2,951 valid readings is then 210.9 °C, and the 2025-04-14 cutoff choice doesn't change it.
- **B1:** With everything else held fixed, mold temperature, humidity, cycle time and shift each have a clear effect on defects. Ambient temperature has none once mold temperature is in the model (p = 0.7). Machine age only looks important because the old machines are all on L4; within L4 its effect is about zero. Operators show no within-line effect: estimates from two halves of the data don't agree (correlation about −0.03).
- **B2:** `rework_cost_eur` tracks defective units almost one-for-one (correlation 0.99), and `qc_inspection_min` rises with the defect count (0.75). Both are recorded after the outcome, so neither can be used as a predictor.
- **B3:** From 2025-06-16, L2 runs about 1.5× above its predicted defect level and stays there; nothing else in the data explains it. A change-point scan puts the break on that date.
- **C1:** Beta looks worst in the raw numbers only because 78% of its batches run on L4, the line with the highest defect rate. Within every line it is the best supplier. If all batches had used Beta resin, the plant rate would be about 0.0537, against about 0.0619 for Gamma and 0.0625 for Alpha.
- **C2:** For Alpha resin, which is not pre-dried, defects follow a U-shape in humidity with the lowest point at about 29.8%. A more flexible curve puts it near 28%; the other suppliers' lowest points are around 42–44%.
- **C3:** Each extra day since a cleaning raises the odds of a defect by about 2%. Capping the gap at 14 days, with everything else unchanged, gives an expected rate of about 0.0560 instead of 0.0598.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05978,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
