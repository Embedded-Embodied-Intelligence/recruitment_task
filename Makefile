.PHONY: install test data data-notraps reference check-claude bench report profile explorer paper

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
	python3 -m edabench.report outputs/runs/v5_seed42

profile:
	python3 -m edabench.profile outputs/runs/v4_seed42 outputs/runs/v5_seed42 --out outputs/runs/profile

explorer: profile
	python3 -m edabench.explorer outputs/runs/v5_seed42 --out docs/explorer.html
	python3 -m edabench.explorer outputs/runs/v4_seed42 --out docs/explorer_v4.html

# Six-page write-up (paper/README.md); figures from the published files and the v5 report.
paper:
	python3 paper/figures.py
	cp outputs/runs/v5_seed42/heatmap.png paper/fig_heatmap_v5.png
	cd paper && pdflatex -interaction=nonstopmode main.tex >/dev/null && pdflatex -interaction=nonstopmode main.tex >/dev/null
	rm -f paper/main.aux paper/main.log paper/main.out
