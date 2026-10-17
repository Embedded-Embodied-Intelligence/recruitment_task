"""Aggregate scored runs into tables for the write-up.

    python -m edabench.report outputs/runs/v3_seed42

Reads every run_XX/score.json under <root>/<model>/<variant>/ and writes, into <root>:
- results.csv   one row per run: total, sections, per-question scores and trap hits;
- summary.md    mean, sd, min and max of the total per model and prompt variant, mean
                score per question, how often each trap caught the model, the most
                common wrong items in the set answers, the prompt-ablation effect and a
                check that the ranking of models does not hinge on the question weights;
- heatmap.png   mean score per model x question.

With 5 runs per cell the sd is reported next to every mean: a difference between models
smaller than their run-to-run spread is not a finding.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import pandas as pd

SET_QUESTIONS = ("B1", "B2")


def collect(root: Path) -> tuple[pd.DataFrame, dict]:
    rows, set_errors = [], {}
    for score_path in sorted(root.glob("*/*/run_*/score.json")):
        run_dir = score_path.parent
        model, variant = run_dir.parent.parent.name, run_dir.parent.name
        score = json.loads(score_path.read_text())
        meta_path = run_dir / "metadata.json"
        meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        row = {
            "model": model, "variant": variant, "run": run_dir.name,
            "total": score["total"], **score["sections"], "format_ok": score["format_ok"],
            "equal_weight_total": sum(q["score"] for q in score["questions"]) / len(score["questions"]),
            "n_tool_calls": meta.get("n_tool_calls"), "duration_s": meta.get("duration_s"),
            "hit_turn_limit": meta.get("hit_turn_limit"),
            "permission_denials": (meta.get("usage") or {}).get("permission_denials"),
            "served_models": ",".join(meta.get("served_models", []) or []),
        }
        for q in score["questions"]:
            row[f"q_{q['qid']}"] = q["score"]
            row[f"trap_{q['qid']}"] = q["trap_hit"]
            if q["qid"] in SET_QUESTIONS:
                given = {str(x).lower() for x in (q["answer"] or [])}
                truth = {str(x).lower() for x in q["truth"]}
                c = set_errors.setdefault((model, variant, q["qid"]), Counter())
                c.update(f"+{x}" for x in given - truth)
                c.update(f"-{x}" for x in truth - given)
        rows.append(row)
    return pd.DataFrame(rows), set_errors


def _md(df: pd.DataFrame, digits: int = 3) -> str:
    """A pipe table without the optional `tabulate` dependency."""
    df = df.reset_index()
    fmt = lambda v: f"{v:.{digits}f}" if isinstance(v, float) else ("" if v is None else str(v))
    lines = ["| " + " | ".join(map(str, df.columns)) + " |", "|" + "---|" * len(df.columns)]
    lines += ["| " + " | ".join(fmt(v) for v in r) + " |" for r in df.itertuples(index=False)]
    return "\n".join(lines)


def summarize(df: pd.DataFrame, set_errors: dict) -> str:
    keys = ["model", "variant"]
    qcols = sorted(c for c in df.columns if c.startswith("q_"))
    totals = df.groupby(keys)["total"].agg(["count", "mean", "std", "min", "max"])
    totals["equal_weights_mean"] = df.groupby(keys)["equal_weight_total"].mean()
    totals["format_ok"] = df.groupby(keys)["format_ok"].mean()
    totals["tool_calls_mean"] = df.groupby(keys)["n_tool_calls"].mean()
    totals["turn_limit_runs"] = df.groupby(keys)["hit_turn_limit"].sum()
    per_q = df.groupby(keys)[qcols].mean().rename(columns=lambda c: c[2:])
    per_q_sd = df.groupby(keys)[qcols].std().rename(columns=lambda c: c[2:])

    hcols = [c for c in df.columns if c.startswith("trap_") and df[c].notna().any()]
    hits = (df.assign(**{c: df[c].map(lambda v: float(v) if v is not None and v == v else None) for c in hcols})
              .groupby(keys)[hcols].mean().rename(columns=lambda c: c[5:]))

    denied = int(df["permission_denials"].fillna(0).sum())
    out = ["# Benchmark results", "",
           f"{len(df)} scored runs. Scores are in [0, 1]; sd is the run-to-run standard deviation.", "",
           *([f"**Warning:** {denied} tool calls were denied by the harness; check those runs.", ""] if denied else []),
           "## Total score", "", _md(totals), "",
           "## Mean score per question", "", _md(per_q, 2), "",
           "Run-to-run sd per question:", "", _md(per_q_sd, 2), "",
           "## How often the trap answer was given", "",
           "Share of runs whose answer was closer to the naive (trap) answer than to the truth.", "",
           _md(hits, 2), "",
           "## Wrong items in set answers", "",
           "`+x` = listed but wrong, `-x` = missed; counts over runs.", ""]
    for (model, variant, qid), c in sorted(set_errors.items()):
        if c:
            out.append(f"- {model} / {variant} / {qid}: " + ", ".join(f"`{k}` x{v}" for k, v in c.most_common(6)))
    out.append("")

    variants = set(df["variant"])
    if {"full", "no_quality_hint"} <= variants:
        m = df.groupby(keys)[["total", *qcols]].mean()
        both = [x for x in df["model"].unique() if (x, "full") in m.index and (x, "no_quality_hint") in m.index]
        if both:
            delta = pd.DataFrame({x: m.loc[(x, "full")] - m.loc[(x, "no_quality_hint")] for x in both}).T
            delta = delta.rename(columns=lambda c: c[2:] if c.startswith("q_") else c)
            delta.index.name = "model"
            out += ["## Prompt ablation: full minus no_quality_hint", "",
                    "Positive = the data-quality hint helped.", "", _md(delta, 3), ""]

    full = df[df["variant"] == "full"] if "full" in variants else df
    rank_w = full.groupby("model")["total"].mean().rank(ascending=False)
    rank_eq = full.groupby("model")["equal_weight_total"].mean().rank(ascending=False)
    same = bool((rank_w == rank_eq).all())
    out += ["## Robustness of the ranking to the weights", "",
            "The ranking of models by mean total is "
            + ("the same" if same else "**different**")
            + " with equal question weights (variant `full`).", ""]
    return "\n".join(out)


def heatmap(df: pd.DataFrame, path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    qcols = sorted(c for c in df.columns if c.startswith("q_"))
    m = df.groupby(["model", "variant"])[qcols].mean()
    fig, ax = plt.subplots(figsize=(1 + 0.7 * len(qcols), 1 + 0.45 * len(m)))
    im = ax.imshow(m.values, vmin=0, vmax=1, cmap="RdYlGn", aspect="auto")
    ax.set_xticks(range(len(qcols)), [c[2:] for c in qcols])
    ax.set_yticks(range(len(m)), [f"{a} / {b}" for a, b in m.index])
    for (i, j), v in pd.DataFrame(m.values).stack().items():
        ax.text(j, i, f"{v:.2f}", ha="center", va="center", fontsize=8)
    fig.colorbar(im, ax=ax, label="mean score")
    ax.set_title("Mean score per question")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", type=Path, help="outputs/runs/<dataset>")
    args = ap.parse_args(argv)
    df, set_errors = collect(args.root)
    if df.empty:
        raise SystemExit(f"no scored runs under {args.root}")
    df.to_csv(args.root / "results.csv", index=False)
    (args.root / "summary.md").write_text(summarize(df, set_errors))
    heatmap(df, args.root / "heatmap.png")
    print(f"wrote results.csv, summary.md and heatmap.png to {args.root}")


if __name__ == "__main__":
    main()
