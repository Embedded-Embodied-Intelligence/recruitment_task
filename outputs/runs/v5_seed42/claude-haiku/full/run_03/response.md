## Data cleaning

- **Batches:** 60 rows are exact duplicates. 37 `batch_id`s are reused on different lines, so the batch key is `(line, batch_id)`, which gives 3,000 unique batches.
- **Dates:** the slash format is per line: L1 is MM/DD/YYYY, L4 is DD/MM/YYYY, and L2/L3 are ISO. After decoding, every date falls inside the export window.
- **Categories:** `shift` is normalised to Day/Night and `supplier_code` is trimmed and upper-cased.
- **Sensors:** L3's `mold_temp` is in °F, so I converted it. 49 readings are 0.0 and treated as missing. Humidity uses −1.0 as a sentinel and is treated as missing.
- **L1 sensor:** L1 reads about 6 °C high after the 2025-04-14 sensor replacement. Its offset is estimated at about 6.2 °C from a mold-temperature model that controls for ambient temperature and other variables. The defect-model check would instead put it near 12 °C, so the estimate is uncertain.

## Answers

**A1.** After removing exact duplicates and keying on `(line, batch_id)`, there are 3,000 unique batches.

**A2.** 226 batches have humidity missing (55) or the −1.0 sentinel (171).

**A3.** Summing recorded defects over the 3,000 unique batches and dividing by total units gives 0.055032.

**A4.** The median of the 2,951 valid mold readings is 211.8 °C after converting L3 and correcting L1 by 6.2 °C. Other offsets in the 6–8 °C range give 211.6–211.8 °C; a 12 °C offset would give 210.7 °C.

**B1.** In a binomial GLM with all other candidates controlled, mold temperature, humidity (U-shaped and supplier-dependent), cycle time, operator, and shift each stay strongly significant. Machine age is not significant. Ambient temperature has a small residual association that vanishes with month fixed effects, so I treated it as acting through mold temperature.

**B2.** `qc_inspection_min` depends on the defect count (its R² rises from 0.20 to 0.46 when defects are added), and `rework_cost_eur` is about 4.2 times the defect count. Both are recorded after the outcome.

**B3.** L2's defect rate steps up from 16 June 2025 by about a factor of two. The rework-per-defect ratio stays flat, so the real defect share rose, and no measured variable in the model explains it. L3 drops from 21 July, but its rework per recorded defect roughly doubles (about 4.2 → 9), so this is an undercount in the recorded defects, not a real fall.

**C1.** Gamma gives the lowest counterfactual rate at 0.0478, versus 0.0516 for Beta and 0.0604 for Alpha. Its standard 36 s recipe lowers defects through cycle time, and at typical humidity its supplier effect is not worse.

**C2.** The fitted humidity curve for Alpha has its minimum at about 30.5%. Spline fits place the minimum between 24% and 33%, so the value is uncertain.

**C3.** Adding a clean every 14 days lowers the mean days-since-cleaning from 9.8 to 5.8, and the spline model gives a rate of 0.05197. Applying the covered-batch ratio across all batches is my assumption; leaving uncovered batches unchanged gives 0.05225.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "operator_id", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30.5,
  "C3_rate_with_regular_cleaning": 0.05197
}
```
