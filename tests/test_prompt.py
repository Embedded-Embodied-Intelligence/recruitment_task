"""Prompt and answer-format tests: the prompt and the parser agree, and parsing is robust."""

import json
import re
from pathlib import Path

import pytest

from edabench.answer import ANSWER_KEYS, B1_CANDIDATES, extract_json, parse_answer
from edabench.generate import CANARY, COLUMNS, MAINTENANCE_COLUMNS, SUPPLIERS
from edabench.prompt import PROMPT_PATH, render_prompt

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = (ROOT / "reference" / "reference_answer.json").read_text()


def test_rendered_prompt_has_no_canary_or_comments():
    text = render_prompt()
    assert CANARY not in text and "<!--" not in text
    assert CANARY in PROMPT_PATH.read_text()  # the source file still carries it


def test_prompt_lists_every_answer_key_and_the_b1_candidates():
    text = render_prompt()
    for key in ANSWER_KEYS.values():
        assert f'"{key}"' in text
    b1 = re.search(r"\*\*B1\.\*\*(.*?)\n", text).group(1)
    assert set(re.findall(r"`([a-z_]+)`", b1)) == B1_CANDIDATES


def test_prompt_never_names_a_trap_answer():
    text = render_prompt().lower()
    for leak in (
        "fahrenheit", "°f", "-1", "duplicate", "rework_cost", "qc_inspection", "beta", "l2", "simpson",
        "sensor", "drift", "calibrat", "offset", "interaction", "pre_dried", "july", "august", "summer", "holiday",
    ):
        assert leak not in text, leak


def test_prompt_only_mentions_existing_columns():
    named = set(re.findall(r"`([a-z_]+)`", render_prompt())) - {"null"}
    assert named <= set(COLUMNS) | set(SUPPLIERS) | set(MAINTENANCE_COLUMNS) | {"batches", "suppliers", "maintenance"}


def test_reference_answer_parses_cleanly():
    parsed = parse_answer(f"Some reasoning.\n```json\n{REFERENCE}```")
    assert parsed.ok and not parsed.warnings and len(parsed.values) == len(ANSWER_KEYS)


def test_last_json_block_wins():
    draft = '```json\n{"A1_unique_batches": 1}\n```'
    final = '```json\n{"A1_unique_batches": 3000}\n```'
    assert extract_json(f"{draft}\nOn reflection:\n{final}")["A1_unique_batches"] == 3000


def test_bare_json_without_fence_is_found():
    body = json.dumps({"A1_unique_batches": 3000, "C1_best_supplier": "Beta"})
    assert extract_json(f"Final answer: {body} Thanks!")["C1_best_supplier"] == "Beta"


def test_field_errors_are_isolated():
    ans = json.loads(REFERENCE)
    ans["A1_unique_batches"] = "about 3000"
    ans["B3_regime_change"] = {"line": "l2", "date": "16/06/2025"}
    del ans["C2_optimal_humidity_pct"]
    parsed = parse_answer(json.dumps(ans))
    assert set(parsed.errors) == {"A1", "B3", "C2"}
    assert parsed.values["C1"] == "Beta"


def test_normalization():
    ans = json.loads(REFERENCE)
    ans |= {"A1_unique_batches": 3000.0, "B3_regime_change": {"line": " l2 ", "date": "2025-06-16"},
            "B1_direct_drivers": ["shift", "mold_temp", "shift", "humidity"]}
    parsed = parse_answer(json.dumps(ans))
    assert parsed.values["A1"] == 3000 and parsed.values["B3"]["line"] == "L2"
    assert parsed.values["B1"] == ["humidity", "mold_temp", "shift"] and "B1" in parsed.warnings


@pytest.mark.parametrize("text", ["", "no json here", "```json\n{not json}\n```"])
def test_missing_answer(text):
    assert parse_answer(text).errors == {"_": "no JSON answer found"}
