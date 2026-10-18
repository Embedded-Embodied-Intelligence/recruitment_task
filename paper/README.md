# Paper

`main.tex` is a six-page write-up of the task, the measure and the v5 results; `main.pdf` is its compiled version.

- **Overleaf:** New Project → Upload Project, and upload a zip of this folder (`main.tex` and the two `fig_*.png`). The default compiler (pdfLaTeX) works.
- **Locally:** `make paper` (needs pdfLaTeX with the XCharter and inconsolata fonts).
- **Figures:** `fig_quiet_traps.png` comes from `python paper/figures.py` (published files only); `fig_heatmap_v5.png` is `outputs/runs/v5_seed42/heatmap.png`.

The paper contains the answer key: never give it to a model under test.
