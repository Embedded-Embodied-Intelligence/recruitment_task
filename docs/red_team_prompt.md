You are helping design a benchmark task that tests how well an LLM with Python code execution performs exploratory data analysis (EDA). The model under test gets CSV files and questions, runs code, and answers in JSON. Answers are scored against a ground truth known exactly, because the data come from a synthetic data-generating process (a simulation written in code), not from real records.

Setting: a plastics injection-molding plant with 4 production lines, about 3,000 production batches over 9 months. The target is the batch defect rate (defective units / units produced). The files are:
- `batches.csv`: one row per batch, with date, line, shift, operator, resin supplier, machine age, ambient temperature, mold temperature, hall humidity, cycle time, units produced, defective units, QC inspection minutes and rework cost;
- `suppliers.csv`: supplier code, name, resin grade, country;
- `maintenance.csv`: a log of maintenance events by line and date.

The current version already contains these traps, and strong models (with pandas and statsmodels) avoid all of them: duplicate rows, sentinel missing values, mixed units (°F on one line), inconsistent category labels, pooled vs averaged rates, a U-shaped effect with zero linear correlation, confounders (machine age, ambient temperature, operator), target leakage (rework cost, QC minutes), Simpson's paradox across lines, a regime change on one line, a humidity × supplier interaction, a sensor offset stated in the maintenance log, and a hidden driver (days since mold cleaning) that must be built from the maintenance log.

Propose 8 new traps that a careful human analyst would catch but a capable LLM agent is likely to miss. For each trap give:
1. what is planted in the data-generating process (concretely, with numbers);
2. which kind of question it corrupts without the question naming it;
3. the naive answer a hurried analyst would give, and the correct answer;
4. the evidence in the data alone that lets a careful analyst detect it, with no note or comment that states it. The trap must be fair: detectable and unambiguous;
5. why an LLM agent in particular would likely miss it (e.g. a default library behaviour, a habit of controlling for everything, over-trusting a single model fit).

Avoid textbook checklist items that most EDA tutorials cover. Prefer traps that require reasoning about how the data were produced: measurement, logging, process causality, time, selection of what gets recorded. Keep each trap to one short paragraph per point.
