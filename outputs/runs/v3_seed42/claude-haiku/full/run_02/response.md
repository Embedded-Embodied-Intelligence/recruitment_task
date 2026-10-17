All ten answers come from code I ran on the cleaned data. The cleaning script is at `/tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py`.

**Data cleaning**
- 60 rows are exact duplicates, leaving 3,000 batches.
- `shift` has 10 spellings (Day/D/DAY/day/" Day", Night/N/…), normalised to 2 values.
- `supplier_code` has case and whitespace variants, normalised to SP-01/02/03.
- `humidity_pct`: 55 blanks and 171 values of −1 are invalid.
- `mold_temp`: 49 zeros are missing values. Line L3 is in Fahrenheit throughout, so I converted it to °C.
- L1 reads 8 °C high from the 2025-04-14 sensor replacement onward, per the calibration check, so I subtracted 8 °C from those readings.

**Part A**
- **A1:** 3,000 unique batches.
- **A2:** 226 batches have no valid humidity (55 blank plus 171 at −1).
- **A3:** Total defective units divided by total produced is 0.05978.
- **A4:** The median corrected mold temperature is 210.9 °C over 2,951 valid readings.

**Part B**
- **B1:** Mold temperature, humidity, cycle time and shift all have large, significant direct effects once the other variables are held fixed. Machine age (p≈0.13) and ambient temperature (p≈0.83) do not. Operator is borderline (pooled p≈0.03) and not significant within any single line, so I have excluded it.
- **B2:** `rework_cost_eur` is almost exactly 4.2 € per defective unit (R² 0.98), and `qc_inspection_min` depends on the defect count, so both are leakage.
- **B3:** L2 has a step change in residuals from a binomial GLM with the process variables. The likelihood peaks at 2025-06-16, with 2025-06-15 close behind (Δ log-likelihood ≈ 2.3). No other line shows a comparable shift.

**Part C**
- **C1:** Modelling humidity separately by supplier, Beta (SP-02) gives the lowest pooled defect rate, 0.0537 against 0.0619 for Gamma and 0.0625 for Alpha.
- **C2:** The Alpha curve is U-shaped. A quadratic gives 29.8 %, but flexible splines fit much better and put the minimum at about 27 %, so I report 27.0.
- **C3:** I rebuilt each line's cleaning schedule with forced cleanings every 14 days, recomputed days since cleaning, and predicted the pooled rate with the fitted model. The counterfactual is 0.0559 over all 3,000 batches (0.0562 on complete cases only).

Choices I made: L2's start date is the likelihood maximum. The L1 correction uses the documented 8 °C, although the likelihood alone prefers about 12–14 °C. The C2 optimum depends on the humidity curve's flexibility.

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
  "C2_optimal_humidity_pct": 27.0,
  "C3_rate_with_regular_cleaning": 0.0559
}
```
