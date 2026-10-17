The answers are below. The analysis was run in Python on the three files, and nothing in the working directory was changed.

**Data cleaning, before any analysis**
- 60 rows are exact duplicates, which leaves 3,000 unique batches. No batch_id has conflicting copies.
- Dates use one format per line: L1 is MM/DD/YYYY, L4 is DD/MM/YYYY, and L2 and L3 are ISO. Shift codes (`D`, `DAY`, `n`, …) and supplier codes (`sp-01`, ` SP-02`, …) are normalised.
- Humidity values of -1 and blanks are treated as missing. Mold temperatures of 0 are treated as missing. L3 logs mold temperature in °F and is converted to °C.
- L1's mold sensor was replaced on 2025-04-14, and readings after that run about 7.4 °C high. I estimated the offset against L2 and L4 on the same days and corrected only the post-replacement L1 readings.

**A1.** 3,000 unique batches (60 exact duplicate rows removed).

**A2.** 226 batches: 55 blank and 171 coded as -1.

**A3.** Total defective units divided by total units over the 3,000 batches gives 0.05503.

**A4.** The median mold temperature after the corrections above is 211.7 °C, over 2,951 valid readings.

**B1.** Using a binomial GLM with dispersion-adjusted tests and all other measured variables in the model, mold temperature, humidity (its effect depends on resin), cycle time and shift each have a strong direct effect (p < 1e-40). Machine age (p = 0.15), ambient temperature (p = 0.72) and operator (permutation p = 0.16) add nothing once the others are held fixed.

**B2.** `qc_inspection_min` and `rework_cost_eur` are set by the inspection of the defects. Rework cost is about €4.2 per defective unit, and inspection time correlates with the defect count (r = 0.63).

**B3.** L2's defect share rises from 2025-06-16 and stays above expectation (observed/expected about 1.26 after the break). L3's recorded defects fall from 2025-07-21, but its inspection-time intercept drops by about 8.5 minutes at the same defect count, which points to a change in how defects are recorded rather than in production. The L2 start date is 06-15 or 06-16: 06-16 fits better in two of the three specifications I tried, and I report 06-16.

**C1.** Gamma gives the lowest rate, 4.78%, against Beta at 5.18% and Alpha at 6.07%. Each supplier's counterfactual uses its grade's recipe cycle time. Gamma comes out lowest whether or not the L3 recording change is removed.

**C2.** For Alpha batches with everything else held fixed, the expected rate is flat between roughly 28% and 31% humidity and is lowest at 29.2%.

**C3.** Adding a cleaning every 14 days after each actual cleaning (so no batch exceeds 13 days since cleaning) gives an expected rate of 0.05191, against 0.05508 for the fitted model without the change. If the L3 recording change is removed, the figure is 0.05425.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.7,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.2,
  "C3_rate_with_regular_cleaning": 0.05191
}
```
