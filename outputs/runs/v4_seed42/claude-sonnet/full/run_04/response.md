The answers come from a Python analysis of the three files. Two judgement calls could move the numbers: the correction for the Line L1 sensor offset, and the exact start date of the Line L2 shift.

**Data cleaning**
- The raw export had 3060 rows but only 3000 unique `batch_id`s, so I removed 60 exact duplicates.
- `production_date` came in three formats: ISO on L2 and L3, MM/DD/YYYY on L1, and DD/MM/YYYY on L4. The format is fixed per line, which resolves the ambiguity.
- Shift and supplier codes had case and whitespace variants, which I normalised.
- Humidity has NaN and −1.0 placeholders.
- Mold temperature has 0.0 placeholders, and L3 reports in °F.
- L1's mold temperature reading steps up by about 7 °C on 2025-04-14, the day of the sensor replacement in the maintenance log. The defect rate does not move, so I treated it as a sensor offset and subtracted about 7.3 °C.

**Answers**
- **A1.** There are 3000 unique batches after removing the 60 duplicate rows.
- **A2.** 226 unique batches have no valid humidity reading: 55 are missing and 171 are −1.0.
- **A3.** The overall defect rate is 0.05503 (defective units divided by produced units, over unique batches).
- **A4.** The median actual mold temperature is about 211.7 °C. I excluded the 0.0 readings, converted L3 from °F and removed the L1 offset after 2025-04-14.
- **B1.** The direct drivers are `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift`. In a model with line, supplier and the cleaning interval controlled, these four are clearly significant. Ambient temperature only acts through mold temperature, and machine age and operator add nothing within a line (the operator test gave p = 0.63).
- **B2.** `qc_inspection_min` and `rework_cost_eur` are set by the outcome. Rework cost is about 4.2 € per defective unit, and inspection time rises with the defect count.
- **B3.** Line L2 shows an abrupt, persistent increase of about 80% in the defect rate, with the best-fitting break at 2025-06-15. The model also fits almost as well with a start of 2025-06-16, so the exact date is uncertain by a day. Line L3's recorded defect rate drops from 2025-07-21, but `qc_inspection_min` falls from about 22 to about 13.5 minutes on the same date. That looks like less inspection catching fewer defects rather than a real improvement, so I did not count it.
- **C1.** Gamma gives the lowest overall rate with its standard recipe (about 0.048, against 0.052 for Beta and 0.061 for Alpha).
- **C2.** For Alpha batches the expected defect rate is lowest at about 29.7% humidity. The curve is U-shaped.
- **C3.** The expected overall rate with regular cleaning is about 0.0518. The defect rate rises by about 1.8% for each day since the last cleaning, and I reset the counter to 0 every 14 days (days since cleaning mod 14). Capping at 14 days instead would give about 0.0535.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.055032,
  "A4_median_mold_temp_c": 211.7,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
