"""Group question scores by the kind of skill they test, across dataset versions.

    python -m edabench.profile outputs/runs/v4_seed42 outputs/runs/v5_seed42 --out outputs/runs/profile

A single total mixes questions every model solves with questions almost none does. This
profile averages the per-question scores of the finished runs (a run with no parseable
answer measures the turn budget, not the analysis) by what the question's trap demands:

- loud: the naive analysis raises a signal by itself (a parser error, a -1 sentinel, a
  phrase in the prompt, a step of several standard deviations), and fixing it is routine;
- estimate: the problem is easy to see, but the answer is a number that has to be
  estimated with the right method (a sensor offset, an optimum, a counterfactual);
- quiet: nothing in the naive analysis points at the problem (the frozen logger, T19);
- drivers: B1, choosing the direct effects among confounded candidates.

Writes <out>.json (read by edabench.explorer) and <out>.md.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

CATEGORIES = {
    "loud": {"label": "Loud traps: detected and fixed", "v4": ["A1", "A2", "A3", "B2", "B3", "C1"],
             "v5": ["A1", "A3", "B2", "B3", "C1"]},
    "estimate": {"label": "Estimate after detection (A4, C2, C3)", "v4": ["A4", "C2", "C3"], "v5": ["A4", "C2", "C3"]},
    "quiet": {"label": "Quiet trap: no signal (frozen logger, A2 in v5)", "v5": ["A2"]},
    "drivers": {"label": "Direct drivers (B1)", "v4": ["B1"], "v5": ["B1"]},
}
MODELS = ("claude-haiku", "claude-sonnet", "claude-opus")


def build(roots: list[Path], variant: str = "full") -> dict:
    scores: dict[tuple[str, str], list[float]] = {}
    runs: dict[str, set[str]] = {}
    for root in roots:
        version = root.name.split("_")[0]
        for path in sorted(root.glob(f"*/{variant}/run_*/score.json")):
            model = path.parent.parent.parent.name
            score = json.loads(path.read_text())
            if not score["format_ok"]:
                continue
            runs.setdefault(model, set()).add(f"{version}/{path.parent.name}")
            for key, cat in CATEGORIES.items():
                qids = cat.get(version, [])
                scores.setdefault((model, key), []).extend(q["score"] for q in score["questions"] if q["qid"] in qids)
    models = [m for m in MODELS if m in runs] + sorted(set(runs) - set(MODELS))
    table = {
        m: {k: ({"mean": round(sum(v) / len(v), 3), "n": len(v)} if (v := scores.get((m, k))) else None)
            for k in CATEGORIES}
        for m in models
    }
    return {"variant": variant, "datasets": [r.name for r in roots], "finished_runs": {m: len(runs[m]) for m in models},
            "categories": {k: c["label"] for k, c in CATEGORIES.items()}, "table": table}


def to_markdown(profile: dict) -> str:
    cats = profile["categories"]
    lines = [
        f"# Score by kind of skill ({', '.join(profile['datasets'])}, {profile['variant']} prompt, finished runs)",
        "",
        "Mean question score; n is the number of question answers behind each cell.",
        "",
        "| model | runs | " + " | ".join(cats.values()) + " |",
        "|---|---|" + "---|" * len(cats),
    ]
    for model, row in profile["table"].items():
        cells = [f"{c['mean']:.2f} (n={c['n']})" if c else "no runs" for c in row.values()]
        lines.append(f"| {model} | {profile['finished_runs'][model]} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("roots", nargs="+", type=Path, help="outputs/runs/<dataset> directories")
    ap.add_argument("--out", type=Path, default=Path("outputs/runs/profile"))
    ap.add_argument("--variant", default="full")
    args = ap.parse_args(argv)
    profile = build(args.roots, args.variant)
    args.out.with_suffix(".json").write_text(json.dumps(profile, indent=2) + "\n")
    args.out.with_suffix(".md").write_text(to_markdown(profile))
    print(to_markdown(profile))


if __name__ == "__main__":
    main()
