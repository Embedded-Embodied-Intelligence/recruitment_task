# Task Design: Hidden Drivers of Defects on a Molding Line

> **Contains the answer key. Never shown to the model under test.** The model only receives `task/prompt.md` and the files in `data/`.

Status: dataset **v5** (section 7e). Earlier status: dataset v3. The Stage 1 design (T1-T10) was validated with a throwaway prototype (see "Feasibility check"). After pilot 01 showed that a model with code execution avoids all ten (section 7c), v3 adds three traps that break answers to questions that do not name them (T11-T13).

## 1. Scenario

A plastics injection-molding plant runs four production lines (`L1`-`L4`) between 2025-01-06 and 2025-09-30. Each row is one **production batch**. Quality control counts defective parts per batch. Management asks: *what drives the defect rate, and what should we change?*

**Target (Y):** batch defect rate = `defective_units / units_produced`.

## 2. Files and schema

`data/batches.csv` (~3,060 rows including duplicates, < 400 KB)

| Column | Type | Notes |
|---|---|---|
| `batch_id` | str | random 5-digit numbers (`B-45889`), unique **within a line only**: 37 numbers occur on two lines (**T18**, v5) |
| `production_date` | str | Each line's export has its own format: ISO on L2 and L3, `MM/DD/YYYY` on L1, `DD/MM/YYYY` on L4 (**T15**) |
| `line` | str | `L1`-`L4` |
| `shift` | str | Day / Night, with **inconsistent labels** |
| `operator_id` | str | 24 operators, each tied to one line |
| `supplier_code` | str | Resin supplier, join key to `suppliers.csv`, with **inconsistent case and whitespace** |
| `machine_age_years` | float | Age of the press |
| `ambient_temp_c` | float | Hall temperature, seasonal |
| `mold_temp` | float | Mold temperature. **Line L3 logs in °F**, others in °C. `0` = sensor failure. **L1 reads 8 °C high from 2025-04-14** (T12), **L3 really runs 6 °C hotter from 2025-05-19** (T16) |
| `humidity_pct` | float | Hall humidity. Missing as empty **or `-1` sentinel**. **The L2 logger repeats 50.2 from 2025-03-03 to 2025-04-13** (frozen, **T19**, v5) |
| `cycle_time_s` | float | Injection cycle time: the recipe of the resin grade plus the operator's adjustment (**T14**) |
| `units_produced` | int | Batch size |
| `defective_units` | int | Defective parts found by QC. **From 2025-07-21 L3 QC finds only 45 % of them** (T17) |
| `qc_inspection_min` | float | Time QC spent on the batch (**leakage**) |
| `rework_cost_eur` | float | Cost of reworking defective parts (**leakage**) |

`data/suppliers.csv` (3 rows): `supplier_code`, `supplier_name` (Alpha, Beta, Gamma), `resin_grade`, `country`, `pre_dried` (Alpha: `no`, the **clue for T11**), `recipe_cycle_time_s` (PP-H350: 30 s, PP-H420 = Gamma: 36 s, the **fact behind T14**).

`data/maintenance.csv` (~76 rows): `date`, `line`, `event`, `note`. Mostly `mold_cleaning` events per line (the source of the **T13** driver), plus one `sensor_replacement` on L1 (2025-04-14) whose note only says that the sensor was replaced. **The L4 cleanings from 2025-02-10 to 2025-04-06 are missing** (done but not logged, **T20**, v5), so the log shows a 69-day gap. In v3 a `calibration_check` note stated the 8.0 °C offset; v4 removed it (T12 now has to be measured).

## 3. Data generating process (DGP)

Per batch *i*:

```
defective_units_i ~ Binomial(units_produced_i, p_i)

logit(p_i) = -3.6
           + b_line[line_i]                    L1 0.0 | L2 0.1 | L3 0.2 | L4 0.9
           + b_supplier[supplier_i]            Alpha 0.0 | Beta -0.25 | Gamma -0.10
           + 0.03   * (mold_temp_c_i - 210)    hotter mold -> more defects (L3 +6 degC from 2025-05-19, T16)
           + 0.0012 * (humidity_pct_i - h*_s)^2  U-shape, h* = 30.0 for Alpha (not pre-dried), 42.92 for Beta and Gamma
           - 0.04   * (cycle_time_s_i - 30)    rushed cycles -> more defects; cycle = recipe(grade) + N(0, 4), clipped 18-45
           + 0.15   * [shift_i = Night]
           + 0.60   * [line_i = L2 and date_i >= 2025-06-16]   mold wear on L2
           + 0.02   * days_since_cleaning_i    dirty molds; cleaned before the first shift
           + u_i,   u_i ~ N(0, 0.25)           batch-level overdispersion
```

Covariates:

- `supplier`: allocation depends on line. **Beta goes ~75 % to L4** (the oldest, worst line), and only 10-15 % to L1-L3.
- `machine_age_years`: ~16 y on L4, ~5 y elsewhere. **No direct effect.**
- `ambient_temp_c`: seasonal sine. It drives the mold controller (`mold_temp_c = 210 + 0.8·(ambient - 21) + noise`) but has **no direct effect**.
- `humidity_pct = 12 + 64 · Beta(1.5, 3)`: right-skewed (mostly dry hall). 36.62 is the point where cov(h, (h - h*)²) = 0. The supplier optima (30.0 and 42.92) average to 36.62 when weighted by the suppliers' shares (Alpha 48.75 %), so the pooled U-shape still has Pearson r ≈ 0. Alpha's optimum is neither the midpoint of the range (≈ 42), the mean (≈ 33) nor the pooled optimum (≈ 36.8).
- `days_since_cleaning`: from `maintenance.csv`. Cleanings come every 10-16 days, but every 26-35 days when the previous cleaning falls in July or August (holidays). Long gaps coincide with the hot season.
- Sensor drift: the published L1 `mold_temp` from 2025-04-14 on is the true value + 8.0 °C. The DGP uses the true value.
- `operator_id`: tied to a line, **no direct effect**.
- Cycle time (v4, T14): `cycle_time_s = recipe_cycle_time_s[grade] + N(0, 4)`, clipped to 18-45 s. Gamma's grade runs a 36 s recipe, so Gamma batches have longer cycles and, through the cycle, fewer defects. The supplier effect therefore has a direct part (Beta best) and a part mediated by the cycle (Gamma best in total).
- QC detection (v4, T17): the binomial draw above gives the **true** defects. From 2025-07-21 L3 QC records `Binomial(true, 0.45)` of them; `rework_cost_eur` is still computed from the true defects (rework still has to fix every bad part), and `qc_inspection_min` drops by 8 minutes. Every answer key is about **recorded** defects, as the questions define them.
- `units_produced`: smaller batches on L4 (lognormal around 250 vs 600), so pooled and mean-of-rates differ.
- Leakage: `rework_cost_eur ≈ 4.2 · true defects · noise`, `qc_inspection_min ≈ 20 + 0.08 · recorded defects - 8 · [L3 fast QC] + noise`. Both are **computed after QC from the outcome**.

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
| T11 | Interaction (v3) | humidity optimum 30 % for Alpha, 42.9 % for Beta and Gamma; clue `pre_dried` | one humidity curve for all suppliers (optimum ≈ 36.8) | C2, C1 |
| T12 | Silent sensor drift (v3, harder in v4) | L1 `mold_temp` +8 °C from 2025-04-14, plausible values; v4: the log only says the sensor was replaced, the offset must be measured (DiD against other lines) | readings taken at face value | A4 |
| T13 | Hidden driver in another file (v3) | defects rise 0.02 logit per day since cleaning; long gaps in July-August | log ignored: summer heat looks like the cause, cleaning effect overstated | B1, C3 |
| T14 | Mediator in the counterfactual (v4) | cycle time follows the recipe of the resin grade (`suppliers.csv`), and a longer cycle lowers defects | supplier switched with the cycle held fixed: Beta | C1 |
| T15 | One date format per line (v4) | L1 `MM/DD/YYYY`, L4 `DD/MM/YYYY`, L2 and L3 ISO; each line consistent | plain `to_datetime` fails; `format="mixed"` or `dayfirst=True` misreads days ≤ 12 | A4, B3, C3 (sensor date, regime date, cleaning join) |
| T16 | Real process change as a contrast (v4) | L3 mold really 6 °C hotter from 2025-05-19, defects rise with it, no log entry | every step "corrected" like a sensor | A4 |
| T17 | Detection change (v4) | L3 QC finds 45 % of the bad parts from 2025-07-21; rework per recorded defect doubles, QC minutes drop by 8 | the drop in recorded L3 defects reported as the regime change | B3 (and B1, C1-C3 through the model fit) |
| T18 | Batch numbers per line (v5) | each line's MES terminal draws its own 5-digit numbers; 37 numbers occur on two lines, with different dates and values | counts distinct `batch_id` (2,963) or de-duplicates on it, merging two batches | A1 (and A2-A4 slightly) |
| T19 | Frozen logger (v5) | L2 humidity repeats one reading (50.2) for six weeks; `-1` and empty readings still occur | the frozen readings counted as valid and used in the humidity fit | A2, C2 |
| T20 | Unlogged cleanings (v5) | ten weeks of L4 cleanings are not in the log (a 69-day gap, more than twice the longest summer gap); L4 defects stay flat over it | logged days taken at face value: the cleaning slope falls from 0.020 to about 0.009 per day | C3 |

Every trap is detectable by a careful analyst with pandas, and each one maps to at least one scored question. Since v3 a trap may also break an answer to a question that does not name it (A4 never mentions sensors, B1 never mentions maintenance). In v3 each such trap had a clue that could be read in the published files. **From v4 the clue has to be inferred from the data**: a step in a reading, a ratio that changes, a format that only one line uses. `tests/test_reference.py::test_v4_clues_are_recoverable_from_the_data` checks on 10 seeds that each one can be found. **v5 traps are quiet**: the naive code runs without an error and returns a plausible number, so nothing tells the model that it should look (section 7e).

## 5. Questions, answer key, metrics

The model returns one JSON object. The metric for each question matches the type of its answer (full definition: `docs/measure.md`).

**Zero-point principle:** for numeric questions the score decays linearly from 1 at the true value to 0 at the distance of the *naive trap answer*: `s = max(0, 1 - |a - t| / d)`, where `d = |naive - t|`. Falling for the trap scores 0, while a small numerical difference still earns most of the credit.

| ID | EDA step | Question (short form) | Answer type | Ground truth source | Metric | Weight |
|---|---|---|---|---|---|---|
| A1 | Describe | Number of unique batches | int | generator (pre-duplication count) | zero-point linear, d = #duplicates | 0.07 |
| A2 | Describe | Number of batches with missing humidity (any encoding) | int | generator | zero-point linear, d = #sentinels | 0.07 |
| A3 | Describe | Overall defect rate = all defective / all produced, after de-duplication | float | generator | zero-point linear, d = \|mean-of-rates - pooled\| | 0.07 |
| A4 | Describe | Median **actual** mold temperature in °C over valid readings | float | generator (°F converted, zeros dropped, L1 drift removed) | zero-point linear, d = \|median without the drift fix - true\| (1.0) | 0.07 |
| B1 | Salient | Which of {mold temp, humidity, cycle time, machine age, ambient temp, operator, shift} have a **direct** effect on defect rate | set | DGP: {mold_temp, humidity_pct, cycle_time_s, shift} | F1 | 0.14 |
| B2 | Salient | Which columns must not be used as predictors because they are determined by the outcome | set | DGP: {rework_cost_eur, qc_inspection_min} | F1 | 0.10 |
| B3 | Salient | Date from which one line's defect level shifted persistently, and which line | date + line | DGP: L2, 2025-06-16 | line exact (gate) × `max(0, 1 - |Δdays| / 30)` | 0.10 |
| C1 | Interpret | Supplier that would give the lowest overall defect rate if it delivered all the resin, everything else unchanged | category | DGP counterfactual: Beta | exact | 0.12 |
| C2 | Interpret | Humidity (%) at which the expected defect rate of **Alpha** batches is lowest | float | DGP: 30.0 | zero-point linear, d = \|pooled-curve optimum - truth\| (6.76) | 0.13 |
| C3 | Interpret | Expected overall rate if every mold had also been cleaned whenever 14 days had passed since its last cleaning | float | DGP counterfactual: 0.056071 (A3 = 0.059775) | zero-point linear, d = \|rate outside July-August - truth\| (0.0023) | 0.13 |

Section weights: Describe 0.28, Salient 0.34, Interpret 0.38. A missing or unparseable field scores 0 for that question only. For numeric questions with several wrong approaches, the zero point is the **best** wrong answer: in A4, a model that fixes the units but not the drift scores 0.

C1 changed in v3. With T11 the supplier ranking at fixed conditions depends on humidity (in a very humid hall Gamma beats Beta), so "held equal" would have two right answers. The plant-wide switch is a counterfactual with one answer, and it is the decision management actually faces. C1 and C3 truths are computed from the DGP itself: every batch keeps its own conditions and random effect, and only the supplier or the time since cleaning changes.

## 6. Feasibility check (prototype, seed 42, clean data before trap injection)

| Check | Result |
|---|---|
| Simpson reversal | Beta overall 5.7 % (worst); within every line Beta is lowest (e.g. L4: 7.9 % vs Alpha 9.7 %) |
| Humidity Pearson r | 0.016 in the prototype, -0.012 in the final data (U-shape invisible to linear correlation); binned rates clearly U-shaped |
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

## 7a. Reference solution findings (Stage 3)

`reference/reference_solution.ipynb` reaches every answer from the data alone and scores 0.995 against the key (the only loss is C2: 36.8 vs 36.62).

**Emergent trap (not planted): variance misspecification.** With batch-level overdispersion, a binomial GLM weighted by batch size treats large batches as far more informative than they are. Its standard errors become too small, and with seed 42 it flags `operator_id` as significant (p = 9e-4) although operators have no effect. An empirical-logit OLS with HC3 errors recovers exactly the true driver set on all 10 tested seeds (`tests/test_reference.py`) and on 20 seeds in an offline check. B1 therefore also rewards choosing a model whose noise assumptions fit the data.

## 7b. Calibration after pilot 00 (no code execution)

Pilot 00 (Sonnet 5.5 in an incognito chat, where code execution is unavailable) scored **0.65 without running any code**, by reading the CSV in context and guessing. Two answers were guessable from the surface of the data rather than from analysis, so both were removed:

| Leak | Why it leaked | Fix |
|---|---|---|
| A1 from ids | sequential `B-00001`…`B-03000`: the last id gives the count | random 6-digit ids from a child RNG (other draws unchanged) |
| C2 at the range midpoint | uniform humidity 15-75 put the optimum exactly at the midpoint, 45 | right-skewed humidity, optimum 36.62; the naive answer is now the range midpoint, which scores 0 |

The no-code run is kept as a **control condition** (`outputs/pilot_00_no_code_exec/`). It measures how much of the score can be reached by eyeballing, which a good EDA benchmark should keep low.

## 7c. Calibration after pilot 01 (code execution, v2)

Pilot 01 (Sonnet 5.5 with code execution) scored **0.995**, the same as the reference solution. It found every T1-T10 trap, and even avoided the variance-misspecification trap by testing operators nested within lines. Diagnosis: each of the ten traps is an item on a standard EDA checklist, and each question points at where to look. v3 therefore follows a new rule: **a trap breaks the answer to a question that does not name it, but always leaves a clue in the published files**. T11-T13 implement it. In a 10-seed prototype, each new trap's naive answer scored 0, the old traps kept working (Simpson reversal on 10/10 seeds, pooled humidity r ≈ 0), and the expert method recovered every truth.

Reference findings for v3 (`tests/test_reference.py`, 10 seeds; 20 in an offline check): the interaction model recovers Alpha's optimum within 1 point, the plant-wide switch always picks Beta, the C3 estimate stays within 0.2 of the zero-point scale, and the driver set stays exact. Without `days_since_cleaning`, ambient temperature turns significant (p < 0.05 on 18 of 20 seeds, p = 8e-5 on seed 42), which is the B1 effect of T13.

## 7d. Calibration after the harness runs on v3 (Stage 7)

23 runs of `claude -p` (Haiku 5.5 and Sonnet 5.5 5× in two prompt variants, Opus 5.5 3×) scored 0.911-0.996 with **no trap hit in any run** (`outputs/runs/v3_seed42/summary.md`). Every v3 clue was readable (the calibration note, `pre_dried`, the cleaning log), and the models read every file. The transcripts also showed what they never do: they parse dates with a plain `pd.to_datetime`, they compute the C1 counterfactual by switching the supplier with every other column held fixed, and they treat a step in a reading as either a sensor fault or a process change by default, not by evidence.

v4 builds on these observations. Two of its traps (T14, T17) were also proposed independently by other LLMs in a red-team prompt (`docs/red_team_prompt.md`): ChatGPT ("cycle time is a mediator", "apparent quality improvement caused by a QC detection change") and Perplexity ("QC inspection intensity", the leakage columns as evidence of how the outcome was recorded). Ideas that were not adopted, and why:

| Idea (source) | Why not in v4 |
|---|---|
| Unlogged scrap runs, selective logging, discarded warm-up (Gemini, ChatGPT, Grok) | the truth is not identifiable from the data, so the fair answer is "cannot be determined", which a deterministic key cannot score |
| Pseudoreplication by delivery lot (Gemini, ChatGPT) | changes p-values, not point answers; it would add noise to B1 and reward a significance convention, not reasoning |
| Sequence effects: resin changeover, defects attributed to the previous batch, startup after idle, cycle time adjusted after a bad batch (Gemini, ChatGPT, DeepSeek) | need production timestamps and batch order, which the schema does not have; a candidate for v5 |
| Censored or saturated readings, cumulative or rolling counters (Gemini, Grok, DeepSeek) | found by a histogram or a monotonicity check, so closer to a cleaning checklist than to reasoning about the process |
| Reused operator ids (Perplexity, Grok) | operators have no effect in the DGP, so no answer would change |
| Reactive maintenance (ChatGPT), shared chiller across lines (Gemini) | conflict with the scheduled cleanings of T13 or need a much larger DGP; the C3 answer would become ambiguous |
| Sampled numerator on one line (DeepSeek) | the same failure mode as T17 (a change in what is recorded); one such trap is enough |

## 7e. Calibration after the harness runs on v4: quiet traps (v5)

On v4 the models found almost every trap and lost points only where a detected problem had to be estimated (`outputs/runs/v4_seed42/summary.md`). Every v4 clue turned out to be loud: `to_datetime` raised an error, the prompt named the recipe, and the QC change moved two columns by several standard deviations. The weighted mean also hid how partial the answers were, because six of the ten questions were solved by every model.

v5 adds three traps whose naive analysis gives no signal at all, on the questions every model solved:

- **T18** breaks the habit of de-duplicating on the id column. The fair clue is in the prompt (the number is assigned by the line's MES terminal) and in the data (rows sharing a number differ in line, date and every value, while true double exports are exact copies).
- **T19** is found only by looking at the distribution of a reading per line (a run of 123 identical values, against at most 2 on the other lines). The question already counts readings that are "not a valid measurement".
- **T20** is found only by checking the logged intervals against the plan stated in the prompt. Unlike the unlogged scrap runs rejected in 7d, its truth is identifiable: L4's defects stay flat over the gap, and leaving those batches out of the fit recovers the cleaning effect (`tests/test_reference.py`, 10 seeds).

The C3 wording also gained "from the recorded `defective_units`", which removes the ambiguity two v4 runs fell into. The reference notebook scores 0.984 on v5.

## 8. Ablation semantics

Every trap has a switch (`configs/benchmark.yaml`, `--disable`, `--no-traps`). All random draws happen whatever the switches are ("common random numbers"), so a variant differs from the full task only in the switched-off trap.

v3 fixed a flaw in this claim. Defect counts used to come from `rng.binomial`, which consumes a varying number of random numbers depending on p, so every trap that changed p (for example regime change) also reshuffled the later draws: which readings go missing, which rows are duplicated. Defects now come from the inverse CDF of one uniform per batch, and `test_ablation_keeps_common_random_numbers` checks every switch. The new v3 draws (cleaning schedule, batch ids) come from child generators.

| Trap off | Effect on data | Effect on answer key |
|---|---|---|
| duplicates | no repeated rows | A1 naive = truth |
| hidden_missing | the same readings are missing, encoded as empty | A2 naive = truth |
| mixed_units | L3 in °C | A4 naive closer to truth |
| inconsistent_labels | canonical `Day`/`Night`, `SP-0x` | none |
| aggregation | same batch-size distribution on all lines | A3 naive ≈ truth |
| nonlinear_effect | humidity effect linear and decreasing | C2 truth = highest observed humidity |
| confounding | machine age and ambient temperature independent of line and mold | none |
| leakage | leakage columns not published | B2 truth = empty set |
| simpson_paradox | supplier allocation independent of line | C1 naive = truth |
| regime_change | no level shift | B3 truth = null |
| interaction | one humidity optimum (36.62) for every supplier | C2 truth = 36.62, C2 naive ≈ truth |
| sensor_drift | L1 sensor accurate; the log still lists the replacement | A4 naive = raw median (as in v2) |
| hidden_driver | cleanings have no effect (the log is still published) | C3 truth = A3 |
| mediator | every grade runs a 30 s recipe | C1 truth = the held-fixed answer (Beta) |
| date_formats | ISO dates on every line | none (only parsing changes) |
| real_process_change | L3 mold temperature unchanged | A4 truth moves with the L3 readings |
| detection_change | L3 QC finds every bad part | B3 has no decoy; recorded = true defects |
| id_collisions | 6-digit numbers unique across the plant (as in v4) | A1 naive = row count |
| frozen_sensor | the L2 logger keeps measuring | A2 naive = `isna()` count |
| unlogged_cleanings | every cleaning is logged | none (the naive slope is right) |

## 9. Contamination protection

Data are synthetic and seeded. The canary GUID is in `data/CANARY.txt` and `eval/ground_truth.json`, but not inside the CSVs, where a comment line would break `read_csv` and act as an unintended trap. A fresh variant (new seed, permuted parameters) can be generated at any time.
