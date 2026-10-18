"""LaTeX snippets of the paper that quote repository files, so nothing is copied by hand.

    python paper/build_appendix.py      # writes paper/generated/{pl,en}/*.tex

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

# Column descriptions in English and Polish.
DESCRIPTIONS = {
    "batch_id": ("batch number assigned by the line's MES terminal", "numer partii nadany przez terminal MES linii"),
    "production_date": ("production date, as exported", "data produkcji, tak jak w eksporcie"),
    "line": ("production line, L1--L4", "linia produkcyjna, L1--L4"),
    "shift": ("day or night shift", "zmiana dzienna albo nocna"),
    "operator_id": ("press operator", "operator prasy"),
    "supplier_code": ("resin supplier, key to \\texttt{suppliers.csv}", "dostawca granulatu, klucz do \\texttt{suppliers.csv}"),
    "machine_age_years": ("age of the press, years", "wiek prasy, lata"),
    "ambient_temp_c": ("hall temperature, \\textdegree C", "temperatura hali, \\textdegree C"),
    "mold_temp": ("mold temperature reading", "odczyt temperatury formy"),
    "humidity_pct": ("hall humidity reading, \\%", "odczyt wilgotności hali, \\%"),
    "cycle_time_s": ("cycle time, s", "czas cyklu, s"),
    "units_produced": ("parts produced in the batch", "liczba sztuk wyprodukowanych w partii"),
    "defective_units": ("defective parts found by QC", "wadliwe sztuki wykryte przez kontrolę jakości"),
    "qc_inspection_min": ("QC inspection time, min", "czas kontroli jakości, min"),
    "rework_cost_eur": ("rework cost, EUR", "koszt poprawek, EUR"),
}
TYPES = {"object": ("text", "tekst"), "str": ("text", "tekst"), "float64": ("float", "liczba"),
         "int64": ("integer", "całkowita")}

# Every other string the snippets print, in English and Polish.
WORDS = {
    "en": {"column": "Column", "type": "Type", "description": "Description", "row": "row",
           "blank": "(blank)", "schema": "Schema of \\texttt{{batches.csv}} ({rows} rows, {cols} columns).",
           "first5": "The first five rows of \\texttt{batches.csv}, as published, without any cleaning.",
           "firstn": "The first {n} rows of \\texttt{{{name}.csv}} ({total} in total).",
           "key": "Q & truth & naive & scale", "excerpt": "Excerpt of the justification", "json": "JSON answer",
           "head": "Q & answer & truth & score & trap", "yes": "yes", "per_q": "{label}, {name}: score per question."},
    "pl": {"column": "Kolumna", "type": "Typ", "description": "Opis", "row": "wiersz",
           "blank": "(puste)", "schema": "Schemat pliku \\texttt{{batches.csv}} ({rows} wierszy, {cols} kolumn).",
           "first5": "Pierwsze pięć wierszy \\texttt{batches.csv}, tak jak opublikowane, bez żadnego czyszczenia.",
           "firstn": "Pierwsze {n} wiersze \\texttt{{{name}.csv}} (razem {total}).",
           "key": "Pyt. & prawda & naiwna & skala", "excerpt": "Wycinek uzasadnienia", "json": "Odpowiedź JSON",
           "head": "Pyt. & odpowiedź & prawda & wynik & pułapka", "yes": "tak", "per_q": "{label}, {name}: ocena pytanie po pytaniu."},
}

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


def data_tables(lang: str) -> str:
    w, i = WORDS[lang], 0 if lang == "en" else 1
    batches = pd.read_csv(ROOT / "data" / "batches.csv", dtype={"humidity_pct": float})
    raw = pd.read_csv(ROOT / "data" / "batches.csv", dtype=str, keep_default_na=False)
    n_rows = f"{len(raw):,}".replace(",", "{,}")
    rows = ["\\begin{table}[H]\\centering\\footnotesize",
            "\\begin{tabularx}{\\linewidth}{@{}l l L@{}}\\toprule",
            f"{w['column']} & {w['type']} & {w['description']} \\\\\\midrule"]
    for c in batches.columns:
        rows.append(f"\\texttt{{{tex(c)}}} & {TYPES[str(batches[c].dtype)][i]} & {DESCRIPTIONS[c][i]} \\\\")
    rows += ["\\bottomrule\\end{tabularx}",
             "\\caption{" + w["schema"].format(rows=n_rows, cols=raw.shape[1]) + "}",
             "\\label{app:schema}\\end{table}", ""]

    head = raw.head(5)
    rows += ["\\begin{table}[H]\\centering\\footnotesize\\ttfamily",
             "\\begin{tabular}{@{}l" + "l" * len(head) + "@{}}\\toprule",
             f"\\normalfont {w['column'].lower()} & " + " & ".join(f"\\normalfont {w['row']} {k + 1}" for k in range(len(head))) + " \\\\\\midrule"]
    for c in raw.columns:
        rows.append(tex(c) + " & " + " & ".join(tex(v) if v else f"\\textit{{{w['blank']}}}" for v in head[c]) + " \\\\")
    rows += ["\\bottomrule\\end{tabular}",
             "\\caption{" + w["first5"] + "}", "\\end{table}", ""]

    for name, n in [("suppliers", 3), ("maintenance", 3)]:
        df = pd.read_csv(ROOT / "data" / f"{name}.csv", dtype=str, keep_default_na=False)
        rows += ["\\begin{table}[H]\\centering\\footnotesize\\ttfamily",
                 "\\begin{tabular}{@{}" + "l" * df.shape[1] + "@{}}\\toprule",
                 " & ".join(tex(c) for c in df.columns) + " \\\\\\midrule"]
        rows += [" & ".join(tex(v) for v in r) + " \\\\" for r in df.head(n).itertuples(index=False)]
        rows += ["\\bottomrule\\end{tabular}",
                 "\\caption{" + w["firstn"].format(n=n, name=name, total=len(df)) + "}", "\\end{table}", ""]
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


def key_table(lang: str) -> str:
    key = json.loads((ROOT / "eval" / "ground_truth.json").read_text())
    rows = ["\\begin{tabular}{@{}lrrr@{}}\\toprule", WORDS[lang]["key"] + " \\\\\\midrule"]
    for q, v in key["questions"].items():
        if v["type"] == "number":
            rows.append(f"{q} & {v['truth']:g} & {v['naive']:g} & {v['scale']:g} \\\\")
    rows.append("\\bottomrule\\end{tabular}")
    return "\n".join(rows) + "\n"


def run_section(lang: str, label: str, path: str, lines: list[int]) -> str:
    w = WORDS[lang]
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
           f"\\noindent\\textbf{{{w['excerpt']}}}",
           verbatim("\n".join(picked)),
           "\\noindent\\begin{minipage}{\\linewidth}\\textbf{" + w["json"] + "}",
           verbatim("\n".join(text[start + 1:-1]), keep_together=True) + "\\end{minipage}\n",
           "\\begin{table}[H]\\centering\\footnotesize",
           "\\begin{tabularx}{\\linewidth}{@{}l L L r c@{}}\\toprule",
           w["head"] + " \\\\\\midrule"]
    for q in score["questions"]:
        trap = {True: w["yes"], False: "--", None: "n/a"}[q["trap_hit"]]
        out.append(f"{q['qid']} & {tex(fmt(q['answer']))} & {tex(fmt(q['truth']))} & {q['score']:.2f} & {trap} \\\\")
    out += ["\\bottomrule\\end{tabularx}",
            "\\caption{" + w["per_q"].format(label=label, name=name) + "}",
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
    for lang in WORDS:
        out = OUT / lang
        out.mkdir(parents=True, exist_ok=True)
        (out / "app_data.tex").write_text(data_tables(lang))
        (out / "app_prompt.tex").write_text(prompt())
        (out / "key_table.tex").write_text(key_table(lang))
        (out / "app_runs.tex").write_text("\n".join(run_section(lang, *s) for s in SELECTED))
        (out / "results_rows.tex").write_text(results_rows())
    print(f"wrote {', '.join(sorted(p.name for p in (OUT / 'en').glob('*.tex')))} to {OUT}/{{en,pl}}")


if __name__ == "__main__":
    main()
