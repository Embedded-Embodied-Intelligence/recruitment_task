Everything below comes from code I ran on the three files.

- **A1.** The file has 3,060 rows, but 60 are exact duplicate rows, so there are 3,000 unique batches.
- **A2.** The humidity reading is missing (NaN) for 55 batches and is the sentinel −1 for 171 more, so 226 batches have no valid reading.
- **A3.** Total defective units divided by total produced units over the 3,000 unique batches is 0.055032.
- **A4.** Line L3 logs mold temperature in °F, and 0.0 is a failed reading, so I converted L3 to °C and dropped the zeros. L1's readings jump by about 8 °C after the sensor replacement on 2025-04-14. Defect rates did not rise, so I treated that as sensor miscalibration and subtracted 8 °C from L1 readings after 2025-04-15. The median actual mold temperature is 211.5 °C. Without the L1 correction it would be 212.8 °C.
- **B1.** In a model that controls for the other variables, mold temperature, humidity, cycle time (relative to the grade's recipe) and shift are all significant. Ambient temperature, machine age and operator are not. Ambient temperature acts only through mold temperature. Machine age is mostly a line-level difference (line L4 has the oldest machines), with no effect within a line. Operators are nested within lines, and their effects are not significant beyond the line effect.
- **B2.** `qc_inspection_min` and `rework_cost_eur` are driven by the number of defects found. `rework_cost_eur` is about 4 EUR per defective unit with R² of about 0.97. `qc_inspection_min` rises with defect count.
- **B3.** L2 shows a persistent jump in defect rate starting 2025-06-15, about a 1.9× odds increase with all process variables controlled. L3 shows a drop from 2025-07-21, but I took that as a measurement artifact. QC time per defect fell by about 8.6 minutes there, which suggests inspections got shorter and caught fewer defects.
- **C1.** With the cycle time set to each grade's recipe, the expected overall defect rates are Gamma 0.0479, Beta 0.0518 and Alpha 0.0606. Gamma is lowest.
- **C2.** For Alpha, the defect rate is U-shaped in humidity, with its minimum at about 29.7 %. A flexible fit puts the minimum at 28.5 %.
- **C3.** I simulated an extra cleaning whenever 14 days had passed since the last cleaning, kept the logged cleanings, and used the fitted model's per-day increase in defects. That gives an expected overall rate of 0.0518.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.5,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
