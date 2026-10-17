**Data cleaning applied before any analysis**
- 60 exact duplicate rows removed, leaving 3000 unique batches.
- `shift` had 10 spellings (e.g., `Day`/`DAY`/`D`/` Day`); normalised to Day/Night.
- `supplier_code` had case and whitespace variants (`sp-01`, ` Sp-02`); normalised.
- Humidity: `-1` (171 rows) and blank (55 rows) treated as missing.
- Mold temperature: L3 is recorded in Fahrenheit throughout, so converted to °C. Zero values (49) treated as missing. L1 reads +8.0 °C after its sensor replacement on 2025-04-14, per the calibration check, so corrected from 2025-04-15 on. The L1 residual confirms the offset starts at that date.

**Part A**
- **A1:** 3000 unique batch IDs after de-duplication.
- **A2:** 226 batches have no valid humidity reading (171 sentinel `-1` plus 55 blanks).
- **A3:** 179,… total defective units over total produced units gives 0.059775.
- **A4:** The median corrected mold temperature over the 2951 valid readings is 210.9 °C.

**Part B**
- **B1:** A binomial GLM with spline terms and dispersion-scaled F-tests, with line, supplier, operator and days since cleaning all in the model, finds mold temperature, humidity (U-shaped, for every resin), cycle time, shift and operator significant. Machine age (p ≈ 0.22) and ambient temperature (p ≈ 0.73) have no direct effect once the L2 shift is included. Ambient looked important only because it tracks summer, when cleaning gaps are longer, and because of the L2 shift.
- **B2:** `rework_cost_eur` (R² = 0.98 on defect count) and `qc_inspection_min` (R² rises from 0.27 to 0.56 with defect count) are downstream of the outcome.
- **B3:** L2 shows a step in defect level. The best change point is 2025-06-15 (lowest deviance, t ≈ 15). Observed/expected defects are about 0.76 before and about 1.29 after. No other line shows a comparable shift.
- **C1:** Setting every batch to one supplier and keeping everything else fixed gives 0.0538 for Beta, against 0.0620 for Gamma and 0.0625 for Alpha. Beta is lowest.
- **C2:** The minimum for Alpha is about 28–29% on the main spline fit. The curve is very flat there, and alternative flexibility settings give 26–30%, so I report 28.5 as the central value.
- **C3:** I rebuilt each line's cleaning schedule so no gap exceeds 14 days (36 cleanings added) and recomputed days since cleaning. The same model gives a counterfactual of 0.0561 on complete cases; scaling to the full-period actual gives 0.0559.

Scripts are in `/tmp/claude-0/-tmp-edabench-claude-fzkzc2p3/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/` (`clean.py`, `model.py`).

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift", "operator_id"],
  "B2_leakage_columns": ["rework_cost_eur", "qc_inspection_min"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 28.5,
  "C3_rate_with_regular_cleaning": 0.0559
}
```
