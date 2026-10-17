I'll start by locating the three files and inspecting their raw contents and data quality before running any analysis.

`b.shift` collides with a DataFrame method; I'll use bracket access.

No package index access here, but numpy and scipy are available, so I'll implement the binomial GLM (IRLS) myself with Wald and likelihood-ratio tests.

Age's raw p=0.01 doesn't account for the remaining overdispersion (2.9), so I'll apply a quasi-binomial correction to the tests and look at the operator effects individually.

**Data cleaning:**
- 60 exact duplicate rows were removed.
- Shift and supplier labels were normalized.
- `humidity_pct` = -1 and blanks were treated as invalid, and `mold_temp` = 0 was treated as invalid.
- L3's mold temperature is in °F and was converted.
- L1's sensor was replaced on 2025-04-14 and a later calibration check found it reads 8.0 °C high, so I subtracted 8 °C from L1 readings from that date.

**Part A**
- **A1:** 3,000 unique `batch_id`s (3,060 rows minus 60 exact duplicates).
- **A2:** 226 unique batches have no valid humidity (blank or the -1 sentinel).
- **A3:** 0.05978, which is the sum of defective units divided by the sum of produced units over the 3,000 unique batches.
- **A4:** 210.9 °C, after converting L3 from °F, correcting L1 by -8 °C from 2025-04-14, and excluding 49 invalid zero readings.

**Part B**
- **B1:** Mold temperature (+0.029 log-odds per °C), cycle time (-0.039 per second), humidity (U-shaped, differs by supplier) and shift (Night +0.17) are direct drivers.
  - Ambient temperature was only a proxy for humidity and drops out (p = 0.70).
  - Machine age and operator are confounded with line (L4 machines are about 16 years old and each operator works on one line); within lines neither has a meaningful effect (age quasi-p = 0.13, operator differences small).
- **B2:** `qc_inspection_min` and `rework_cost_eur` are consequences of the defects. Rework costs about €4.2 per defective unit on every line, and inspection time rises with the defect count.
- **B3:** L2 has a step of about +0.66 log-odds (about 1.9× the defect rate) that persists from mid-June to the end of the data and that the process variables don't explain. The other lines show no comparable shift.
  - The exact start date is slightly uncertain: 06-16 has roughly 65% likelihood weight against 35% for 06-15, so I used 2025-06-16.

**Part C**
- **C1:** Gamma. A counterfactual with all resin from one supplier, using each supplier's humidity curve, gives Gamma 0.0566, Beta 0.0578 and Alpha 0.0625, and Gamma is best in 89% of bootstrap fits.
- **C2:** About 29.8% humidity. Alpha's fitted quadratic bottoms out there, with a bootstrap interval of about 29.0–30.5, and a cubic fit gives about 29.4.
- **C3:** About 0.0560. I reset days since last cleaning to its value modulo 14, using the fitted effect of +0.020 log-odds per day since cleaning. Three estimation variants (0.05599, 0.05605, 0.05616) all give about 0.0560.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.0598,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
