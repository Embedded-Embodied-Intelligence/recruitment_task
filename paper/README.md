# Paper

Two documents with the same content: `main_pl.tex` in Polish and `main_en.tex` in English. Each has its own appendices in its language; `main_pl.pdf` (17 pages) and `main_en.pdf` (16 pages) are the compiled versions. `preamble.tex` is shared by both.

- **Overleaf:** New Project → Upload Project, and upload a zip of this folder (`main_pl.tex`, `main_en.tex`, `preamble.tex`, the two `fig_*.png` and `generated/`). Pick the document to build under Menu → Main document. The default compiler (pdfLaTeX) works.
- **Locally:** `make paper` (needs pdfLaTeX with the XCharter and inconsolata fonts and Polish babel support, `texlive-lang-polish` on Debian).
- **Figures:** `python paper/figures.py` draws `fig_quiet_traps.png` (from the published files only) and `fig_heatmap_finished.png` (from `outputs/runs/v5_seed42/results.csv`). The pipeline figure is TikZ in the preamble.
- **Generated tables and listings:** `python paper/build_appendix.py` writes `generated/pl/*.tex` and `generated/en/*.tex` from the repository files: the data schema and sample rows, the prompt exactly as a run receives it, the v5 key table, the three model outputs with their per-question scores, and the results table. Nothing in the appendices is copied by hand.

The papers contain the answer key: never give them to a model under test.
