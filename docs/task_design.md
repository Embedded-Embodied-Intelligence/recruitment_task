# Task Design: Hidden Drivers of Defects on a Molding Line

> **Contains the answer key. Never shown to the model under test.** The model only receives `task/prompt.md` and the files in `data/`.

Status: Stage 1 design, validated with a throwaway prototype (see "Feasibility check"). Parameters may be tuned in Stage 6 (difficulty calibration).

## 1. Scenario

A plastics injection-molding plant runs four production lines (`L1`-`L4`) between 2025-01-06 and 2025-09-30. Each row is one **production batch**. Quality control counts defective parts per batch. Management asks: *what drives the defect rate, and what should we change?*

**Target (Y):** batch defect rate = `defective_units / units_produced`.

## 2. Files and schema

`data/batches.csv` (~3,060 rows including duplicates, < 400 KB)

| Column | Type | Notes |
|---|---|---|
| `batch_id` | str | `B-00001` ... |
| `production_date` | date | ISO `YYYY-MM-DD` |
| `line` | str | `L1`-`L4` |
| `shift` | str | Day / Night, with **inconsistent labels** |
| `operator_id` | str | 24 operators, each tied to one line |
| `supplier_code` | str | Resin supplier, join key to `suppliers.csv`, with **inconsistent case and whitespace** |
| `machine_age_years` | float | Age of the press |
| `ambient_temp_c` | float | Hall temperature, seasonal |
| `mold_temp` | float | Mold temperature. **Line L3 logs in °F**, others in °C. `0` = sensor failure |
| `humidity_pct` | float | Hall humidity. Missing as empty **or `-1` sentinel** |
| `cycle_time_s` | float | Injection cycle time |
| `units_produced` | int | Batch size |
| `defective_units` | int | Defective parts found by QC |
| `qc_inspection_min` | float | Time QC spent on the batch (**leakage**) |
| `rework_cost_eur` | float | Cost of reworking defective parts (**leakage**) |

`data/suppliers.csv` (3 rows): `supplier_code`, `supplier_name` (Alpha, Beta, Gamma), `resin_grade`, `country`.

## 3. Data generating process (DGP)

Per batch *i*:

```
defective_units_i ~ Binomial(units_produced_i, p_i)

logit(p_i) = -3.6
           + b_line[line_i]                    L1 0.0 | L2 0.1 | L3 0.2 | L4 0.9
           + b_supplier[supplier_i]            Alpha 0.0 | Beta -0.25 | Gamma -0.10
           + 0.03   * (mold_temp_c_i - 210)    hotter mold -> more defects
           + 0.0012 * (humidity_pct_i - 45)^2  U-shape, optimum at 45 %
           - 0.04   * (cycle_time_s_i - 30)    rushed cycles -> more defects
           + 0.15   * [shift_i = Night]
           + 0.60   * [line_i = L2 and date_i >= 2025-06-16]   mold wear on L2
           + u_i,   u_i ~ N(0, 0.25)           batch-level overdispersion
```

Covariates:

- `supplier`: allocation depends on line. **Beta goes ~75 % to L4** (the oldest, worst line), and only 10-15 % to L1-L3.
- `machine_age_years`: ~16 y on L4, ~5 y elsewhere. **No direct effect.**
- `ambient_temp_c`: seasonal sine. It drives the mold controller (`mold_temp_c = 210 + 0.8·(ambient - 21) + noise`) but has **no direct effect**.
- `humidity_pct ~ U(15, 75)`, symmetric around the optimum, so Pearson r ≈ 0.
- `operator_id`: tied to a line, **no direct effect**.
- `units_produced`: smaller batches on L4 (lognormal around 250 vs 600), so pooled and mean-of-rates differ.
- Leakage: `rework_cost_eur ≈ 4.2 · defective_units · noise`, `qc_inspection_min ≈ 20 + 0.08 · defective_units + noise`. Both are **computed after QC from the outcome**.

## 4. Planted traps

| ID | Trap | Injection | Naive behavior | Affects |
|---|---|---|---|---|
| T1 | Duplicates | ~2 % rows exported twice (same `batch_id`, identical values) | counts 3,060 batches | A1, A3 |
| T2 | Hidden missing values | `humidity_pct`: ~2 % empty + ~5 % `-1`; `mold_temp`: ~1.5 % `0` | `isna()` misses sentinels | A2, A4, C2 |
| T3 | Mixed units | L3 `mold_temp` in °F | median and temp effect distorted | A4, B1 |
| T4 | Inconsistent labels | `shift`: Day/day/D/DAY, Night/night/N/ NIGHT; `supplier_code` case/space | categories split, join fails | B1, C1 |
| T5 | Aggregation | defect rate varies with batch size via line | mean of batch rates instead of pooled rate | A3 |
| T6 | Non-linear effect | U-shaped humidity, r ≈ 0 | humidity dismissed as irrelevant | B1, C2 |
| T7 | Confounding | age, operator, ambient correlate with Y through line or mold temp | spurious drivers reported | B1 |
| T8 | Leakage | `rework_cost_eur`, `qc_inspection_min` | reported as top predictors | B2 |
| T9 | Simpson's paradox | Beta worst overall, best within every line | wrong supplier recommended | C1 |
| T10 | Regime change | L2 defect level jumps on 2025-06-16 | missed, averaged away | B3 |

Every trap is detectable by a careful analyst with pandas, and each one maps to at least one scored question.

## 5. Questions, answer key, metrics

The model returns one JSON object. The metric for each question matches the type of its answer (see `docs/measure.md`, Stage 5).

**Zero-point principle:** for numeric questions the score decays linearly from 1 at the true value to 0 at the distance of the *naive trap answer*: `s = max(0, 1 - |a - t| / d)`, where `d = |naive - t|`. Falling for the trap scores 0, while a small numerical difference still earns most of the credit.

| ID | EDA step | Question (short form) | Answer type | Ground truth source | Metric | Weight |
|---|---|---|---|---|---|---|
| A1 | Describe | Number of unique batches | int | generator (pre-duplication count) | zero-point linear, d = #duplicates | 0.075 |
| A2 | Describe | Number of batches with missing humidity (any encoding) | int | generator | zero-point linear, d = #sentinels | 0.075 |
| A3 | Describe | Overall defect rate = all defective / all produced, after de-duplication | float | generator | zero-point linear, d = \|mean-of-rates - pooled\| | 0.075 |
| A4 | Describe | Median mold temperature in °C over valid readings | float | generator | zero-point linear, d = \|naive median - true\| | 0.075 |
| B1 | Salient | Which of {mold temp, humidity, cycle time, machine age, ambient temp, operator, shift} have a **direct** effect on defect rate | set | DGP: {mold_temp, humidity_pct, cycle_time_s, shift} | F1 | 0.15 |
| B2 | Salient | Which columns must not be used as predictors because they are determined by the outcome | set | DGP: {rework_cost_eur, qc_inspection_min} | F1 | 0.125 |
| B3 | Salient | Date from which one line's defect level shifted persistently, and which line | date + line | DGP: L2, 2025-06-16 | line exact (gate) × `max(0, 1 - |Δdays| / 30)` | 0.125 |
| C1 | Interpret | Supplier with the lowest defect rate after accounting for line, shift and process parameters | category | DGP: Beta | exact | 0.15 |
| C2 | Interpret | Humidity level (%) at which the expected defect rate is lowest | float | DGP: 45 | `max(0, 1 - |a - 45| / 15)` | 0.15 |

Section weights: Describe 0.30, Salient 0.40, Interpret 0.30. A missing or unparseable field scores 0 for that question only.

## 6. Feasibility check (prototype, seed 42, clean data before trap injection)

| Check | Result |
|---|---|
| Simpson reversal | Beta overall 5.7 % (worst); within every line Beta is lowest (e.g. L4: 7.9 % vs Alpha 9.7 %) |
| Humidity Pearson r | 0.016 (U-shape invisible to linear correlation); binned rates clearly U-shaped, minimum at 45-50 % |
| Confounders | naive r: age 0.34, ambient 0.26. Multiple regression t: age -0.26, ambient 1.19 (not significant) |
| True drivers | regression t: mold 27, humidity² 43, cycle -22, night 8.5, supplier Beta -12 |
| Regime change | L2 weekly defect rate 4-5 % before 2025-06-16, 7-9 % after |
| Pooled vs mean of rates | 0.0558 vs 0.0595 |
| Median mold temp | ~209.9 °C clean vs ~212.2 naive (°F rows and zeros included) |

## 7. Difficulty hypotheses (to be tested in Stage 6)

- Likely solved: A1, A2 (if the model inspects values), B2 (leakage is fairly visible).
- Likely partial: A3, A4, B1 (models tend to include machine age or ambient temperature), B3 (date off by days).
- Likely failed: C1 (Simpson), C2 (if humidity was dismissed).
- Expected total: 0.4-0.7. If a model scores 1.0, add difficulty (for example, a second regime change or an interaction effect). If it scores ~0, check the prompt for ambiguity before blaming the model.

## 8. Contamination protection

Data are synthetic and seeded, and every file carries a canary GUID. A fresh variant (new seed, permuted parameters) can be generated at any time.
