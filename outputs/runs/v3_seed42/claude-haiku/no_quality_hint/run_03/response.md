## Summary

I cleaned the data, fitted a binomial model of defective units with date-clustered checks, and answered each question from that. The main data problems I corrected were:

- **Duplicates:** 60 exact duplicate rows, so 3000 unique batches.
- **Shift and supplier labels:** inconsistent codes (`D`, `N`, `night`, ` Sp-01`) mapped to `Day`/`Night` and `SP-01`–`SP-03`.
- **Humidity:** `-1` and blank values treated as invalid.
- **Mold temperature:** `0.0` treated as missing. All L3 readings are in Fahrenheit and converted to °C.
- **L1 sensor:** the maintenance log says the sensor reads 8 °C high after its 2025-04-14 replacement, so I subtracted 8 °C from L1 readings from that date. An independent check agrees: the model's own offset for post-replacement L1 batches is −0.252 (CI −0.286 to −0.219), against −0.234 predicted from an 8 °C bias.

## Answers

**A1.** 3000 unique batches after removing 60 exact duplicate rows.

**A2.** 226 batches have a blank humidity or the `-1` sentinel.

**A3.** 102,831 defective units out of 1,720,295 produced gives 0.059775.

**A4.** The median of the 2951 valid, corrected mold temperatures is 210.90 °C.

**B1.** Mold temperature, humidity (through a supplier-specific curve), cycle time, and shift all keep significant effects with clustered errors. Ambient temperature and machine age drop out once day clustering is accounted for. Operator is the closest call: within-line operator differences are small, and the joint test is borderline (p ≈ 0.04 clustered, 0.065 permutation), so I excluded it.

**B2.** `rework_cost_eur` is almost a fixed €4.2 per defect (r = 0.99), and `qc_inspection_min` rises with the defect rate even after controls, so both are outcome-driven.

**B3.** L2 shows a jump of about +0.66 on the logit scale starting 2025-06-16, the likelihood-maximising date. The other lines show only gradual drift, with no abrupt step.

**C1.** With each supplier applied to all batches, Beta gives the lowest pooled rate (0.0537, against 0.0614 for Alpha and 0.0619 for Gamma). The ranking holds when missing covariates are imputed. Beta's observed rate is the highest, but that comes from its line mix.

**C2.** For Alpha, the fitted humidity curve is U-shaped with its minimum at 29.8%, which sits in the flattest part of a binned check. The quadratic shape is an assumption, so this is the least certain answer.

**C3.** With a forced clean every 14 days, the expected overall rate is 0.0560, down from 0.0598. This is the observed baseline plus the model-estimated change over all batches, with missing covariates imputed by line or supplier median. It uses one mold per line, calendar days, and the linear days-since effect from the fit.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 226,
  "A3_overall_defect_rate": 0.059775,
  "A4_median_mold_temp_c": 210.9,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s", "shift"],
  "B2_leakage_columns": ["rework_cost_eur", "qc_inspection_min"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-16"},
  "C1_best_supplier": "Beta",
  "C2_optimal_humidity_pct": 29.8,
  "C3_rate_with_regular_cleaning": 0.0560
}
```
