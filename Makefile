.PHONY: install test data data-notraps

install:
	python3 -m pip install -e ".[dev]"

test:
	python3 -m pytest -q

data:
	python3 -m edabench.generate --config configs/benchmark.yaml

# Ablation: same seed and noise, every trap off (expected to score ~1.0).
data-notraps:
	python3 -m edabench.generate --config configs/benchmark.yaml --no-traps --out data_notraps --truth eval/ground_truth_notraps.json
