I cleaned the data, fitted a binomial model of the batch defect rate on the cleaned process variables and used it for the counterfactual questions. The two answers that rest most on judgement are the B3 date and the long logging gap on line L4; both are explained below.

**Data quality issues I found and fixed**
- **Duplicates:** 60 rows are exact copies and were removed, leaving 3,000 batches. Some `batch_id` values repeat, but always on different lines or dates, so the MES terminals reuse numbers and those are separate batches.
- **Dates:** each line writes dates differently. L1 uses MM/DD/YYYY, L4 uses DD/MM/YYYY, and L2/L3 use ISO dates.
- **Text fields:** shift and supplier codes come in mixed spellings, capitals and spaces, so I normalised them.
- **Mold temperature:**
  - L3 records it in °F, which I converted to °C.
  - A reading of 0.0 is not a valid measurement.
  - The L1 sensor replaced on 2025-04-14 reads about 7.7 °C too high. Before the swap, L1 matched the other lines. After correcting for the 7.7 °C, the defect model needs no separate before/after term for L1.
- **Humidity:** −1 is a placeholder for "no reading". The L2 sensor was also stuck at 50.2 from 2025-03-03 to 2025-04-13.
- **L3 inspection:** from 2025-07-21, QC inspection time on L3 dropped from about 23 to 13 minutes. Recorded defects fell with it while the process variables stayed the same.
- **L4 maintenance log:** no mold cleaning is logged between 2025-02-01 and 2025-04-11 (69 days). The defect rate shows no build-up in that time, so I treated those cleanings as done but not recorded.

**Answers**
- **A1:** 3,000 unique batches after removing the 60 exact duplicates.
- **A2:** 349 batches have humidity that is empty, −1, or the stuck L2 value.
- **A3:** 0.0550 overall (total defective units ÷ total units produced, over unique batches).
- **A4:** 211.6 °C median, after converting L3 from °F, dropping 0.0 readings and taking the 7.7 °C bias off the new L1 sensor.
- **B1:** `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift` have direct effects.
  - Effects on the defect rate: hotter molds and night shifts raise it, longer cycles lower it, and humidity's effect depends on the resin.
  - Within each line, machine age, the operator and ambient temperature add nothing. Ambient temperature acts through mold temperature, and L4's higher rate stays flat across its machine ages (10–21 years).
- **B2:** `rework_cost_eur` (about €4.2 per defective unit) and `qc_inspection_min` (about 0.08 minutes more per defect found) both follow from the defect count.
- **B3:** On line L2, defects jump by roughly 1.9 times from about 2025-06-16 and stay high, which no process variable explains. The scan of possible start dates is nearly tied between 06-16 and 06-19, so the exact day is uncertain. The L3 drop in July is not a change in real production, only the shorter inspection.
- **C1:** Gamma would give the lowest rate (model estimate about 0.051, against 0.054 for Beta and 0.064 for Alpha). This assumes standard recipe cycle times and all other conditions as they were.
- **C2:** For Alpha resin, which is not pre-dried, the model's lowest point is about 29.7 % humidity, and grouping humidity in 4 % bins also puts the minimum at 26–30 %. The rate rises steeply above about 45 %.
- **C3:** About 0.0518. Each extra day since the last cleaning adds about 2 % to the odds of a defect. I reset the days-since-cleaning count every 14 days for 507 affected batches, but left out the L4 logging gap. Including it would give 0.0512.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 349,
  "A3_overall_defect_rate": 0.0550,
  "A4_median_mold_temp_c": 211.6,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["rework_cost_eur", "qc_inspection_min"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 30,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
