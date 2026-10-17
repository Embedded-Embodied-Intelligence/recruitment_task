.PHONY: install test data data-notraps reference

install:
	python3 -m pip install -e ".[dev,notebook]"

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
