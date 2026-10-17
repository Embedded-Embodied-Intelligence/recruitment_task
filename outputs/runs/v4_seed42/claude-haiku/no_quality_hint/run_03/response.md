## Summary

Cleaning, modelling, and the counterfactuals are done and the answers below are from executed code. Key data fixes:

- **Duplicates:** 60 exact duplicate rows removed, leaving 3,000 batches.
- **Dates:** mixed ISO and slash formats. About 557 slash dates are ambiguous (DD/MM or MM/DD). I resolved them to the reading closest to the neighbouring batches on the same line, since the file is chronological per line. I could not verify this against the source system.
- **Shift and supplier:** spellings and case normalised (`N`/`D`/`night` → Night/Day; `sp-01` → SP-01).
- **Mold temperature:** L3 is logged in °F for the whole period, so I converted it to °C. Zero readings are dropouts.
- **Humidity:** `-1` is a sentinel, treated as invalid together with blanks.
- **Model:** quasi-binomial logit on batch defect counts, with humidity by supplier (pre-drying changes the slope), plus step terms for three issues:
  - L2 real shift from 2025-06-15.
  - L1 mold-sensor offset after the 2025-04-14 replacement.
  - L3 under-recording of defects from 2025-07-21. Rework cost per recorded defect roughly doubles and QC time halves there, so the recorded share falls even though the real share rises.

## Justifications

- **A1:** 3,000 unique batches after removing 60 exact duplicate rows.
- **A2:** 226 batches have invalid humidity: 55 blank and 171 with the `-1` sentinel.
- **A3:** 94,671 defective ÷ 1,720,295 produced = 0.05503.
- **A4:** Median of 2,951 valid readings after L3 °F→°C conversion and dropout removal is 212.8 °C. The L1 sensor replacement left readings about 6 °C high after 2025-04-14; removing that offset would give 211.8 °C. I did not apply that correction because the offset is estimated, not documented.
- **B1:** Mold temperature, humidity, cycle time, and shift stay significant with all others controlled (p < 1e-10). Ambient temperature has no effect once the L3 recording artefact is controlled (p = 0.89), and machine age is not significant (p = 0.17). Operators are nested in lines; within each line they are not significant (three of four lines p > 0.2, L4 p = 0.05), so they are excluded. The pooled operator test is borderline (p ≈ 0.02), so that call is the least certain.
- **B2:** `rework_cost_eur` is about €4.25 per defective unit (R² 0.89). `qc_inspection_min` tracks the defect count and moves with the QC change on L3.
- **B3:** L2's defect share steps up from 2025-06-15 (logit +0.66, χ² ≈ 360). Its rework cost per defect is unchanged, so the rise is real and not explained by mold temperature, humidity, cycle time, shift, or cleaning age. The L3 drop is a recording artefact, as above. The 06-15 date is the best-fitting break; 06-12 and 06-14 are nearly as good.
- **C1:** With each grade's standard recipe cycle time (30 s for PP-H350, 36 s for PP-H420), Gamma gives the lowest rate at 0.0480 (Beta 0.0520, Alpha 0.0604). Without the recipe change, Beta would be lowest, so the recipe step decides it.
- **C2:** Alpha-only quadratic vertex at 29.6% (SE 0.4); cubic 29.3%, spline 29.1%. Binned estimates are flat between about 25% and 30%, so the optimum is in that band.
- **C3:** Setting each batch's days-since-cleaning to `days mod 14` (17% of batches exceed 14 days) lowers the recorded rate from 0.05503 to 0.05176. Linear, spline, and binned cleaning-age specifications give 0.05176–0.05190.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 212.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.6,
  "C3_rate_with_regular_cleaning": 0.05176
}
```
