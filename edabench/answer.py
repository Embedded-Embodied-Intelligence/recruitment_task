"""Extract and validate the model's final JSON answer.

Extraction is deliberately strict about *where* the answer is (the last ```json block,
falling back to the last top-level JSON object) and tolerant about *how* it is written
(key order, int written as 3000.0). Field-level problems never fail the whole answer:
each invalid field is reported and later scored 0, so one typo costs one question.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

ANSWER_KEYS = {
    "A1": "A1_unique_batches",
    "A2": "A2_missing_humidity_batches",
    "A3": "A3_overall_defect_rate",
    "A4": "A4_median_mold_temp_c",
    "B1": "B1_direct_drivers",
    "B2": "B2_leakage_columns",
    "B3": "B3_regime_change",
    "C1": "C1_best_supplier",
    "C2": "C2_optimal_humidity_pct",
}
B1_CANDIDATES = {"mold_temp", "humidity_pct", "cycle_time_s", "machine_age_years", "ambient_temp_c", "operator_id", "shift"}

_JSON_BLOCK = re.compile(r"```json\s*(\{.*?\})\s*```", re.DOTALL | re.IGNORECASE)


@dataclass
class ParsedAnswer:
    values: dict[str, object] = field(default_factory=dict)  # question id -> normalized value
    errors: dict[str, str] = field(default_factory=dict)     # question id (or "_") -> problem
    warnings: dict[str, str] = field(default_factory=dict)   # accepted but suspicious

    @property
    def ok(self) -> bool:
        return not self.errors


def extract_json(text: str) -> dict | None:
    """Return the last ```json block, else the last balanced {...} that parses."""
    blocks = _JSON_BLOCK.findall(text)
    for candidate in reversed(blocks):
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    for start in reversed([m.start() for m in re.finditer(r"\{", text)]):
        depth = 0
        for end in range(start, len(text)):
            depth += {"{": 1, "}": -1}.get(text[end], 0)
            if depth == 0:
                try:
                    obj = json.loads(text[start:end + 1])
                except json.JSONDecodeError:
                    break
                if isinstance(obj, dict) and set(ANSWER_KEYS.values()) & set(obj):
                    return obj
                break
    return None


def _number(v, integer: bool = False):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise ValueError(f"expected a number, got {v!r}")
    if integer:
        if float(v) != int(v):
            raise ValueError(f"expected an integer, got {v!r}")
        return int(v)
    return float(v)


def _str_list(v):
    if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
        raise ValueError(f"expected a list of strings, got {v!r}")
    return sorted({x.strip() for x in v})


def _regime(v):
    if v is None:
        return None
    if not isinstance(v, dict) or not {"line", "date"} <= set(v):
        raise ValueError(f"expected {{'line', 'date'}} or null, got {v!r}")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(v["date"]).strip()):
        raise ValueError(f"date must be YYYY-MM-DD, got {v['date']!r}")
    return {"line": str(v["line"]).strip().upper(), "date": str(v["date"]).strip()}


def _text(v):
    if not isinstance(v, str):
        raise ValueError(f"expected a string, got {v!r}")
    return v.strip()


_VALIDATORS = {
    "A1": lambda v: _number(v, integer=True),
    "A2": lambda v: _number(v, integer=True),
    "A3": _number,
    "A4": _number,
    "B1": _str_list,
    "B2": _str_list,
    "B3": _regime,
    "C1": _text,
    "C2": _number,
}


def parse_answer(text: str) -> ParsedAnswer:
    out = ParsedAnswer()
    obj = extract_json(text)
    if obj is None:
        out.errors["_"] = "no JSON answer found"
        return out
    for qid, key in ANSWER_KEYS.items():
        if key not in obj:
            out.errors[qid] = f"missing key {key}"
            continue
        try:
            out.values[qid] = _VALIDATORS[qid](obj[key])
        except ValueError as e:
            out.errors[qid] = str(e)
    # Unknown names are kept: the set metric counts them as false positives instead of
    # zeroing the whole question for one misspelt name.
    if "B1" in out.values and not set(out.values["B1"]) <= B1_CANDIDATES:
        out.warnings["B1"] = f"names outside the candidate list: {sorted(set(out.values['B1']) - B1_CANDIDATES)}"
    return out
