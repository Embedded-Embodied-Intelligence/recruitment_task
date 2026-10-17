The numbers below come from executing Python on the three files.

**A1.** The file has 3,060 rows, but 60 are exact duplicates. That leaves 3,000 unique `batch_id`s.

**A2.** 226 unique batches have no valid humidity reading: 55 are blank and 171 hold the sentinel value -1.

**A3.** Total defective units divided by total produced units over the unique batches is 0.059775.

**A4.** Line L3 logs mold temperature in °F (about 412), and 0 marks a missing reading. I converted L3 to °C and dropped the zeros. The maintenance log says L1's sensor was replaced on 2025-04-14, and on 2025-09-22 a calibration check found it reads 8 °C too high. L1 jumps by about 8 °C on exactly that date, so I subtracted 8 °C from L1 readings from 2025-04-14 on. The median actual mold temperature is 210.9 °C.

**B1.** I fitted a binomial GLM weighted by units produced, with a step term for the L2 shift from B3. Mold temperature, humidity, cycle time and shift are strongly significant (shift p≈1e-47). Ambient temperature is not (p=0.87), and neither is machine age (p=0.10). Operators are nested within lines, and their within-line effect is marginal and inconsistent (joint F≈1.8), so I treated them as noise. The apparent effects of age and ambient temperature came from line and time confounding.

**B2.** `qc_inspection_min` and `rework_cost_eur` are recorded after the defects occur and rise with the defect rate, so they must not be used as predictors.

**B3.** Line L2's residual defect level jumps after 2025-06-16 and stays high, a step of about +0.66 on the log-odds scale. The jump is not explained by the process variables. The best-fit break date is 2025-06-16, and the fit is nearly as good for 06-15. L1's temperature jump is a sensor offset, not a defect shift.

**C1.** I predicted total defects with every batch assigned to each supplier in turn. The rates are Beta 0.0537, Gamma 0.0619 and Alpha 0.0625, so Beta is best.

**C2.** Alpha is not pre-dried, so its humidity curve is quadratic. The fitted minimum is at 29.8% humidity, which is inside the observed 12.1–72.3% range. A cubic variant puts it at 29.4%.

**C3.** I reset days-since-cleaning to its value modulo 14, which matches a cleaning on every 14th day. The model then predicts a rate of 0.0562 for the period.

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
  "C3_rate_with_regular_cleaning": 0.0562
}
```
