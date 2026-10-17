I cleaned the data, fitted a model of each batch's defect rate (on the log-odds scale) and checked every answer below with code.

**Data quality fixes applied first**
- **Duplicates:** 60 rows were exact duplicates of other rows, leaving 3,000 unique batches.
- **Dates:** dates came in three formats (ISO, MM/DD and DD/MM). Where both readings were possible, I picked the one that fits the file's date order.
- **Text labels:** shift was written ten different ways and supplier codes had mixed case and spaces; I standardised both.
- **Missing humidity:** blank values and the value `-1` count as missing.
- **Mold temperature:** a reading of `0` counts as invalid. Line L3 logs in °F, so I converted those values to °C.
- **Line L1 temperature sensor:** after the sensor was replaced on 2025-04-14, L1's readings jumped by about +6.2 °C compared with other lines at the same ambient temperature. Defect rates did not change at that point, and the defect data fit much better if the new sensor reads high. So I subtracted 6.17 °C from L1 readings from that date on.
- **Days since cleaning:** for each batch I counted the days since that line's last mold cleaning.
- **Cycle time:** I measured it as the deviation from the recipe time of the resin grade.

**Justifications**
- **A1:** 3,060 rows, 3,000 unique `batch_id`s, and every duplicate is an exact copy.
- **A2:** 226 unique batches have a blank humidity value or the placeholder `-1`.
- **A3:** Total defective units divided by total units produced over the 3,000 batches is 0.05503.
- **A4:** After dropping 0-readings, converting L3's °F to °C and removing the +6.17 °C offset on L1 after the sensor change, the median is 211.8 °C. Without the sensor fix it would be 212.8 °C.
- **B1:** With line, supplier, line-change periods and the other variables held fixed, mold temperature, humidity (whose effect differs by supplier), cycle-time deviation and night shift (+0.16 on the log-odds scale) are all strongly significant. Machine age has no effect within any line (the high L4 rate is a line effect), ambient temperature works only through mold temperature (p=0.23), and operators add nothing once line is fixed (p=0.32).
- **B2:** Rework cost is about €4.2 per defective unit (correlation 0.95), and QC inspection time rises by about 0.08 minutes per defect, so both follow from the outcome.
- **B3:** After accounting for the process variables, L2's defect rate jumps by about +0.65 on the log-odds scale from 2025-06-16 and stays there. L3's drop from 2025-07-21 is not a real improvement: QC inspection time was halved on the same date (about 22 to 13.5 minutes), so fewer defects were being found, not fewer made.
- **C1:** I re-ran the model for all batches with one supplier at a time, keeping each batch's cycle-time deviation from its grade's recipe. That gives Alpha 0.0606, Beta 0.0521 and Gamma 0.0484, so Gamma is lowest. Setting cycle times exactly to the recipe gives the same ranking.
- **C2:** For Alpha, the effect of humidity is U-shaped with its minimum at about 29.7%. A more flexible curve has a flat bottom between roughly 26% and 30%, so I answered 29.7.
- **C3:** Each day of mold age adds about 0.019–0.020 to the log-odds of a defect. Resetting the cleaning count every 14 days lowers the expected rate to about 0.0519, against 0.0550 actual.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.0550,
  "A4_median_mold_temp_c": 211.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.7,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
