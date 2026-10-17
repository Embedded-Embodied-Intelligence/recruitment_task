.PHONY: install test data data-notraps reference check-claude bench report

install:
	python3 -m pip install -e ".[dev,notebook,harness]"

test:
	python3 -m pytest -q

data:
	python3 -m edabench.generate --config configs/benchmark.yaml

# Ablation: same seed and noise, every trap off (expected to score ~1.0).
data-notraps:
	python3 -m edabench.generate --config configs/benchmark.yaml --no-traps --out data_notraps --truth eval/ground_truth_notraps.json

# Re-execute the expert solution notebook (reads data/, writes reference/reference_answer.json).
reference:
	python3 reference/build_notebook.py

# Harness (docs/harness.md). MODELS and VARIANTS can be overridden: make bench MODELS=claude-haiku RUNS=5
MODELS ?= claude-haiku claude-sonnet
VARIANTS ?= full no_quality_hint
RUNS ?= 5

check-claude:
	python3 -m edabench.runner --check claude-haiku

bench:
	python3 -m edabench.runner --model $(MODELS) --variant $(VARIANTS) --runs $(RUNS)

report:
	python3 -m edabench.report outputs/runs/v3_seed42
