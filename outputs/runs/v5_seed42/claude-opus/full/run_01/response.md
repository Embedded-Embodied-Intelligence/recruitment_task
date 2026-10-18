I ran the analysis in Python on the cleaned data. A few calls depend on judgement: the size of the L1 sensor offset, an apparent gap in L4's cleaning log, and the exact humidity optimum. I flag each one where it comes up.

**Data cleaning:**
- **Duplicates:** I dropped 60 rows that were exact copies.
- **Batch IDs:** these repeat across lines, because each line's terminal numbers its own batches. I treated a batch as unique by line plus `batch_id`.
- **Dates:** each line uses its own format. L1 is MM/DD/YYYY, L4 is DD/MM/YYYY, and L2 and L3 use ISO dates.
- **Text fields:** I normalised the different spellings of `shift` and `supplier_code`.
- **Mold temperature:** a reading of 0.0 is not valid. L3 records in °F, so I converted it.
- **L1 temperature sensor:** the new sensor fitted on 2025-04-14 reads about 8 °C too high. Two independent estimates agree on this: comparing L1 with the other lines gives about 8, and the defect model fits best at 8.
- **Humidity:** blank values and −1 are not valid. L2's sensor was also stuck at 50.2 from 2025-03-03 to 04-13.

**A – Describe the data**
- **A1:** There are 3,060 rows. Removing 60 exact duplicates leaves 3,000 batches, identified by line plus `batch_id`.
- **A2:** 226 batches have a blank or −1 humidity reading. Another 123 come from L2's stuck sensor, giving 349 in total.
- **A3:** Over the 3,000 batches, total defective units divided by total units produced is 0.0550.
- **A4:** After converting L3 from °F, removing the 0.0 readings and taking 8 °C off L1's readings from 2025-04-14, the median is 211.5 °C. With a 6.5 °C correction it would be 211.8 °C.

**B – Identify salient features**
- **B1:** The direct drivers are `mold_temp`, `humidity_pct`, `cycle_time_s` and `shift`. I tested this with a binomial model of defects that also controls for supplier, line and days since the last cleaning.
  - Higher mold temperature raises defects.
  - Humidity matters differently by supplier: Alpha resin is not pre-dried, and its defects rise sharply at high humidity.
  - Longer cycle times relative to the recipe lower defects.
  - Night shift is about 16% worse.
  - `machine_age_years` has no effect within any line; it only stands in for L4 having the old presses.
  - `ambient_temp_c` acts only through mold temperature, and `operator_id` adds nothing once over-dispersion is accounted for.
- **B2:** `rework_cost_eur` is about €4.2 per defective unit, so it is computed from the defect count. `qc_inspection_min` also rises with the number of defects found.
- **B3:** Yes: L2 from 2025-06-16. Model residuals jump by about 70% from that day, and both rework cost per defect and inspection time stay normal, so the extra defects are real.
  - L3 also changes, from 2025-07-21, but its recorded defects fall rather than rise. Inspection time drops from about 22 to 13 minutes and rework cost per recorded defect doubles, so that change is in how defects are recorded, not in what the line produces.

**C – Interpret salient features**
- **C1:** Gamma would give the lowest overall rate, about 0.052, compared with Beta at about 0.056 and Alpha at about 0.066. This simulates each supplier with its grade's recipe, keeping humidity, temperature and everything else as observed.
- **C2:** The expected defect rate for Alpha is lowest at about 29% humidity. Different model shapes put the minimum between 26% and 30%, and the curve is fairly flat between 25% and 45%.
- **C3:** I estimate 0.0518. Defects rise by about 2% for each day since the last cleaning, so I re-scored each batch's recorded defects with days since cleaning capped by a 14-day cycle.
  - L4 has no logged cleanings from February to April, yet its defects show no build-up over that period. That suggests the log is incomplete there, so I applied no gain to those batches. Taking the log at face value instead gives 0.0512.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 349,
  "A3_overall_defect_rate": 0.0550,
  "A4_median_mold_temp_c": 211.5,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Gamma",
  "C2_optimal_humidity_pct": 29,
  "C3_rate_with_regular_cleaning": 0.0518
}
```
