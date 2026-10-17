All ten answers are computed from the data. The main findings are that the L2 break, the sensor problems, and line confounding each change the answer if ignored.

- **A1:** 3,000 unique batches. The 3,060 rows include 60 exact duplicates, which I removed.
- **A2:** 226 batches lack a valid humidity reading: 55 are blank and 171 carry the −1.0 sentinel.
- **A3:** 0.059775 overall (102,831 defective units out of 1,720,295 produced).
- **A4:** 210.9 °C. I dropped 49 zero mold readings, converted L3 from °F to °C (its readings are about 412, and the maintenance log doesn't say why), and removed the +8.0 °C L1 sensor offset from its 2025-04-14 replacement. The L1 correction lowers deviance by about 245 in the fitted model, which supports it.
- **B1:** `mold_temp`, `humidity_pct`, `cycle_time_s`, and `shift` have direct effects in a binomial GLM with line, supplier, days since cleaning, and an L2 break term. Ambient temperature (p = 0.83) and machine age (p = 0.13) do not once those terms are in. Operator is not direct either: the within-line permutation test gives p = 0.17. Operator and line are fully confounded, and the raw ambient correlation is driven by the L2 break.
- **B2:** `rework_cost_eur` is almost fully determined by defective units (R² = 0.98). `qc_inspection_min` rises with defects, t ≈ 44 after controls, so both are recorded after the outcome.
- **B3:** L2 shows a clear step up of about +0.66 log-odds that the process variables don't explain. Its best onset is 2025-06-16 by deviance; 2025-06-15 is almost as good (deviance difference 4.5), since that day's batches are mixed. No other line has a comparable break.
- **C1:** Beta (SP-02) gives the lowest rate, 5.37 %, against Alpha 6.24 % and Gamma 6.19 %, with all batches re-priced under the fitted model. Raw data ranks Alpha lowest only because Beta mostly runs on L4, the high-defect line. Beta is also less sensitive to humidity.
- **C2:** Alpha's humidity effect is U-shaped, with a linear coefficient of −0.0675 and a quadratic of +0.00113 per %². The minimum is 29.8 %, inside the observed range of 12.1–72.3 %.
- **C3:** A 14-day cleaning cycle cuts the mean days since cleaning from 8.4 to 5.7 and gives an expected rate of 0.05603 (model-expected baseline 0.05982, against 0.05978 observed). A categorical days term gives 0.05612, but the linear term fits as well (p = 0.25), so I kept the linear one.

Assumptions: missing humidity and mold values are integrated out by Monte Carlo draws from their observed distributions, since they are independent of the other covariates. The overdispersion (scale ≈ 2.9) is handled with quasi-binomial standard errors.

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
  "C2_optimal_humidity_pct": 29.76,
  "C3_rate_with_regular_cleaning": 0.05603
}
```
