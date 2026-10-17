"""The results explorer embeds every scored run and is safe against response text."""

import json
from pathlib import Path

from edabench.explorer import collect, render

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "outputs" / "runs" / "v4_seed42"


def test_explorer_embeds_every_scored_run():
    data = collect(RUNS)
    assert len(data["runs"]) == len(list(RUNS.glob("*/*/run_*/score.json")))
    assert data["findings"] and data["history"]
    page = render(data)
    assert page.startswith("<!doctype html>") and "<title>" in page


def test_response_text_cannot_close_the_script(tmp_path):
    run = tmp_path / "m" / "full" / "run_01"
    run.mkdir(parents=True)
    (run / "score.json").write_text(json.dumps({"total": 0.5, "sections": {}, "format_ok": True, "questions": []}))
    (run / "metadata.json").write_text("{}")
    (run / "response.md").write_text("</script><script>alert(1)</script>")
    page = render(collect(tmp_path), fragment=True)
    assert page.count("</script>") == 1
