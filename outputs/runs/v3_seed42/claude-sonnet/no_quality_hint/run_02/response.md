All ten answers come from Python run on the data. The steps below were needed because the raw files are messy.

**Data cleaning**
- The file has 60 exact duplicate rows, which I removed.
- Shift labels and supplier codes came in inconsistent spellings, so I normalised them.
- Humidity has 55 blanks and 171 values of −1. The −1 is a sentinel for a failed reading, so I treated it as missing.
- Mold temperature is 0 on 49 batches, which I treated as missing.
- Line L3 logs mold temperature in °F (about 410), so I converted it to °C.
- Line L1's mold temperature sensor was replaced on 2025-04-14 and later calibrated as reading 8 °C high. I subtracted 8 °C from L1 readings from 2025-04-14 onward.
- For modeling I used a binomial GLM with overdispersion correction, weighted by units produced.

**Part A**
- **A1:** There are 3000 unique batch_ids (3060 rows).
- **A2:** 226 batches have a missing or invalid humidity reading (55 blank plus 171 at −1).
- **A3:** Total defective units divided by total units produced is 0.059775.
- **A4:** After the °F and sensor-offset corrections, the median actual mold temperature is 210.9 °C.

**Part B**
- **B1:** Mold temperature, humidity (a U-shaped effect), cycle time and shift (night is higher) all have significant direct effects.
  - Ambient temperature only looked significant because of an unmodeled shift on L2. Once that is included its coefficient is about 0.
  - Operators are nested within lines and show no effect beyond the line.
  - Machine age is confounded with L4, the old line. Within a line its slope is about 0, so I did not count it.
- **B2:** `qc_inspection_min` and `rework_cost_eur` are recorded after the defects are known. Both are strongly tied to the defect count, so they must not be used as predictors.
- **B3:** L2's defect level steps up by about 87% (a coefficient of 0.62) from 2025-06-16. Process variables, supplier and days since cleaning don't explain it, and the change-point scan puts the break there.
- **C1:** Setting every batch to each supplier in the fitted model gives defect rates of Beta 0.0529, Gamma 0.0615 and Alpha 0.0622. Beta is lowest.
- **C2:** The Alpha-only fit puts the humidity minimum at about 29.8%, inside the observed range of 12 to 72%.
- **C3:** Defect risk rises about 2% per day since the last cleaning (coefficient 0.0198 per day). I reset each batch's days-since-cleaning to its value modulo 14 and shifted each batch's log-odds accordingly, which gives 0.0561.

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
  "C3_rate_with_regular_cleaning": 0.0561
}
```
