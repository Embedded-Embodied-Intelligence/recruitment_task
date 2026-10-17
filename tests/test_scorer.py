"""Scorer tests: the metric itself is part of the benchmark, so it is tested like code.

Covers the required properties (0 for a bad answer, 1 for the correct one, strictly
between for partial answers), the task PDF's list example, monotonicity, isolation of
format errors, and anchor answers (expert ~1, naive trap-taker low).
"""

import json
from pathlib import Path

import numpy as np
import pytest

from edabench.scorer import (
    WEIGHTS, WEIGHTS_V2, category_score, jaccard, number_score, positional_accuracy, regime_score,
    relative_closeness, score_text, set_f1,
)

ROOT = Path(__file__).resolve().parents[1]
GT = json.loads((ROOT / "eval" / "ground_truth.json").read_text())
Q = GT["questions"]
REFERENCE = json.loads((ROOT / "reference" / "reference_answer.json").read_text())


def answer_text(**overrides) -> str:
    return "```json\n" + json.dumps(REFERENCE | overrides) + "\n```"


def perfect() -> dict:
    return {
        "A1_unique_batches": Q["A1"]["truth"], "A2_missing_humidity_batches": Q["A2"]["truth"],
        "A3_overall_defect_rate": Q["A3"]["truth"], "A4_median_mold_temp_c": Q["A4"]["truth"],
        "B1_direct_drivers": Q["B1"]["truth"], "B2_leakage_columns": Q["B2"]["truth"],
        "B3_regime_change": Q["B3"]["truth"], "C1_best_supplier": Q["C1"]["truth"],
        "C2_optimal_humidity_pct": Q["C2"]["truth"], "C3_rate_with_regular_cleaning": Q["C3"]["truth"],
    }


def naive() -> dict:
    """What an analyst who falls for every trap would answer."""
    return {
        "A1_unique_batches": Q["A1"]["naive"], "A2_missing_humidity_batches": Q["A2"]["naive"],
        "A3_overall_defect_rate": Q["A3"]["naive"], "A4_median_mold_temp_c": Q["A4"]["naive"],
        "B1_direct_drivers": ["mold_temp", "machine_age_years", "ambient_temp_c", "cycle_time_s"],
        "B2_leakage_columns": [], "B3_regime_change": None, "C1_best_supplier": Q["C1"]["naive"],
        "C2_optimal_humidity_pct": Q["C2"]["naive"], "C3_rate_with_regular_cleaning": Q["C3"]["naive"],
    }


# --- the three properties required by the task -------------------------------------

def test_correct_answer_scores_one():
    r = score_text(json.dumps(perfect()), GT)
    assert r["total"] == pytest.approx(1.0) and r["format_ok"]


@pytest.mark.parametrize("text", ["", "I could not finish the analysis.", "```json\n{}\n```"])
def test_no_answer_scores_zero(text):
    assert score_text(text, GT)["total"] == 0.0


def test_trap_answers_score_zero_on_their_questions():
    r = {q["qid"]: q for q in score_text(json.dumps(naive()), GT)["questions"]}
    for qid in ("A1", "A2", "A3", "A4", "B3", "C1", "C2", "C3"):
        assert r[qid]["score"] == 0.0, qid
    assert all(r[q]["trap_hit"] for q in ("A1", "A2", "A3", "A4", "C1", "C2", "C3"))


def test_partial_answer_is_strictly_between():
    total = score_text(json.dumps(naive()), GT)["total"]
    assert 0 < total < 0.3  # only the partly right B1 earns credit


def test_reference_solution_scores_near_one():
    assert score_text(answer_text(), GT)["total"] > 0.98


def test_older_keys_keep_their_own_weights():
    """A v2 key (nine questions, no weights field) is scored as it was when published."""
    v2 = json.loads((ROOT / "outputs" / "pilot_01" / "ground_truth_v2.json").read_text())
    r = score_text((ROOT / "outputs" / "pilot_01" / "response.md").read_text(), v2)
    assert r["total"] == pytest.approx(0.995161) and r["format_ok"]
    assert [q["qid"] for q in r["questions"]] == list(WEIGHTS_V2)


# --- the task PDF's list example: [1, 3, 6, 11] vs [1, 3, 7, 15] --------------------

def test_pdf_example_depends_on_answer_semantics():
    truth, ans = [1, 3, 6, 11], [1, 3, 7, 15]
    assert positional_accuracy(ans, truth) == 0.5          # ordered labels (e.g. row indices)
    assert jaccard(ans, truth) == pytest.approx(1 / 3)     # unordered labels
    assert set_f1(ans, truth) == 0.5
    assert relative_closeness(ans, truth) == pytest.approx(0.8674, abs=1e-4)  # quantities
    for s in (positional_accuracy(ans, truth), jaccard(ans, truth), relative_closeness(ans, truth)):
        assert 0 < s < 1
    assert positional_accuracy(truth, truth) == jaccard(truth, truth) == relative_closeness(truth, truth) == 1


# --- metric properties ---------------------------------------------------------------

def test_number_score_bounded_monotone_symmetric():
    rng = np.random.default_rng(0)
    for _ in range(200):
        t, scale = rng.normal(0, 100), rng.uniform(0.01, 50)
        d1, d2 = sorted(rng.uniform(0, 3 * scale, 2))
        s1, s2 = number_score(t + d1, t, scale), number_score(t + d2, t, scale)
        assert 0 <= s2 <= s1 <= 1
        assert number_score(t - d1, t, scale) == pytest.approx(s1)
    assert number_score(5, 5, 1) == 1 and number_score(6, 5, 1) == 0


def test_set_f1_edges():
    assert set_f1([], []) == 1.0
    assert set_f1(["a"], []) == 0.0 and set_f1([], ["a"]) == 0.0
    assert set_f1(["Mold_Temp", "shift"], ["mold_temp", "shift"]) == 1.0
    assert set_f1(["a", "b", "c"], ["a", "b"]) == pytest.approx(0.8)   # one false positive
    assert set_f1(["a"], ["a", "b"]) == pytest.approx(2 / 3)           # one miss


def test_regime_score():
    t = {"line": "L2", "date": "2025-06-16"}
    assert regime_score(t, t, 30) == 1
    assert regime_score({"line": "L2", "date": "2025-06-23"}, t, 30) == pytest.approx(1 - 7 / 30)
    assert regime_score({"line": "L3", "date": "2025-06-16"}, t, 30) == 0
    assert regime_score({"line": "L2", "date": "2025-02-30"}, t, 30) == 0
    assert regime_score(None, t, 30) == 0 and regime_score(None, None, 30) == 1
    assert regime_score(t, None, 30) == 0


def test_category_case_insensitive():
    assert category_score(" beta", "Beta") == 1 and category_score("Alpha", "Beta") == 0


# --- aggregation -----------------------------------------------------------------------

def test_weights_and_sections():
    assert sum(WEIGHTS.values()) == pytest.approx(1)
    r = score_text(answer_text(C1_best_supplier="Alpha"), GT)
    assert r["sections"]["interpret"] < 1 and r["sections"]["describe"] == pytest.approx(1, abs=1e-3)
    assert r["total"] == pytest.approx(score_text(answer_text(), GT)["total"] - WEIGHTS["C1"], abs=1e-6)


def test_one_bad_field_costs_one_question():
    r = score_text(answer_text(A2_missing_humidity_batches="many"), GT)
    a2 = next(q for q in r["questions"] if q["qid"] == "A2")
    assert a2["score"] == 0 and "number" in a2["note"] and not r["format_ok"]
    assert r["total"] == pytest.approx(score_text(answer_text(), GT)["total"] - WEIGHTS["A2"], abs=1e-6)


def test_more_traps_avoided_never_scores_lower():
    """Replacing naive answers by correct ones one at a time never decreases the total."""
    ans, prev = naive(), score_text(json.dumps(naive()), GT)["total"]
    for key, value in perfect().items():
        ans[key] = value
        cur = score_text(json.dumps(ans), GT)["total"]
        assert cur >= prev - 1e-12
        prev = cur
    assert prev == pytest.approx(1.0)
