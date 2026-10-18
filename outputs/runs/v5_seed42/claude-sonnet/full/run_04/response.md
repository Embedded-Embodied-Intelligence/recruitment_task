The overall defect rate is 0.0550, and 349 batches have no valid humidity reading. The best resin is Gamma, and Alpha is best at about 30% humidity. All numbers below come from code I ran on the three files.

**Data cleaning**
- Dates came in three formats, by line: L1 as MM/DD/YYYY, L4 as DD/MM/YYYY, and L2 and L3 as ISO.
- Supplier codes and shift labels had inconsistent case and spacing.
- 60 rows were exact duplicates.
- The 37 batch IDs shared by two different lines (such as `B-12109`) are different batches, so I kept them.
- Mold temperature was 0.0 in 49 rows, which I treated as missing. L3 reports in °F, so I converted it.
- After the L1 sensor replacement on 2025-04-14, L1 reads about 7.5 °C higher than the other lines did at the same ambient temperature. I subtracted 7.5 °C from L1 readings from that date.
- Humidity had NaN values, a −1 sentinel, and a stuck value of 50.2 on L2 from 2025-03-03 to 2025-04-13.
- L3 QC inspection time fell from about 22.6 to 13.7 minutes from 2025-07-21, and recorded defects fell with it. I treated that as an under-count, not a real improvement.

**Answers**
- **A1:** 3000 unique batches after dropping exact duplicates (batch ID plus line). Dates run 2025-01-06 to 2025-09-30.
- **A2:** 349 batches. That is 56 NaN, 177 coded −1, and the L2 stuck-sensor window, with overlaps counted once.
- **A3:** 0.05503, which is total defective units divided by total units over the 3000 unique batches.
- **A4:** 211.6 °C, after converting L3 from °F, excluding the 49 zero readings, and correcting L1 after the sensor swap. Without the L1 correction it is 212.8.
- **B1:** `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift` have direct effects, using a binomial model with line, supplier, cleaning age and the line regimes. Ambient temperature acts through mold temperature (its direct coefficient is about 0.005 and negligible). Machine age is explained by line (within-line p=0.36). Operator has no effect once line is controlled (p=0.16).
- **B2:** `qc_inspection_min` and `rework_cost_eur`. Both are consequences of the defect count.
- **B3:** L2 from 2025-06-16. Its defect rate rises by about 1.9× in odds terms and persists, and the process variables, cleaning age and humidity do not explain it. L3's drop on 2025-07-21 coincides with shorter QC inspection, so I read it as an under-count and not a real shift.
- **C1:** Gamma. With each resin at its recipe cycle time, the expected rates are Gamma 0.0490, Beta 0.0528 and Alpha 0.0622. Gamma's edge comes mostly from its longer 36 s cycle, which lowers defects.
- **C2:** About 30%. Humidity has a U-shaped effect, and Alpha, which is not pre-dried, has its minimum lower than Beta or Gamma (about 41–44%). Fits with different curve shapes gave 26–30%, and I'm giving 30.
- **C3:** About 0.0520. Defects rise with days since the last cleaning, and the mold-cleaning gaps run 26–69 days on L4 in Feb–Apr, and 28–35 days on L1, L2, L3 and L4 in Jul–Sep. I re-computed each batch's cleaning age as if cleaning happened every 14 days. Five ways of modelling the cleaning effect gave 0.0519–0.0528.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 349,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0520
}
```
