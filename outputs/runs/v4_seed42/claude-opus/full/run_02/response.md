I cleaned the data, fitted a model and answered all ten questions. I couldn't confirm two things: which mold-temperature sensor on L1 reads correctly, and the exact day of the L2 change. Both are noted below.

**Data quality issues I fixed first**
- **Duplicates:** 60 rows are exact duplicates and I removed them.
- **Dates:** lines L2 and L3 write dates as YYYY-MM-DD, L1 as MM/DD/YYYY and L4 as DD/MM/YYYY. I parsed each line in its own format.
- **Text codes:** `shift` and `supplier_code` have mixed spellings and stray spaces (e.g. "D", " Day", "NIGHT"; " Sp-01", "sp-01"). I normalised them.
- **Humidity:** `-1` means "no reading", and some values are blank. I treated both as missing.
- **Mold temperature:**
  - A reading of `0.0` means "no reading".
  - Line L3 logs in °F (values around 380–465), so I converted it to °C.
  - The L1 sensor was replaced on 2025-04-14. After that, L1 reads about 6.4 °C higher than the other lines under the same ambient conditions, and the defect data matches the actual temperature not having changed. I took the new sensor to be the one that's off and subtracted the offset. The alternative (the old sensor read low) can't be ruled out from the data, but it barely moves the A4 median (211.8 vs 212.8).

**How I estimated effects:** a logistic model of the defect rate. It uses corrected mold temperature, a humidity curve that differs by supplier, cycle time, shift, days since the last mold cleaning, line effects and the two changes found in B3.

**A1.** 3,060 rows minus 60 duplicates gives 3,000 unique batch IDs.
**A2.** 226 batches have no usable humidity: 171 coded as `-1` and 55 blank.
**A3.** 173,483 defective out of 3,152,494 produced units gives 0.05503.
**A4.** The median is 211.8 °C, over the 2,951 batches with a valid reading.

**B1.** Mold temperature (about +0.03 log-odds per °C), humidity (U-shaped), cycle time (longer is better) and shift (night is worse) stay significant when everything else is held fixed. Ambient temperature only acts through mold temperature (direct effect about 0). Operators don't differ within their line (F-test p = 0.74). Machine age has no effect within a line (0.0006 ± 0.004); line L4's higher rate is a line effect that age doesn't explain.
**B2.** `rework_cost_eur` is about €4.2 per defective unit, and `qc_inspection_min` rises by about 0.08 min per defective unit, so both are produced by the outcome.
**B3.** Yes: line L2's defect rate jumps by about +0.66 log-odds and stays there, starting 2025-06-16. The best-fitting change date was 06-16, but 06-15 fits almost as well. L3's drop from 2025-07-21 is not a real change: QC inspection time there fell from about 22 to 13 minutes, so fewer defects were found rather than fewer made.

**C1.** In the simulation, Gamma gives the lowest rate (about 0.048), against about 0.052 for Beta and 0.060 for Alpha. Alpha looks best in the raw averages only because of the conditions it happened to run in.
**C2.** Alpha's defect rate is lowest at about 29.5 % hall humidity. The curve is U-shaped, rising steeply below 20 % and above 45 %.
**C3.** Extra cleanings at day 14 bring the rate down from 0.0550 to about 0.0519. I modelled this by resetting the days-since-cleaning count every 14 days. The model keeps everything else as it was, including L3's reduced inspection.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.05503,
  "A4_median_mold_temp_c": 211.8,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29.5,
  "C3_rate_with_regular_cleaning": 0.0519
}
```
