"""LaTeX snippets of the paper that quote repository files, so nothing is copied by hand.

    python paper/build_appendix.py      # writes paper/generated/*.tex

Appendix A (data), B (prompt), C (key table), D (three model outputs) and the results table.
"""

import json
from pathlib import Path

import pandas as pd

from edabench.backends import CLI_NOTE
from edabench.prompt import render_prompt
from edabench.scorer import score_text

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "paper" / "generated"
RUNS = ROOT / "outputs" / "runs" / "v5_seed42"

DESCRIPTIONS = {
    "batch_id": "batch number assigned by the line's MES terminal",
    "production_date": "production date, as exported",
    "line": "production line, L1--L4",
    "shift": "day or night shift",
    "operator_id": "press operator",
    "supplier_code": "resin supplier, key to \\texttt{suppliers.csv}",
    "machine_age_years": "age of the press, years",
    "ambient_temp_c": "hall temperature, \\textdegree C",
    "mold_temp": "mold temperature reading",
    "humidity_pct": "hall humidity reading, \\%",
    "cycle_time_s": "cycle time, s",
    "units_produced": "parts produced in the batch",
    "defective_units": "defective parts found by QC",
    "qc_inspection_min": "QC inspection time, min",
    "rework_cost_eur": "rework cost, EUR",
}
TYPES = {"object": "text", "str": "text", "float64": "float", "int64": "integer"}

# One run per model; excerpt = lines of response.md, joined with "[...]" where lines are skipped.
SELECTED = [
    ("Haiku 5.5", "claude-haiku/full/run_03", [3, 6, 7, 13, 17, 19, 29]),
    ("Sonnet 5.5", "claude-sonnet/full/run_02", [6, 8, 9, 13, 15, 18, 23]),
    ("Opus 5.5", "claude-opus/full/run_03", [4, 10, 11, 13, 17, 19, 25, 28]),
]


def tex(s: str) -> str:
    for a, b in [("\\", "\\textbackslash{}"), ("&", "\\&"), ("%", "\\%"), ("$", "\\$"), ("#", "\\#"),
                 ("_", "\\_"), ("{", "\\{"), ("}", "\\}"), ("~", "\\textasciitilde{}"), ("^", "\\^{}")]:
        s = s.replace(a, b)
    return s


def verbatim(text: str, size: str = "\\footnotesize", keep_together: bool = False) -> str:
    opts = f"fontsize={size},breaklines" + (",samepage" if keep_together else "")
    return f"\\begin{{Verbatim}}[{opts}]\n{text.rstrip()}\n\\end{{Verbatim}}\n"


def data_tables() -> str:
    batches = pd.read_csv(ROOT / "data" / "batches.csv", dtype={"humidity_pct": float})
    raw = pd.read_csv(ROOT / "data" / "batches.csv", dtype=str, keep_default_na=False)
    n_rows = f"{len(raw):,}".replace(",", "{,}")
    rows = ["\\begin{table}[H]\\centering\\footnotesize",
            "\\begin{tabularx}{\\linewidth}{@{}l l L@{}}\\toprule",
            "Column & Type & Description \\\\\\midrule"]
    for c in batches.columns:
        rows.append(f"\\texttt{{{tex(c)}}} & {TYPES[str(batches[c].dtype)]} & {DESCRIPTIONS[c]} \\\\")
    rows += ["\\bottomrule\\end{tabularx}",
             f"\\caption{{Schemat pliku \\texttt{{batches.csv}} ({n_rows} wierszy, {raw.shape[1]} kolumn). "
             f"/ Schema of \\texttt{{batches.csv}} ({n_rows} rows, {raw.shape[1]} columns).}}",
             "\\label{app:schema}\\end{table}", ""]

    head = raw.head(5)
    rows += ["\\begin{table}[H]\\centering\\footnotesize\\ttfamily",
             "\\begin{tabular}{@{}l" + "l" * len(head) + "@{}}\\toprule",
             "\\normalfont column & " + " & ".join(f"\\normalfont row {i + 1}" for i in range(len(head))) + " \\\\\\midrule"]
    for c in raw.columns:
        rows.append(tex(c) + " & " + " & ".join(tex(v) if v else "\\textit{(blank)}" for v in head[c]) + " \\\\")
    rows += ["\\bottomrule\\end{tabular}",
             "\\caption{Pierwsze pięć wierszy \\texttt{batches.csv}, bez żadnego czyszczenia. "
             "/ The first five rows of \\texttt{batches.csv}, as published.}", "\\end{table}", ""]

    for name, n in [("suppliers", 3), ("maintenance", 3)]:
        df = pd.read_csv(ROOT / "data" / f"{name}.csv", dtype=str, keep_default_na=False)
        rows += ["\\begin{table}[H]\\centering\\footnotesize\\ttfamily",
                 "\\begin{tabular}{@{}" + "l" * df.shape[1] + "@{}}\\toprule",
                 " & ".join(tex(c) for c in df.columns) + " \\\\\\midrule"]
        rows += [" & ".join(tex(v) for v in r) + " \\\\" for r in df.head(n).itertuples(index=False)]
        rows += ["\\bottomrule\\end{tabular}",
                 f"\\caption{{Pierwsze {n} wiersze \\texttt{{{name}.csv}} (razem {len(df)}). "
                 f"/ The first {n} rows of \\texttt{{{name}.csv}} ({len(df)} in total).}}", "\\end{table}", ""]
    return "\n".join(rows)


def prompt() -> str:
    return verbatim(render_prompt() + CLI_NOTE, "\\scriptsize")


def fmt(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, dict):
        return f"{v['line']}, {v['date']}"
    if isinstance(v, list):
        return ", ".join(sorted(v))
    return str(v)


def key_table() -> str:
    key = json.loads((ROOT / "eval" / "ground_truth.json").read_text())
    rows = ["\\begin{tabular}{@{}lrrr@{}}\\toprule", "Q & truth & naive & scale \\\\\\midrule"]
    for q, v in key["questions"].items():
        if v["type"] == "number":
            rows.append(f"{q} & {v['truth']:g} & {v['naive']:g} & {v['scale']:g} \\\\")
    rows.append("\\bottomrule\\end{tabular}")
    return "\n".join(rows) + "\n"


def run_section(label: str, path: str, lines: list[int]) -> str:
    run = RUNS / path
    text = (run / "response.md").read_text().splitlines()
    score = json.loads((run / "score.json").read_text())
    picked, prev = [], None
    for n in lines:
        if prev is not None and n != prev + 1:
            picked.append("[...]")
        picked.append(text[n - 1])
        prev = n
    start = next(i for i, line in enumerate(text) if line.startswith("```json"))
    name = path.split("/")[-1].replace("_", "\\_")
    out = [f"\\subsection*{{{label}, {name}: {score['total']:.3f}}}",
           "\\noindent\\textbf{Wycinek uzasadnienia / Excerpt of the justification}",
           verbatim("\n".join(picked)),
           "\\noindent\\begin{minipage}{\\linewidth}\\textbf{Odpowiedź JSON / JSON answer}",
           verbatim("\n".join(text[start + 1:-1]), keep_together=True) + "\\end{minipage}\n",
           "\\begin{table}[H]\\centering\\footnotesize",
           "\\begin{tabularx}{\\linewidth}{@{}l L L r c@{}}\\toprule",
           "Q & odpowiedź / answer & prawda / truth & wynik / score & pułapka / trap \\\\\\midrule"]
    for q in score["questions"]:
        trap = {True: "tak / yes", False: "--", None: "n/a"}[q["trap_hit"]]
        out.append(f"{q['qid']} & {tex(fmt(q['answer']))} & {tex(fmt(q['truth']))} & {q['score']:.2f} & {trap} \\\\")
    out += ["\\bottomrule\\end{tabularx}",
            f"\\caption{{{label}, {name}: ocena pytanie po pytaniu. / {label}, {name}: score per question.}}",
            "\\end{table}", ""]
    return "\n".join(out)


def results_rows() -> str:
    full = pd.read_csv(RUNS / "results.csv")
    notraps = pd.read_csv(ROOT / "outputs" / "runs" / "v5_seed42_notraps" / "results.csv")
    rows = []
    for model, label in [("claude-haiku", "Haiku 5.5"), ("claude-sonnet", "\\textbf{Sonnet 5.5}"), ("claude-opus", "Opus 5.5")]:
        d = full[(full["model"] == model) & (full["variant"] == "full")]
        done = d[~d["hit_turn_limit"]]
        mean = f"{d['total'].mean():.3f}"
        mean = f"\\textbf{{{mean}}}" if "Sonnet" in label else mean
        rows.append(f"{label} & {len(d)} & {mean} & {d['total'].std():.3f} & "
                    f"{d['total'].min():.3f}--{d['total'].max():.3f} & {len(done)} ({done['total'].mean():.3f}) \\\\")
    rows.append("\\midrule")
    ref = json.loads((ROOT / "reference" / "reference_answer.json").read_text())
    key = json.loads((ROOT / "eval" / "ground_truth.json").read_text())
    reference = score_text("```json\n" + json.dumps(ref) + "\n```", key)["total"]
    rows.append(f"\\REFLABEL & 1 & {reference:.3f} & & & \\\\")
    rows.append(f"\\NOTRAPSLABEL & {len(notraps)} & {notraps['total'].mean():.3f} & {notraps['total'].std():.3f} & "
                f"{notraps['total'].min():.3f}--{notraps['total'].max():.3f} & {(~notraps['hit_turn_limit']).sum()} \\\\")
    return "\n".join(rows) + "\n"


def main() -> None:
    OUT.mkdir(exist_ok=True)
    (OUT / "app_data.tex").write_text(data_tables())
    (OUT / "app_prompt.tex").write_text(prompt())
    (OUT / "key_table.tex").write_text(key_table())
    (OUT / "app_runs.tex").write_text("\n".join(run_section(*s) for s in SELECTED))
    (OUT / "results_rows.tex").write_text(results_rows())
    print(f"wrote {', '.join(sorted(p.name for p in OUT.glob('*.tex')))} to {OUT}")


if __name__ == "__main__":
    main()
