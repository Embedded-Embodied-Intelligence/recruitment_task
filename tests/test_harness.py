"""The harness without real models: a scripted API client, a fake `claude` binary and a
fake backend drive the tool loop, the CLI wrapper, the runner and the report."""

import json
import os
import stat
import sys
from pathlib import Path
from types import SimpleNamespace as NS

import pytest

pytest.importorskip("jupyter_client")
pytest.importorskip("ipykernel")

from edabench import backends, report, runner
from edabench.answer import ANSWER_KEYS
from edabench.backends import RunResult, _elide_old_outputs, claude_command, run_claude_cli, run_openai_compatible
from edabench.config import BenchmarkConfig, ModelSpec
from edabench.prompt import QUALITY_HINT, render_prompt
from edabench.sandbox import PythonSandbox

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / "data" / f for f in runner.INPUT_FILES]


def perfect_answer(truth: dict) -> str:
    obj = {ANSWER_KEYS[q]: spec["truth"] for q, spec in truth["questions"].items()}
    return "Done.\n\n```json\n" + json.dumps(obj) + "\n```\n"


# --- OpenAI-compatible tool loop ---------------------------------------------------------

def _tool_call(i, code=None, args=None, name="run_python"):
    arguments = args if args is not None else json.dumps({"code": code})
    return NS(id=f"call_{i}", function=NS(name=name, arguments=arguments))


def _response(content="", tool_calls=None):
    msg = NS(content=content, tool_calls=tool_calls)
    return NS(choices=[NS(message=msg)], usage=NS(prompt_tokens=10, completion_tokens=5))


class ScriptedClient:
    def __init__(self, responses):
        self.responses, self.calls = list(responses), []
        self.chat = NS(completions=NS(create=self._create))

    def _create(self, **kwargs):
        self.calls.append(kwargs)
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def api_spec(**kw):
    return ModelSpec(name="fake", backend="openai_compatible", model_id="fake-1", **kw)


def test_tool_loop_executes_code_and_returns_the_final_text():
    client = ScriptedClient([
        _response(tool_calls=[_tool_call(1, "import pandas as pd\ndf = pd.read_csv('batches.csv')\nprint(len(df))")]),
        _response(tool_calls=[_tool_call(2, args="not json"), _tool_call(3, "x", name="shell")]),
        _response(tool_calls=[_tool_call(4, "print(df.shape[1] > 5)")]),
        _response(content="final answer"),
    ])
    r = run_openai_compatible(api_spec(), "task", FILES, 1.0, client=client)
    tool_outputs = [m["content"] for m in r.transcript if m["role"] == "tool"]
    assert r.text == "final answer" and r.error is None and not r.hit_turn_limit
    assert tool_outputs[0].strip() == "3060"                 # the published rows, duplicates included
    assert "must be JSON" in tool_outputs[1] and "unknown tool" in tool_outputs[2]
    assert tool_outputs[3].strip() == "True"                 # state persists between calls
    assert (r.n_model_calls, r.n_tool_calls) == (4, 4)
    assert r.usage == {"prompt_tokens": 40, "completion_tokens": 20}
    assert all(c["model"] == "fake-1" and c["temperature"] == 1.0 for c in client.calls)


def test_turn_limit_forces_an_answer_without_tools():
    looping = [_response(tool_calls=[_tool_call(i, "1")]) for i in range(2)]
    client = ScriptedClient([*looping, _response(content="forced answer")])
    r = run_openai_compatible(api_spec(max_turns=2), "task", FILES, 1.0, client=client)
    assert r.text == "forced answer" and r.hit_turn_limit
    assert "tools" not in client.calls[-1] and "tools" in client.calls[0]
    assert client.calls[-1]["messages"][-1]["content"] == backends.FINAL_ANSWER_NUDGE


def test_provider_error_is_reported_not_raised():
    r = run_openai_compatible(api_spec(), "task", FILES, 1.0, client=ScriptedClient([RuntimeError("429 quota")]))
    assert r.error == "RuntimeError: 429 quota" and r.text == ""


def test_old_tool_outputs_are_elided_for_small_context_budgets():
    msgs = [{"role": "user", "content": "q"}] + [{"role": "tool", "content": f"out{i}"} for i in range(4)]
    kept = [m["content"] for m in _elide_old_outputs(msgs, 2)]
    assert kept[1].startswith("[earlier output elided") and kept[3:] == ["out2", "out3"]
    assert _elide_old_outputs(msgs, None) == msgs


def test_sandbox_blocks_network_and_survives_timeouts():
    with PythonSandbox(FILES[:1], timeout_s=3) as sb:
        net = sb.run("import urllib.request\nurllib.request.urlopen('https://example.com', timeout=5)")
        assert net.error and ("network access is disabled" in net.error or "URLError" in net.error)
        sb.run("x = 42")
        slow = sb.run("import time\ntime.sleep(30)")
        assert slow.timed_out
        assert sb.run("print('alive', x)").output.strip() == "alive 42"


# --- claude -p wrapper ---------------------------------------------------------------

FAKE_CLAUDE = r'''#!{python}
import json, os, sys
args = sys.argv[1:]
assert "ANTHROPIC_API_KEY" not in os.environ
open("analysis.py", "w").write("print('hi')\n")
events = [
    {{"type": "system", "subtype": "init", "args": args}},
    {{"type": "assistant", "message": {{"content": [{{"type": "tool_use", "name": "Bash",
        "input": {{"command": "python3 analysis.py"}}}}]}}}},
    {{"type": "result", "subtype": "{subtype}", "is_error": {is_error}, "result": "the answer",
      "num_turns": 3, "usage": {{"output_tokens": 7}}, "modelUsage": {{"claude-haiku-5-5": {{}}}},
      "permission_denials": [{{"tool_name": "Read"}}]}},
]
print("\n".join(json.dumps(e) for e in events))
'''


def fake_claude(tmp_path, subtype="success", is_error=False):
    path = tmp_path / "claude"
    path.write_text(FAKE_CLAUDE.format(python=sys.executable, subtype=subtype, is_error=is_error))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


def cli_spec(**kw):
    return ModelSpec(name="haiku", backend="claude_cli", model_id="claude-haiku-5-5", effort="medium", **kw)


def test_claude_command_isolates_the_run():
    cmd = claude_command(cli_spec(), "PROMPT")
    assert cmd[:3] == ["claude", "-p", "PROMPT"]
    for flag in ("--safe-mode", "--strict-mcp-config", "--no-session-persistence"):
        assert flag in cmd
    assert cmd[cmd.index("--model") + 1] == "claude-haiku-5-5"
    assert cmd[cmd.index("--effort") + 1] == "medium"
    assert cmd[cmd.index("--permission-mode") + 1] == "dontAsk"
    assert "WebFetch" in cmd and "WebSearch" in cmd and "--bare" not in cmd
    assert cmd[cmd.index("--allowedTools") + 1] == "Bash"      # the sandbox is the boundary
    settings = json.loads(cmd[cmd.index("--settings") + 1])
    assert settings["sandbox"]["enabled"] and settings["sandbox"]["network"]["allowedDomains"] == []
    hidden = settings["sandbox"]["filesystem"]["denyRead"]
    assert str(ROOT / "eval") in hidden and str(ROOT / "edabench") in hidden
    deny = settings["permissions"]["deny"]
    assert f"Read(//{(ROOT / 'eval').as_posix().lstrip('/')}/**)" in deny
    assert f"Edit(//{ROOT.as_posix().lstrip('/')}/**)" in deny
    # Read rules also bind the sandbox, so they must spare the interpreter's venv (macOS).
    assert not any(r.startswith("Read(") and Path(sys.executable).absolute().as_posix().startswith(
        "/" + r[len("Read(//"):].removesuffix(")").removesuffix("/**")) for r in deny)
    extra = claude_command(cli_spec(), "P", hidden=(Path("/tmp/key"),))
    extra_settings = json.loads(extra[extra.index("--settings") + 1])
    assert "/tmp/key" in extra_settings["sandbox"]["filesystem"]["denyRead"]
    assert "Read(//tmp/key/**)" in extra_settings["permissions"]["deny"]
    plain = claude_command(cli_spec(cli_sandbox=False), "P")
    assert "sandbox" not in json.loads(plain[plain.index("--settings") + 1])


def test_claude_cli_run_collects_answer_usage_and_code(tmp_path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "must-not-leak")
    r = run_claude_cli(cli_spec(), "task", FILES, tmp_path / "code", claude_bin=fake_claude(tmp_path))
    assert r.text == "the answer" and r.error is None
    assert (r.n_model_calls, r.n_tool_calls) == (3, 1)
    assert list(r.usage["modelUsage"]) == ["claude-haiku-5-5"] and r.usage["permission_denials"] == 1
    assert (tmp_path / "code" / "analysis.py").exists()
    assert "python3 analysis.py" in (tmp_path / "code" / "commands.sh").read_text()
    assert not (tmp_path / "code" / "batches.csv").exists()


def test_claude_cli_turn_limit_is_a_model_failure_and_quota_is_an_error(tmp_path):
    r = run_claude_cli(cli_spec(), "t", [], claude_bin=fake_claude(tmp_path, "error_max_turns", True))
    assert r.hit_turn_limit and r.error is None
    r = run_claude_cli(cli_spec(), "t", [], claude_bin=fake_claude(tmp_path, "error_during_execution", True))
    assert r.error and not r.hit_turn_limit


# --- runner and report -------------------------------------------------------------

def test_runner_scores_resumes_and_reports(tmp_path):
    cfg = BenchmarkConfig(seed=42, n_runs=2, temperature=1.0, traps={})
    good, broken = api_spec(), ModelSpec(name="broken", backend="openai_compatible", model_id="x")
    calls = []

    def fake_backend(spec, prompt, files, temperature, artifacts_dir=None, hidden=()):
        calls.append((spec.name, "check data quality" in prompt.lower()))
        assert hidden == (files[0].parent.parent,)              # the answer key's directory
        if spec.name == "broken":
            return RunResult(text="", error="RateLimitError: 429")
        truth = json.loads((files[0].parent.parent / "_ground_truth.json").read_text())
        return RunResult(text=perfect_answer(truth), n_tool_calls=3, duration_s=1.0)

    root = runner.run_benchmark(cfg, [good, broken], ["full", "no_quality_hint"], 2, tmp_path, fake_backend, log=lambda *_: None)
    assert root.name == "v4_seed42"
    assert not any("ground_truth" in f.name for f in (root / "_data").iterdir())
    assert calls == [("fake", True), ("fake", True), ("fake", False), ("fake", False), ("broken", True)]
    score = json.loads((root / "fake" / "full" / "run_01" / "score.json").read_text())
    assert score["total"] == 1.0
    assert (root / "broken" / "full" / "run_01" / "error.json").exists()

    calls.clear()
    runner.run_benchmark(cfg, [good, broken], ["full"], 2, tmp_path, fake_backend, log=lambda *_: None)
    assert calls == [("broken", True)]                      # finished runs are not repeated

    report.main([str(root)])
    summary = (root / "summary.md").read_text()
    assert "| fake | full | 2 | 1.000" in summary and "Prompt ablation" in summary
    assert (root / "heatmap.png").stat().st_size > 0
    assert len(__import__("pandas").read_csv(root / "results.csv")) == 4


def test_prompt_variant_drops_only_the_quality_hint():
    full, ablated = render_prompt(), render_prompt(variant="no_quality_hint")
    assert QUALITY_HINT in full and QUALITY_HINT not in ablated
    assert len(full) - len(ablated) == len(QUALITY_HINT)
    with pytest.raises(ValueError):
        render_prompt(variant="nope")


def test_missing_analysis_library_stops_the_runner(monkeypatch):
    from edabench import runner

    assert runner.missing_libraries() == []
    assert runner.missing_libraries(("pandas", "no_such_library_xyz")) == ["no_such_library_xyz"]
    monkeypatch.setattr(runner, "missing_libraries", lambda: ["statsmodels"])
    with pytest.raises(SystemExit, match="statsmodels"):
        runner.main(["--check", "claude-haiku"])
