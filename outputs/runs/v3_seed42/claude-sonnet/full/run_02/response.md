The answers below come from code I ran on all three files.

**Data cleaning**
- There were 3,060 rows but only 3,000 unique `batch_id`s, because 60 rows were exact duplicates. I dropped them.
- `shift` and `supplier_code` had inconsistent spellings and whitespace, which I normalised.
- Humidity has 55 blanks and 171 values of −1, a sentinel for "no reading". I treated both as missing.
- `mold_temp` is in °F on L3, with values around 410 against about 210 on the other lines. I converted L3 to °C.
- Mold temperature also has 0 values, which I treated as missing.
- The maintenance log says L1's sensor reads 8 °C too high. L1's readings run about 7.8 °C above the other lines from 2025-04-15, so I subtracted 8 °C from L1 from that date.

**Part A**
- **A1:** There are 3,000 unique batches.
- **A2:** 226 batches have no valid humidity reading (55 blank, 171 at −1).
- **A3:** Total defective units divided by total produced units over the unique batches is 0.05978.
- **A4:** The median actual mold temperature is 210.9 °C, after the °F conversion, the L1 offset and excluding zeros.

**Part B**
- **B1:** I fitted a binomial model with line, shift, supplier, humidity, cycle time, machine age, ambient temperature, days since cleaning and a regime step.
  - Mold temperature, humidity, cycle time and shift are significant.
  - Ambient temperature is not significant once mold temperature is in the model (p=0.81). It only acts through mold temperature.
  - Machine age is not significant within lines (p≈0.1). The old machines are all on L4, so the apparent age effect is a line effect.
  - Operators are nested within lines, so their apparent effects are line effects.
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count, not inputs to it.
- **B3:** L2 shows a persistent step up from 2025-06-16. A step at that date fits best of all candidate dates, and it adds about +0.66 on the logit scale, after controlling for process variables.
- **C1:** Beta gives the lowest rate. Setting every batch to a single supplier gives 5.37% for Beta, 6.19% for Gamma and 6.25% for Alpha.
- **C2:** For Alpha, the fitted quadratic in humidity bottoms out at about 29.8%.
- **C3:** Days since cleaning raises the odds of a defect by about 2% per day (coefficient 0.0203 on the logit scale). I reset each batch's days-since-cleaning to its value modulo 14. That gives an expected overall rate of 0.0560.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
