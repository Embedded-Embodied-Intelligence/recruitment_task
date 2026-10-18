"""The skill profile averages finished runs only and keeps every category's questions apart."""

from pathlib import Path

from edabench.profile import CATEGORIES, build

ROOT = Path(__file__).resolve().parents[1] / "outputs" / "runs"


def test_profile_covers_both_datasets_and_skips_unfinished_runs():
    p = build([ROOT / "v4_seed42", ROOT / "v5_seed42"])
    assert set(p["categories"]) == set(CATEGORIES)
    haiku = p["table"]["claude-haiku"]
    assert p["finished_runs"]["claude-haiku"] == 8  # 5 on v4, 3 of 5 on v5 (2 hit the turn limit)
    assert haiku["quiet"]["n"] == 3 and 0 <= haiku["quiet"]["mean"] <= 1
    assert haiku["loud"]["n"] == 5 * 6 + 3 * 5


def test_categories_do_not_share_a_question_within_a_version():
    for version in ("v4", "v5"):
        qids = [q for c in CATEGORIES.values() for q in c.get(version, [])]
        assert len(qids) == len(set(qids))
