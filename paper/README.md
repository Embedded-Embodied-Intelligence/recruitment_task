# Paper

`main.tex` is a bilingual write-up of the task: the full text in Polish (Part I), then the same text in English (Part II), and shared appendices with bilingual captions. `main.pdf` is its compiled version (26 pages).

- **Overleaf:** New Project → Upload Project, and upload a zip of this folder (`main.tex`, the two `fig_*.png` and `generated/`). The default compiler (pdfLaTeX) works.
- **Locally:** `make paper` (needs pdfLaTeX with the XCharter and inconsolata fonts and Polish babel support, `texlive-lang-polish` on Debian).
- **Figures:** `python paper/figures.py` draws `fig_quiet_traps.png` (from the published files only) and `fig_heatmap_finished.png` (from `outputs/runs/v5_seed42/results.csv`). The pipeline figure is TikZ in `main.tex`.
- **Generated tables and listings:** `python paper/build_appendix.py` writes `generated/*.tex` from the repository files: the data schema and sample rows, the prompt exactly as a run receives it, the v5 key table, the three model outputs with their per-question scores, and the results table. Nothing in the appendices is copied by hand.

The paper contains the answer key: never give it to a model under test.
