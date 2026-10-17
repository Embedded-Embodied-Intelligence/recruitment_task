The analysis is complete. Here is what I found and how I got there.

**Data cleaning (applied before every number below)**
- Removed 60 exact duplicate rows: 3,060 rows became 3,000 unique batches.
- Resolved 569 ambiguous dates (DD/MM vs MM/DD) by nearest-neighbour ordering in the file. This rule recovers known dates 362 of 365 times in a holdout check (99.2%).
- Normalised shift labels (`D`/`Day`/`DAY`/… → Day; `N`/`night`/… → Night) and supplier codes (case and whitespace).
- Treated humidity blanks and `-1` as missing. Treated `mold_temp = 0` as missing (49 rows).
- Converted all L3 mold temperatures from Fahrenheit to Celsius: every L3 reading is above 300, and no other line has any.

**Answers**

- **A1: 3000.** This is the number of unique `batch_id`s after removing the 60 exact duplicates.
- **A2: 226.** This counts unique batches with a blank humidity or the `-1` sentinel.
- **A3: 0.055032.** This is 94,671 defective units out of 1,720,295 produced.
- **A4: 212.8 °C.** This is the median of the 2,951 valid mold readings, after the L3 conversion.
- **B1: mold_temp, humidity_pct, cycle_time_s, shift.** In a binomial model with splines and the line-level steps (see B3), these four stay significant (p < 1e-40 for each). Ambient temperature drops out once the steps are included (p = 0.43), and machine age (p = 0.15) and operator (p = 0.06) are not significant.
- **B2: qc_inspection_min, rework_cost_eur.** Both move with the outcome: rework cost correlates 0.94 with defective count, and QC time rises with defect rate (coefficient about 49, t = 28). They are recorded after the defects, so they are downstream.
- **B3: L2 from 2025-06-15.** The observed/expected ratio on L2 steps from about 0.8 to about 1.25 and stays there through September. The step survives controls for every process variable, cleaning age, and an ambient×line interaction. **L3 also has an unexplained step, from 2025-07-21, in the opposite direction (observed/expected about 1.2 → 0.6).** I reported L2 because it is the increase that threatens quality, but the JSON can name only one line, so this choice is a judgement call. The L1 step on 2025-04-14 matches a logged mold-sensor replacement, and recorded mold temperature jumps about 5 °C on that date, so I treat it as a measurement effect.
- **C1: Gamma (SP-03).** Predicted overall rates are 0.0607 (Alpha), 0.0520 (Beta), 0.0478 (Gamma), with each batch's cycle time set to its grade's recipe.
- **C2: 27.3%.** For Alpha batches the predicted rate has its minimum here, and it is flat between about 25 and 28%.
- **C3: 0.05183.** Setting each batch's days since cleaning to (days mod 14) gives this rate, against a model baseline of 0.05508.

**Caveats**
- The C1–C3 answers come from one fitted model (splines, with the three steps). They are model-based predictions, not observed outcomes.
- I did not fit a formal change-point model with a per-date likelihood ratio on every line. I used a daily scan, and the steps are robust to finer mold-temperature and ambient terms.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 212.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 27.3,
  "C3_rate_with_regular_cleaning": 0.05183
}
```
