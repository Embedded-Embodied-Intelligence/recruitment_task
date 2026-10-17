# Datasheet: EDA-Bench molding-plant dataset (v4)

Structured after *Datasheets for Datasets* (Gebru et al., 2021). Design details and the answer key are in `docs/task_design.md`, which is not given to the models.

## Motivation

- **Purpose.** To test whether an LLM with Python code execution can carry out an exploratory data analysis. The model has to describe the data, find the salient features and interpret them, and every answer is scored against an exact truth.
- **Why synthetic.** Real plant data come with no answer key, and nobody can say what a counterfactual ("if every batch had used supplier X") would really have been. A simulation gives an exact truth for every question, also for counterfactuals, and lets each trap be switched off on its own.
- **Created by** KamPieDev for a deepsense.ai recruitment task, October 2026.

## Composition

| File | Rows | What one row is |
|---|---|---|
| `data/batches.csv` | 3,060 (3,000 unique batches + duplicates) | one production batch: date, line, shift, operator, supplier, machine age, hall and mold temperature, humidity, cycle time, units produced, defective units, QC minutes, rework cost |
| `data/suppliers.csv` | 3 | a resin supplier: name, grade, country, pre-drying, standard cycle-time recipe of the grade |
| `data/maintenance.csv` | 75 | a maintenance event: mold cleanings per line and one sensor replacement |

- **Period:** 2025-01-06 to 2025-09-30, 4 production lines, 24 operators.
- **Target:** batch defect rate = `defective_units / units_produced`.
- **Deliberate data-quality issues (the traps).** The issues are deliberate, and each one maps to a scored question:
  - duplicated rows, missing values coded as `-1` or `0`, and °F on one line;
  - inconsistent labels and one date format per line;
  - a mold-temperature sensor that reads high after its replacement;
  - a change of QC inspection on one line.
  The full list is T1-T17 in `docs/task_design.md`.
- **No personal data.** Operator ids such as `OP-07` and supplier names are fictional.
- **Size.** About 260 KB in total, small enough for any code sandbox.

## Collection process (the data-generating process)

- **Generator.** Data come from `edabench/generate.py`, a seeded simulation. Defective units are binomial, and the logit combines:
  - line effects, supplier effects and mold temperature;
  - a U-shaped humidity effect that differs by supplier;
  - cycle time, which follows the grade's recipe;
  - night shift, a level shift on one line, days since the last mold cleaning, and batch-level noise.
- **Covariates without an effect.** Machine age, hall temperature and operator correlate with the target only through confounding.
- **Common random numbers.** Every random draw happens whatever the trap switches are. Turning one trap off therefore changes only what that trap touches, which `tests/test_generate.py` checks.

## Preprocessing and labels

- **The published files are raw by design.** The traps are what the task measures, so no cleaning is applied.
- **Answer key.** `eval/ground_truth.json` holds, for each question, the truth, the naive answer (the score's zero point) and the weights. Counterfactual truths are computed from the simulation itself, keeping each batch's own conditions and noise.

## Uses

- **Intended:** benchmarking LLM agents on EDA, studying the failure modes of automated analysis, and teaching data cleaning and causal pitfalls.
- **Not intended:** any conclusion about real injection molding. Effect sizes are chosen for detectability, not taken from the literature.
- **Known limitation.** After the QC trap was added, question C3 can be read as asking for the true rather than the recorded defect rate (`SUBMISSION.md`, "Known limitations").

## Distribution and maintenance

- **License:** MIT (see `LICENSE`).
- **Contamination.** A canary GUID is stored in `data/CANARY.txt` and in the answer key, and not inside the CSVs, where it would break parsing. If a model reproduces it, the benchmark leaked into its training data.
- **Fresh variants.** If the published instance is contaminated, `python -m edabench.generate --seed <n>` generates a new instance with the same structure and new numbers. Single traps can be switched off with `--disable <trap>`, and all of them with `--no-traps`.
- **Versions.** The version is stored in the key (`dataset_version`) and in every run's metadata. v1-v3 keys are archived with the pilots in `outputs/pilot_*`, and the scorer keeps each version's weights.
- **Reproducibility.** `make data` regenerates `data/` and the key byte for byte from `configs/benchmark.yaml` (seed 42).
