All ten answers are computed from the data, with the cleaning steps below. The analysis scripts are in the scratchpad directory (`/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/`).

**Cleaning applied before analysis**
- Removed 60 exact duplicate rows (3060 → 3000 batches).
- Normalised shift labels (`D`/`DAY`/` Day` → Day, `N`/`NIGHT` → Night) and supplier codes (`sp-01` → SP-01).
- Treated humidity `-1.0` and blank as invalid.
- Treated mold temperature `0` as missing.
- L3 mold temperatures are in °F; converted to °C.
- L1 mold sensor reads +8 °C after its 2025-04-14 replacement (matches the 2025-09-22 calibration check); corrected by −8 °C from that date.

**Part A**
- **A1:** 3000 unique batches after removing duplicates.
- **A2:** 226 batches have humidity missing (55) or set to the −1 sentinel (171).
- **A3:** 0.059775 = total defective ÷ total produced over the 3000 batches.
- **A4:** Median corrected mold temperature is 210.9 °C over the 2951 batches with a valid reading.

**Part B**
- **B1:** A binomial GLM with supplier-specific humidity splines, mold temperature, cycle time, shift, operator, days since cleaning and an L2 regime term. Likelihood-ratio tests keep mold temperature, humidity, cycle time, shift and operator (all p < 0.001). Ambient temperature drops out (p ≈ 0.98) once the L2 regime is included, so its earlier signal was seasonal confounding. Machine age is excluded with some doubt: its pooled effect is only borderline (p ≈ 0.01), its sign reverses between L4 and L1–L3, and binned residuals show no trend.
- **B2:** `qc_inspection_min` rises with defect count beyond what process variables explain, and `rework_cost_eur` is about 4.2 × defective units. Both are consequences of the outcome.
- **B3:** L2's residual defect rate jumps abruptly on 2025-06-15 (t ≈ −14 at the best split). No other line shows a comparable break.

**Part C**
- **C1:** Beta gives the lowest counterfactual overall rate (0.0536), against 0.0620 for Gamma and 0.0624 for Alpha, using the same model across all 3000 batches.
- **C2:** For Alpha, predicted defect rate is minimised near 29.2 % humidity. The curve is flat between about 28 % and 30 %, and a quadratic-humidity check gives 29.75 %.
- **C3:** Every mold is forced to clean whenever 14 days pass since its last cleaning, adding 36 cleanings. The model puts the benefit at about 0.0039 points, so the overall rate falls from 0.05978 to about 0.0559.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift", "operator_id"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.2,
  "C3_rate_with_regular_cleaning": 0.0559
}
```
