"""Deterministic partial-credit scoring of a model answer against eval/ground_truth.json.

Each question uses a metric matched to the *type* of its answer (docs/measure.md):

    number    s = max(0, 1 - |a - t| / scale)  scale = distance of the naive trap answer
    set       F1 between answered and true sets (both empty -> 1)
    category  exact match, case-insensitive
    regime    line must match (gate) x max(0, 1 - |days off| / scale_days); null vs null -> 1

The total is the weighted mean over the nine questions, always in [0, 1]. A missing or
malformed field scores 0 for its question only.

Usage:
    python -m edabench.scorer outputs/<run>/response.md --truth eval/ground_truth.json
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path

from edabench.answer import ParsedAnswer, parse_answer

WEIGHTS = {
    "A1": 0.075, "A2": 0.075, "A3": 0.075, "A4": 0.075,  # Describe   0.30
    "B1": 0.150, "B2": 0.125, "B3": 0.125,               # Salient    0.40
    "C1": 0.150, "C2": 0.150,                            # Interpret  0.30
}
SECTIONS = {"A": "describe", "B": "salient_features", "C": "interpret"}
assert abs(sum(WEIGHTS.values()) - 1) < 1e-12


# --- metrics ----------------------------------------------------------------------

def number_score(answer: float, truth: float, scale: float) -> float:
    """Linear decay from 1 at the truth to 0 at `scale` away from it."""
    if scale <= 0:
        raise ValueError("scale must be positive")
    return max(0.0, 1.0 - abs(answer - truth) / scale)


def set_f1(answer, truth) -> float:
    """F1 of two sets of identifiers (compared case-insensitively)."""
    a = {str(x).strip().lower() for x in answer}
    t = {str(x).strip().lower() for x in truth}
    if not a and not t:
        return 1.0
    return 2 * len(a & t) / (len(a) + len(t))


def category_score(answer: str, truth: str) -> float:
    return float(answer.strip().lower() == truth.strip().lower())


def regime_score(answer: dict | None, truth: dict | None, scale_days: float) -> float:
    if truth is None or answer is None:
        return float(truth is None and answer is None)
    if answer["line"].upper() != truth["line"].upper():
        return 0.0
    try:
        days = abs((date.fromisoformat(answer["date"]) - date.fromisoformat(truth["date"])).days)
    except ValueError:
        return 0.0
    return max(0.0, 1.0 - days / scale_days)


# --- worked example from the task PDF (docs/measure.md, section 2) ------------------

def positional_accuracy(answer: list, truth: list) -> float:
    """Share of positions holding the right element: for ordered lists of labels."""
    return sum(a == t for a, t in zip(answer, truth)) / max(len(answer), len(truth))


def jaccard(answer, truth) -> float:
    a, t = set(answer), set(truth)
    return len(a & t) / len(a | t) if a | t else 1.0


def relative_closeness(answer: list[float], truth: list[float]) -> float:
    """Mean of max(0, 1 - |a - t| / |t|) per position: for ordered lists of quantities."""
    return sum(max(0.0, 1 - abs(a - t) / abs(t)) for a, t in zip(answer, truth)) / len(truth)


# --- scoring ----------------------------------------------------------------------

@dataclass
class QuestionScore:
    qid: str
    score: float
    weight: float
    answer: object
    truth: object
    note: str = ""            # parse error or warning
    trap_hit: bool | None = None  # answer closer to the naive trap answer than to the truth


def _trap_hit(spec: dict, answer) -> bool | None:
    if "naive" not in spec or answer is None:
        return None
    if spec["type"] == "number":
        return abs(answer - spec["naive"]) < abs(answer - spec["truth"])
    if spec["type"] == "category":
        return category_score(answer, spec["naive"]) == 1.0
    return None


def score_parsed(parsed: ParsedAnswer, ground_truth: dict) -> dict:
    questions = ground_truth["questions"]
    rows = []
    for qid, weight in WEIGHTS.items():
        spec = questions[qid]
        if qid not in parsed.values:
            note = parsed.errors.get(qid) or parsed.errors.get("_", "missing")
            rows.append(QuestionScore(qid, 0.0, weight, None, spec["truth"], note))
            continue
        a, t = parsed.values[qid], spec["truth"]
        kind = spec["type"]
        if kind == "number":
            s = number_score(a, t, spec["scale"])
        elif kind == "set":
            s = set_f1(a, t)
        elif kind == "category":
            s = category_score(a, t)
        elif kind == "regime":
            s = regime_score(a, t, spec["scale_days"])
        else:
            raise ValueError(f"unknown question type {kind!r}")
        rows.append(QuestionScore(qid, round(s, 6), weight, a, t, parsed.warnings.get(qid, ""), _trap_hit(spec, a)))

    total = sum(r.score * r.weight for r in rows)
    sections = {
        name: round(sum(r.score * r.weight for r in rows if r.qid[0] == p)
                    / sum(r.weight for r in rows if r.qid[0] == p), 6)
        for p, name in SECTIONS.items()
    }
    return {
        "total": round(total, 6),
        "sections": sections,
        "format_ok": parsed.ok,
        "questions": [asdict(r) for r in rows],
    }


def score_text(text: str, ground_truth: dict) -> dict:
    return score_parsed(parse_answer(text), ground_truth)


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description="Score a model response against the answer key.")
    ap.add_argument("response", help="file with the model's final reply (text with a ```json block, or plain JSON)")
    ap.add_argument("--truth", default="eval/ground_truth.json")
    args = ap.parse_args(argv)
    result = score_text(Path(args.response).read_text(), json.loads(Path(args.truth).read_text()))
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
