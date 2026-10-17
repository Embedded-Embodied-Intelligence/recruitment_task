# Prompt Design: `task/prompt.md`

Principle: **difficulty must come from the data, not from an ambiguous prompt.** Every question has one correct answer under its stated definition. The prompt never names a trap, and `tests/test_prompt.py` checks that no trap answer leaks into the text.

## Structure

| Part | Purpose |
|---|---|
| Role + goal | Business framing: what drives the defect rate, what to change |
| Data | Two files, the join key, the time span, the target definition |
| How to work | Execute Python (task requirement), inspect before analysing, check quality |
| Questions A / B / C | Map 1:1 onto the three EDA steps of the task definition |
| Answer format | Short justification, then exactly one JSON object with fixed keys and types |

The prompt is identical for every dataset variant, so ablations change only the data. This is why B2 allows an empty list and B3 allows `null`.

## Hint audit: what each question defines and what it leaves to the analyst

| Q | Defined in the prompt (removes ambiguity) | Left to discover (the trap) |
|---|---|---|
| A1 | a batch is identified by `batch_id`; count *unique* batches | that rows are repeated |
| A2 | "missing **or not a valid measurement**" | that `-1` is a sentinel |
| A3 | exact formula: total defective / total produced over unique batches | not to average batch rates |
| A4 | unit (°C) and "valid readings" | L3 logs in °F, `0` = sensor failure |
| B1 | closed candidate list; operational definition of *direct effect* | U-shape (r ≈ 0), confounding by line and mold temperature, variance misspecification |
| B2 | "determined by the outcome"; excludes `defective_units` | which columns are post-QC |
| B3 | "persistent, abrupt", "not explained by process variables", first production date | seasonal drift vs real level shift; which line |
| C1 | "held equal": line, shift and process conditions | Simpson's paradox; dirty join key |
| C2 | "within the observed range", "all other conditions equal" | need for a non-linear term |

## Deliberate wording choices

- **"Missing or not a valid measurement" (A2).** Without "valid", counting only `NaN` would be a defensible reading, so a model could be penalised for an ambiguity rather than a mistake. The phrase sets the definition, but the model still has to find the sentinel.
- **"Check data quality before you rely on any number."** Any analyst brief would say this. It levels the field (no model can claim it was not asked to clean), and it is a calibration knob for Stage 6: a variant without this line measures how much models clean *unprompted*.
- **No example values in the format block.** Placeholders (`<integer>`) instead of numbers, so the format cannot anchor an answer.
- **Fixed column names in B1 and B2.** The answer is a set of identifiers, so it can be scored by F1 without fuzzy matching. Unknown names count as false positives instead of voiding the question (`edabench/answer.py`).
- **Justification before JSON.** Not scored, but it makes failure analysis possible (Stage 7) and does not change the scorer's input.
- **Canary in an HTML comment.** It stays in the source file and is stripped by `edabench.prompt.render_prompt`, so it is not sent to the model.

## Answer parsing (`edabench/answer.py`)

- Takes the **last** ```json block, so a model that revises its answer is scored on the final one. If there is no fenced block, it takes the last JSON object that contains answer keys.
- Validates each field separately: a malformed field scores 0 for that question only.
- Normalizes harmless variations: `3000.0` becomes `3000`, line ids are upper-cased, list duplicates and whitespace are removed.
