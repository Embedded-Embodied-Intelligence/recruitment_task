# Measure Definition

**Deliverable 4.** The quality of a model's answer is a number in **[0, 1]**: 0 for a bad answer, 1 for the correct answer, and a value in between for a partially correct one. Implementation: `edabench/scorer.py`. Tests: `tests/test_scorer.py`.

```bash
python -m edabench.scorer <response file> --truth eval/ground_truth.json
```

## 1. Overall score

The answer has ten fields, one per question (datasets v3 to v5). Each question *q* gets a score *s_q* ∈ [0, 1] from a metric matched to its answer type. The total is a weighted mean:

```
score = Σ_q  w_q · s_q          Σ_q w_q = 1
```

| Section (EDA step) | Questions | Weight |
|---|---|---|
| Describe the data | A1, A2, A3, A4 | 0.07 each, 0.28 total |
| Identify salient features | B1 0.14, B2 0.10, B3 0.10 | 0.34 |
| Interpret salient features | C1 0.12, C2 0.13, C3 0.13 | 0.38 |

The weights put more value on **finding and interpreting** effects (72 %) than on describing the data (28 %). Describing is a prerequisite: each A-question is cheap on its own, but the cleaning it requires feeds every later answer. Interpretation weighs most because it answers management's question ("what should we change?"). The report also gives each section's score separately.

The weights are stored in the answer key (`weights`), so each dataset version is scored with the weights it was published with. A v1 or v2 key has no `weights` field and is scored with the nine-question weights of that time (A 0.075 each, B1 0.15, B2 and B3 0.125, C1 and C2 0.15).

**Failure isolation.** A missing or malformed field scores 0 for its own question only (`format_ok` is then `false`). A reply with no JSON answer at all scores 0.

## 2. Choosing a metric: the list example from the task

The task asks for a reasonable score when the correct answer is `[1, 3, 6, 11]` and the model returns `[1, 3, 7, 15]`. The right metric depends on **what the numbers mean**:

| If the elements are... | Suitable metric | Score |
|---|---|---|
| labels in a ranking (e.g. row indices of the top 4) | positional accuracy | 2/4 = **0.50** |
| an unordered set of labels | Jaccard 2/6 = 0.33, or F1 = **0.50** | 0.33 / 0.50 |
| quantities (e.g. counts, measurements) | mean relative closeness, `max(0, 1 - |a - t| / |t|)` per position | **0.87** |

If the elements are row indices, row 7 is *not* "almost" row 6: it is a different object, so a numeric metric would inflate the score to 0.87. If they are quantities, 7 instead of 6 is a small error, and a set metric would deflate the score to 0.33. **Labels call for set or ranking metrics, quantities call for distance-based metrics, and categories call for exact match.** All three variants are implemented and tested (`test_pdf_example_depends_on_answer_semantics`).

## 3. Metrics per answer type

### Numbers (A1-A4, C2): linear decay to the naive answer

```
s = max(0, 1 - |a - t| / scale)
```

A fixed relative tolerance would not work here. In A1 the trap (not removing duplicates) gives 3,060 instead of 3,000, a 2 % error. A 10 % tolerance would award 0.8 to a model that fell for the trap. So **the zero point is set at the naive trap answer**: `scale = |naive - t|`, as computed by the generator from the same data. Falling for the trap scores 0, a small numerical deviation earns almost full credit, and the score drops linearly in between. When several wrong approaches exist, the zero point is the **best** of them (A4: units fixed, drift not fixed), so every worse approach scores 0 too. A floor keeps the scale positive when a trap is switched off (ablation variants).

The values of the final key (v5, `eval/ground_truth.json`):

| Q | Truth | Naive trap answer | Scale | Trap |
|---|---|---|---|---|
| A1 | 3000 | 2963 | 37 | batch numbers deduplicated across lines (T18); keeping the duplicate exports gives 3,060, further from the truth |
| A2 | 349 | 226 | 123 | frozen logger readings counted as valid (T19); blanks and `-1` already treated as missing |
| A3 | 0.055032 | 0.059387 | 0.004355 | mean of batch rates instead of the pooled rate |
| A4 | 211.5 | 212.8 | 1.3 | L1 sensor drift not corrected (°F and zeros already fixed) |
| C2 | 30.0 | 36.72 | 6.72 | one humidity curve for all suppliers |
| C3 | 0.051864 | 0.050447 | 0.001417 | "summer as good as the rest of the year": the rate outside July-August |

### Sets (B1 drivers, B2 leakage): F1

```
F1 = 2·|A ∩ T| / (|A| + |T|)        F1(∅, ∅) = 1
```

F1 penalizes both a false driver (for example `machine_age_years`, the confounder) and a missed one (for example `humidity_pct`, invisible to correlation), with each mistake costing about as much. Accuracy over the 7 candidates was rejected because it gives credit for correctly *not* listing variables nobody would list. Jaccard was rejected because it punishes a single error harder than F1 does, which compresses partial credit. Names outside the candidate list count as false positives.

### Category (C1 supplier): exact match

There are three suppliers, and the question has one correct answer. Partial credit for "second best" would reward the naive answer that Simpson's paradox produces.

### Counterfactuals (C1, C3): truth from the DGP

C1 and C3 ask what *would* have happened. The key computes this from the data generating process itself: every batch keeps its own conditions and its random batch effect, and only the supplier (C1) or the days since cleaning (C3) change. From v4, a switched batch also takes the cycle time of its new grade's recipe plus its own operator adjustment (T14), and the expected defects are the *recorded* ones (T17), as A3 defines the rate. The answer is therefore exact, not an estimate by our own model. C3 is reported as a rate: the observed A3 rate times the ratio of expected defects with and without the extra cleanings. The reference solution estimates the same ratio from a fitted model and lands within 0.2 of the zero-point scale on every tested seed.

### Regime change (B3): gated date distance

```
s = [line correct] · max(0, 1 - |days off| / 30)          null vs null = 1
```

The line is a gate: a correct date on the wrong line is a wrong finding. Within the right line, being a week off still earns 0.77, because detecting the shift matters more than pinpointing the exact day.

From v4 the key also stores a **decoy** for B3: the L3 QC change (T17), where recorded defects fall but production does not change. An answer on the decoy's line counts as a trap hit in the report (`trap_B3`), and scores 0 like any wrong line.

## 4. Properties guaranteed by tests

| Property | Test |
|---|---|
| Correct answer → 1.0, empty or no answer → 0.0 | `test_correct_answer_scores_one`, `test_no_answer_scores_zero` |
| Every trap answer scores 0 on its question | `test_trap_answers_score_zero_on_their_questions` |
| A partial answer scores strictly between 0 and 1 | `test_partial_answer_is_strictly_between` |
| Expert reference solution ≈ 1 (0.984 on v5, 0.989 on v4) | `test_reference_solution_scores_near_one` |
| Older keys keep their own weights (pilot 01 still scores 0.995 on v2) | `test_older_keys_keep_their_own_weights` |
| Bounded, monotone in the error, symmetric | `test_number_score_bounded_monotone_symmetric` |
| Avoiding one more trap never lowers the score | `test_more_traps_avoided_never_scores_lower` |
| One malformed field costs exactly its weight | `test_one_bad_field_costs_one_question` |

## 5. Diagnostics (not part of the score)

For each question the report gives `trap_hit`: whether the answer lies closer to the naive trap answer than to the truth. It tells *which* trap a model fell for and feeds the failure analysis across models (Stage 7).

## 6. Why not LLM-as-a-Judge

Every answer is a number, a set of identifiers, a category or a date, so deterministic metrics are possible. They are free, reproducible and unbiased, and they cannot be persuaded by a confident explanation. The models' short justifications are collected for error analysis, but they are never scored.
