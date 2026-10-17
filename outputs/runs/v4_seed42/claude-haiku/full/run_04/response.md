## Data preparation

- **Duplicates:** 60 exact duplicate rows, so 3,060 raw rows became 3,000 unique batches.
- **Dates:** each line uses its own format. L2 and L3 are ISO, L1 is MM/DD/YYYY, and L4 is DD/MM/YYYY. Everything parsed to the stated period.
- **Labels:** shift has 10 spellings, reduced to Day/Night. Supplier codes had case and whitespace variants, normalised.
- **Humidity:** blanks and the −1 sentinel are treated as missing.
- **Mold temperature:** 49 readings of 0.0 are missing. All 737 L3 readings are in °F and were converted to °C.
- **L1 sensor:** a mold temperature sensor was replaced on L1 on 2025-04-14. From then on, L1 reads about 8.5°C high against L2 and L4 at the same ambient temperature. I correct L1 readings after that date by 8.5°C. This is an estimate from the data, not a calibration record.

## Answers

- **A1:** 3,000 unique batch IDs after removing the duplicates.
- **A2:** 226 unique batches have a blank humidity (56 raw rows) or the −1 sentinel (177 raw rows).
- **A3:** 0.0550318 (total defective units / total produced units over the 3,000 batches).
- **A4:** 211.4°C. Only the Fahrenheit fix gives 212.8°C, but the L1 sensor correction brings the value in line with what the defect data supports (the ambient effect disappears). The estimate is stable at 211.4–211.6 for offsets from 7.5 to 8.5°C.
- **B1:** Mold temperature, humidity, cycle time, shift and operator all have clear direct effects in a binomial model that controls for the others. Ambient temperature has no direct effect once the corrected mold temperature is in the model (p ≈ 0.5). Machine age is at most a borderline effect (p ≈ 0.04 with flexible controls), it reverses sign between lines, and its size is negligible, so I excluded it.
- **B2:** `rework_cost_eur` is about €4.5 per defective unit, and `qc_inspection_min` rises with the defect count (about 0.08 min per defect). Both are recorded from the inspection that counts the defects.
- **B3:** L2 shows a clear break on 2025-06-15. Its defect rate goes from 4.1% to 9.4% and stays high to September, and it is not explained by mold temperature, humidity, ambient temperature, cleaning age, operator or supplier. L3 also shows a break (2025-07-21), but there the QC inspection time falls from about 23 to 14 minutes, so the drop is in recording, not in production.
- **C1:** Gamma. With each grade run at its standard cycle time, Gamma gives 4.79% overall, against 5.21% for Beta and 6.04% for Alpha. Gamma stays lowest when the supplier-specific humidity response is removed.
- **C2:** About 29%. The Alpha humidity curve is U-shaped; the quadratic gives 29.3%, and the spline fits give 27–29%.
- **C3:** 0.0517. Adding a cleaning every 14 days (I treated the log as one mold per line) lowers the model-predicted rate from 5.50% to 5.17%.

Caveats: the L1 correction is an estimate. If the L1 readings are not corrected, A4 becomes 212.8°C. I did not change any files in the repository and I did not commit anything.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.0550318,
  "A4_median_mold_temp_c": 211.4,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "operator_id", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-15"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.3,
  "C3_rate_with_regular_cleaning": 0.0517
}
```
