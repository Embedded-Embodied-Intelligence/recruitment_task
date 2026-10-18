All ten answers come from executed Python on the cleaned data. A few conclusions depend on judgement calls, which I flag below.

**Cleaning applied.**
- I dropped 60 exact duplicate rows.
- `batch_id` is only unique per line's terminal (the same ID appears on different lines with different data), so a batch is identified by line plus `batch_id`.
- Dates are `YYYY-MM-DD` on L2 and L3, `MM/DD/YYYY` on L1 and `DD/MM/YYYY` on L4.
- Shift labels and supplier codes had mixed case and stray spaces, which I normalised.
- Humidity values of -1 or blank are invalid.
- Mold temperature 0 is a failed reading. L3 reports in °F, so I converted it to °C.

**Part A**
- **A1:** There are 3000 unique batches, identified by line plus `batch_id`.
- **A2:** 226 batches have a missing or invalid humidity reading. These are NaN or the -1 sentinel.
- **A3:** Total defective units divided by total produced units is 0.055032.
- **A4:** The median mold temperature is 212.8 °C, after converting L3 from °F and excluding the zero readings.

**Part B**
- **B1:** I used a binomial model with line fixed effects, and quasi-binomial standard errors.
  - Mold temperature, humidity, cycle time and shift are direct drivers.
  - Ambient temperature has no effect once mold temperature is in the model (p = 0.63). It works through mold temperature.
  - Machine age is not significant within lines (p = 0.11). It only looks important because L4 has all the old machines.
  - Operator has no effect within lines. Each operator works on one line only.
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the defect count, not inputs to it. Rework cost per defective unit is about 4.2 euros.
- **B3:** L2 shows a real, persistent step up in defects from 2025-06-16 that the process variables don't explain, about 2.1 times the odds. L3 also has a step, down from 2025-07-21, but I didn't count it. Inspection minutes on L3 fell from 22.6 to 13.7 and rework cost per defect more than doubled, so it looks like an inspection change rather than a real change in what the line produces.

**Part C**
- **C1:** I predicted each supplier's overall rate with the grade's recipe cycle time and everything else unchanged. The rates are Alpha 0.0604, Beta 0.0517 and Gamma 0.0477, so Gamma is lowest.
- **C2:** For Alpha batches the humidity–defect curve is a parabola with its minimum at about 30.5%.
- **C3:** The log shows L4 with no cleaning from 2025-02-01 to 2025-04-11, yet L4 defect rates stayed flat through that stretch. I think the log is missing L4 cleanings there, so I left those 114 L4 batches unchanged.
  - For the other batches, I reset days since cleaning to the remainder after dividing by 14, then shifted each batch's odds using the fitted per-day effect.
  - That gives about 0.052. Without the L4 exclusion the answer would be 0.0529.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 212.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30.5,
  "C3_rate_with_regular_cleaning": 0.0521
}
```
