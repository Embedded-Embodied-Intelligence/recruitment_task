# Measure Definition

**Deliverable 4.** The quality of a model's answer is a number in **[0, 1]**: 0 for a bad answer, 1 for the correct answer, and a value in between for a partially correct one. Implementation: `edabench/scorer.py`. Tests: `tests/test_scorer.py`.

```bash
python -m edabench.scorer <response file> --truth eval/ground_truth.json
```

## 1. Overall score

The answer has nine fields, one per question. Each question *q* gets a score *s_q* ∈ [0, 1] from a metric matched to its answer type. The total is a weighted mean:

```
score = Σ_q  w_q · s_q          Σ_q w_q = 1
```

| Section (EDA step) | Questions | Weight |
|---|---|---|
| Describe the data | A1, A2, A3, A4 | 0.075 each, 0.30 total |
| Identify salient features | B1 0.15, B2 0.125, B3 0.125 | 0.40 |
| Interpret salient features | C1, C2 | 0.15 each, 0.30 total |

The weights put more value on **finding and interpreting** effects (70 %) than on describing the data (30 %). Describing is a prerequisite: each A-question is cheap on its own, but the cleaning it requires feeds every later answer. The report also gives each section's score separately.

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

A fixed relative tolerance would not work here. In A1 the trap (not removing duplicates) gives 3,060 instead of 3,000, a 2 % error. A 10 % tolerance would award 0.8 to a model that fell for the trap. So **the zero point is set at the naive trap answer**: `scale = |naive - t|`, as computed by the generator from the same data. Falling for the trap scores 0, a small numerical deviation earns almost full credit, and the score drops linearly in between. A floor keeps the scale positive when a trap is switched off (ablation variants).

| Q | Truth | Naive trap answer | Scale | Trap |
|---|---|---|---|---|
| A1 | 3000 | 3060 | 60 | duplicates kept |
| A2 | 200 | 43 | 157 | `-1` sentinel not treated as missing |
| A3 | 0.047621 | 0.050288 | 0.002667 | mean of batch rates instead of the pooled rate |
| A4 | 211.0 | 213.7 | 2.7 | °F readings on L3 and zeros kept |
| C2 | 36.62 | 42.2 | 5.58 | midpoint of the observed humidity range (a guess without modelling) |

### Sets (B1 drivers, B2 leakage): F1

```
F1 = 2·|A ∩ T| / (|A| + |T|)        F1(∅, ∅) = 1
```

F1 penalizes both a false driver (for example `machine_age_years`, the confounder) and a missed one (for example `humidity_pct`, invisible to correlation), with each mistake costing about as much. Accuracy over the 7 candidates was rejected because it gives credit for correctly *not* listing variables nobody would list. Jaccard was rejected because it punishes a single error harder than F1 does, which compresses partial credit. Names outside the candidate list count as false positives.

### Category (C1 supplier): exact match

There are three suppliers, and the question has one correct answer. Partial credit for "second best" would reward the naive answer that Simpson's paradox produces.

### Regime change (B3): gated date distance

```
s = [line correct] · max(0, 1 - |days off| / 30)          null vs null = 1
```

The line is a gate: a correct date on the wrong line is a wrong finding. Within the right line, being a week off still earns 0.77, because detecting the shift matters more than pinpointing the exact day.

## 4. Properties guaranteed by tests

| Property | Test |
|---|---|
| Correct answer → 1.0, empty or no answer → 0.0 | `test_correct_answer_scores_one`, `test_no_answer_scores_zero` |
| Every trap answer scores 0 on its question | `test_trap_answers_score_zero_on_their_questions` |
| A partial answer scores strictly between 0 and 1 | `test_partial_answer_is_strictly_between` |
| Expert reference solution ≈ 1 (0.995) | `test_reference_solution_scores_near_one` |
| Bounded, monotone in the error, symmetric | `test_number_score_bounded_monotone_symmetric` |
| Avoiding one more trap never lowers the score | `test_more_traps_avoided_never_scores_lower` |
| One malformed field costs exactly its weight | `test_one_bad_field_costs_one_question` |

## 5. Diagnostics (not part of the score)

For each question the report gives `trap_hit`: whether the answer lies closer to the naive trap answer than to the truth. It tells *which* trap a model fell for and feeds the failure analysis across models (Stage 7).

## 6. Why not LLM-as-a-Judge

Every answer is a number, a set of identifiers, a category or a date, so deterministic metrics are possible. They are free, reproducible and unbiased, and they cannot be persuaded by a confident explanation. The models' short justifications are collected for error analysis, but they are never scored.
