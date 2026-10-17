## Answers

**A1.** The file has 3,060 rows, of which 60 are exact duplicates, leaving 3,000 unique `batch_id`s.

**A2.** 55 humidity values are blank and 171 are the sentinel `-1.0`, so 226 batches have no valid reading. Valid values run from 12.1% to 72.3%.

**A3.** Total defective units divided by total produced units over the 3,000 batches is 0.055032.

**A4.** The median is 210.9 °C over the 2,951 batches with a non-zero mold reading. L3 is logged in °F and was converted. L1 reads about 11 °C high after the 2025-04-14 sensor replacement, and I applied that correction, estimated by maximum likelihood. Without it the median is 212.8 °C.

**B1.** In a binomial GLM that controls for line, supplier, shift, operator, cleaning age and the two line shifts, mold temperature, humidity (U-shaped and supplier-specific), cycle time and shift each have very strong effects. Machine age and ambient temperature have no direct effect once mold temperature and cleaning age are held fixed. Operator is borderline: the joint test is p ≈ 0.01 parametric but ≈ 0.07 by permutation, and the signal sits only in L1, so I excluded it.

**B2.** `rework_cost_eur` is almost fully determined by defective units (R² = 0.89). `qc_inspection_min` rises with the number of defects found (R² = 0.46), so both are downstream of the outcome.

**B3.** L2's defect rate roughly doubles from 2025-06-15 and the shift survives all process controls (likelihood gain ≈ 1,440). L3 also shows a step on 2025-07-21, but it coincides with an abrupt drop in inspection time from about 23 to 14 minutes, which points to a change in inspection rather than in what the line produces. The L2 date is sensitive to a few days because some dates were ambiguous.

**C1.** With each supplier used for every batch and cycle time set to its grade's standard recipe, the overall predicted rates are Gamma 0.0479, Beta 0.0520 and Alpha 0.0604. Gamma wins mainly because its 36 s standard cycle is longer than the 30 s for the PP-H350 grades, and longer cycles reduce defects.

**C2.** Humidity has a U-shaped effect whose curvature differs by supplier. For Alpha batches, the pooled expected rate is minimised at about 29.3% humidity, which matches the quadratic vertex.

**C3.** Adding a cleaning whenever 14 days have passed since a line's last one adds 36 cleanings and lowers mean days-since-cleaning from 8.4 to 5.7. Defect risk rises about 0.021 logit per day since cleaning, so the predicted overall rate falls from 0.05503 to 0.05168.

## Judgement calls to check

- **Dates:** 508 rows had ambiguous dd/mm versus mm/dd dates. I resolved them using the nearest same-line rows, which affects B3 and C3 at the margin.
- **Molds:** the cleaning log is per line, so I treated each line's mold as one mold.
- **Sensor offset:** the 11 °C correction is a model-based estimate. Offsets of 10–12 °C move A4 by only 0.2 °C.
- **Imputation:** for C1 and C3 I imputed the 226 missing humidity and 49 zero mold readings so all 3,000 batches are scored. Scoring only the complete rows gives C3 = 0.05182 and the same supplier ranking.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.3,
  "C3_rate_with_regular_cleaning": 0.051679
}
```
