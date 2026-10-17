Everything is computed and checked. Summary below, with the JSON at the end.

**Data-cleaning steps (applied before every answer)**
- 60 rows are exact duplicates, leaving 3,000 unique batches.
- Dates come in three formats. L1 is MM/DD/YYYY, L4 is DD/MM/YYYY, and L2/L3 are ISO. All parsed dates fall within 2025-01-06 to 2025-09-30.
- Shift labels (`D`, `DAY`, `night ` and so on) and supplier codes (`sp-01`, `SP-01 `) are normalised.
- Humidity: 55 blanks and 171 readings of -1.0 are treated as invalid.
- Mold temperature: L3 is in Fahrenheit, so I converted it to °C. 49 zero readings are treated as missing.
- L1's mold sensor was replaced on 2025-04-14. Before that date L1 matches L2 and L4 on the same days (+0.17 ± 0.49 °C). After it, L1 reads +7.5 ± 0.4 °C higher, so I corrected it by that amount.

**Justifications**

- **A1:** 3,060 rows contain 60 exact duplicates, leaving 3,000 unique `batch_id`s.
- **A2:** 55 blanks plus 171 sentinel readings of -1.0 gives 226 invalid humidity values.
- **A3:** 94,671 defective units out of 1,720,295 produced gives 0.05503.
- **A4:** After converting L3 to °C, dropping zeros and applying the L1 sensor correction, the median of the 2,951 valid readings is 211.6 °C.
- **B1:** A binomial GLM with batch weights, controlling for everything else, gives strong likelihood-ratio tests for mold temperature, humidity (which depends on supplier), cycle time, operator, and shift. Machine age (p≈0.15) and ambient temperature (p≈0.69, and zero on L1 before the sensor change) have no direct effect once mold temperature is held fixed.
- **B2:** `rework_cost_eur` tracks defect count (R² ≈ 0.89). `qc_inspection_min` is about 20 min plus 0.08 min per defect, so both are determined by the outcome.
- **B3:** L2's defect rate roughly doubles from mid-June, and the step survives every process variable (likelihood-ratio statistic ≈ 800). L3 also drops sharply on 2025-07-21, but its QC inspection base time falls from about 20 to 12 min on that same day, so I read it as an inspection change rather than a production change. The L1 shift is the sensor artifact.
- **C1:** Setting every batch to one supplier with that grade's standard cycle time gives Gamma 0.0480, Beta 0.0518 and Alpha 0.0606.
- **C2:** For Alpha (not pre-dried), the humidity effect is quadratic with its minimum at about 29.7%.
- **C3:** Days since the last cleaning is a strong driver (about +0.021 logit per day). Capping it at 14 days by adjusting the observed defect count lowers the overall rate from 0.05503 to 0.05211.

**Choices and caveats**
- **A4 is sensitive to the sensor correction.** Without it the median is 212.8; a 6–11 °C correction gives 210.8–211.8. I used the directly measured 7.5 °C.
- **B3 date:** The first affected date is 2025-06-15, but 2025-06-16 fits marginally better (deviance difference about 3.7), so the exact start is uncertain by a day.
- **B3 line:** I treated L3 as a measurement artifact. If it is actually a real improvement, it would be a second shift.
- **B1 scope:** Days since last cleaning is a major driver but is not on the candidate list, so it is not in B1.

Analysis scripts are in `/tmp/claude-0/-tmp-edabench-claude-cv1rg2ec/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad` (`clean.py` holds the cleaning logic).

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "operator_id", "shift"],
  "B2_leakage_columns": ["rework_cost_eur", "qc_inspection_min"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.05211
}
```
