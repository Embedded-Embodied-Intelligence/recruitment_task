# Prompt Design: `task/prompt.md`

Principle: **difficulty must come from the data, not from an ambiguous prompt.** Every question has one correct answer under its stated definition. The prompt never names a trap, and `tests/test_prompt.py` checks that no trap answer leaks into the text.

## Structure

| Part | Purpose |
|---|---|
| Role + goal | Business framing: what drives the defect rate, what to change |
| Data | Three files, the join key, the time span, the target definition, when cleanings happen |
| How to work | Execute Python (task requirement), inspect before analysing, check quality |
| Questions A / B / C | Map 1:1 onto the three EDA steps of the task definition |
| Answer format | Short justification, then exactly one JSON object with fixed keys and types |

The prompt is identical for every dataset variant, so ablations change only the data. This is why B2 allows an empty list and B3 allows `null`.

## Hint audit: what each question defines and what it leaves to the analyst

| Q | Defined in the prompt (removes ambiguity) | Left to discover (the trap) |
|---|---|---|
| A1 | `batch_id` is a number from the line's MES terminal (v5); count *unique* batches | that rows are repeated, and that a number can occur on two lines (T18) |
| A2 | "missing **or not a valid measurement**" | that `-1` is a sentinel |
| A3 | exact formula: total defective / total produced over unique batches | not to average batch rates |
| A4 | unit (°C), "**actual** temperature", "valid readings" | L3 logs in °F, `0` = sensor failure, L1 sensor reads 8 °C high from its replacement (v4: measured, not stated), L3's own step is real (T16) |
| B1 | closed candidate list; operational definition of *direct effect* | U-shape (r ≈ 0), confounding by line and mold temperature, variance misspecification |
| B2 | "determined by the outcome"; excludes `defective_units` | which columns are post-QC |
| B3 | "persistent, abrupt", "not explained by process variables", "in the share of defective parts it actually produces", first production date | seasonal drift vs real level shift; which line; v4: a fall in *recorded* defects on L3 is not one (T17); dates need a format per line (T15) |
| C1 | a plant-wide switch to one supplier, "processed with the standard recipe of its grade", everything else as it was | Simpson's paradox; dirty join key; with T11 the answer needs a prediction, not a coefficient; v4: the recipe moves the cycle time (T14) |
| C2 | Alpha batches only, "within the observed range", "all other conditions equal" | need for a non-linear term; Alpha's curve differs from the pooled one (clue: `pre_dried`) |
| C3 | the counterfactual schedule (extra cleaning after 14 days), rate as in A3 from the recorded defects (v5 wording) | build days since cleaning per line from another file (backward as-of join); separate the cleaning effect from season and the L2 regime |

## v3 wording (after pilot 01)

- **"actual" in A4.** A miscalibrated reading is not invalid, it is wrong by a known amount. "Actual" makes the correction part of the question without naming the sensor. Without it, a model could defend reporting the logged values.
- **"From next quarter the plant will use only Alpha resin" in C2.** A business reason to ask about one supplier. It does not say the curve differs by supplier; the model has to check that.
- **"Molds are supposed to be cleaned at least every 14 days" in C3.** States the plan, not the gaps. The model has to find in the log that the plan was missed in summer.
- **"Cleanings are done before the first shift" in the data section.** Without it, "days since the last cleaning" for a batch produced on a cleaning day would be ambiguous (0 or the previous interval), and the C3 answer would depend on a guess.

## v4 wording (after the harness runs)

- **"the standard process recipe of each resin grade" in the `suppliers.csv` description and "processed with the standard recipe of its grade" in C1.** Without it the counterfactual is ambiguous: nobody could say how the process would change with the resin. The prompt gives the fact but not its consequence; the model has to see that the recipe sets the cycle time, and that the cycle time is a driver.
- **"actually produces" in B3.** Defines the question as a change in production, so a change in what QC records is not a valid answer. Without it, reporting the L3 QC change would be defensible.
- **No mention of dates, sensors or QC methods.** These clues stay in the data only.

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
