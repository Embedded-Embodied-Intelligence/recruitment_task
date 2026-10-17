"""Model backends: send the task, let the model execute code, return its final reply.

Two backends cover the models available without a paid API:
- `openai_compatible`: any chat-completions API with tool calling (Gemini, Groq, ...).
  The model gets one tool, `run_python`, executed in `edabench.sandbox`.
- `claude_cli`: Claude Code in print mode (`claude -p`) on the operator's machine,
  which runs code with its own tools inside a scratch directory.

Both get the same task text plus a short, backend-specific note on how to run code, and
both return a `RunResult` with the final text and a full transcript for error analysis.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

from edabench.config import ModelSpec
from edabench.sandbox import PythonSandbox

RUN_PYTHON_TOOL = {
    "type": "function",
    "function": {
        "name": "run_python",
        "description": (
            "Execute Python code in a persistent session (variables survive between calls). "
            "The task files are in the current working directory. pandas, numpy, scipy, "
            "statsmodels and matplotlib are installed; there is no internet access. "
            "Returns stdout, the value of the last expression and any error."
        ),
        "parameters": {
            "type": "object",
            "properties": {"code": {"type": "string", "description": "Python code to execute"}},
            "required": ["code"],
        },
    },
}
API_NOTE = (
    "\n## Environment\n\nThe three files are in the current working directory. "
    "Execute Python with the `run_python` tool; variables persist between calls.\n"
)
CLI_NOTE = (
    "\n## Environment\n\nThe three files are in the current working directory. "
    "Execute Python with your tools (for example `python3 script.py`).\n"
)
FINAL_ANSWER_NUDGE = (
    "You have reached the limit of tool calls for this task. Reply now with your final "
    "answer in the required format, based on what you have found so far."
)


@dataclass
class RunResult:
    text: str
    transcript: list = field(default_factory=list)
    n_model_calls: int = 0
    n_tool_calls: int = 0
    usage: dict = field(default_factory=dict)
    duration_s: float = 0.0
    error: str | None = None
    hit_turn_limit: bool = False


# --- OpenAI-compatible APIs with our sandbox ---------------------------------------

def _elide_old_outputs(messages: list[dict], keep: int | None) -> list[dict]:
    """Copy of the conversation where all but the last `keep` tool outputs are elided."""
    if keep is None:
        return list(messages)
    tool_idx = [i for i, m in enumerate(messages) if m.get("role") == "tool"]
    old = set(tool_idx[:-keep] if keep else tool_idx)
    return [
        {**m, "content": "[earlier output elided to fit the context budget]"} if i in old else m
        for i, m in enumerate(messages)
    ]


def run_openai_compatible(spec: ModelSpec, prompt: str, files: list[Path], temperature: float,
                          client=None) -> RunResult:
    """Tool-calling loop. `client` can be injected for tests (an OpenAI-like object)."""
    if client is None:
        from openai import OpenAI

        key = os.environ.get(spec.api_key_env or "")
        if not key:
            raise RuntimeError(f"{spec.name}: set the {spec.api_key_env} environment variable")
        client = OpenAI(base_url=spec.base_url, api_key=key, max_retries=8, timeout=300)

    start, result = time.monotonic(), RunResult(text="")
    messages: list[dict] = [{"role": "user", "content": prompt + API_NOTE}]
    usage = {"prompt_tokens": 0, "completion_tokens": 0}
    with PythonSandbox(files, max_output_chars=spec.max_output_chars) as sandbox:
        for call in range(spec.max_turns + 1):
            last = call == spec.max_turns
            if last:
                messages.append({"role": "user", "content": FINAL_ANSWER_NUDGE})
                result.hit_turn_limit = True
            if call and spec.min_interval_s:
                time.sleep(spec.min_interval_s)
            try:
                resp = client.chat.completions.create(
                    model=spec.model_id,
                    messages=_elide_old_outputs(messages, spec.keep_tool_outputs),
                    temperature=temperature,
                    **({} if last else {"tools": [RUN_PYTHON_TOOL], "tool_choice": "auto"}),
                )
            except Exception as e:  # provider errors end the run; the log keeps the reason
                result.error = f"{type(e).__name__}: {e}"
                break
            result.n_model_calls += 1
            if resp.usage:
                for k in usage:
                    usage[k] += getattr(resp.usage, k, 0) or 0
            msg = resp.choices[0].message
            entry = {"role": "assistant", "content": msg.content or ""}
            if msg.tool_calls:
                entry["tool_calls"] = [
                    {"id": tc.id, "type": "function",
                     "function": {"name": tc.function.name, "arguments": tc.function.arguments}}
                    for tc in msg.tool_calls
                ]
            messages.append(entry)
            if not msg.tool_calls:
                result.text = msg.content or ""
                break
            for tc in msg.tool_calls:
                result.n_tool_calls += 1
                if tc.function.name != "run_python":
                    output = f"Error: unknown tool {tc.function.name!r}; the only tool is run_python."
                else:
                    try:
                        code = json.loads(tc.function.arguments)["code"]
                    except (json.JSONDecodeError, KeyError, TypeError):
                        output = 'Error: the arguments must be JSON like {"code": "print(1)"}.'
                    else:
                        output = sandbox.run(code).for_model()
                messages.append({"role": "tool", "tool_call_id": tc.id, "content": output})
    result.transcript, result.usage = messages, usage
    result.duration_s = round(time.monotonic() - start, 1)
    return result


# --- Claude Code in print mode ------------------------------------------------------
#
# Flags checked against Claude Code 2.1.302 (`claude --help`) and the docs at
# code.claude.com (cli-reference, headless, permission-modes, sandboxing), 2026-10-17.
#
# - The run uses the operator's claude.ai login (Pro). `--bare` is not used because it
#   only accepts ANTHROPIC_API_KEY, and the key is removed from the environment because
#   print mode prefers it over the login, which would bill the API instead of the plan.
# - `--safe-mode`, an empty MCP config, user settings left out and auto memory off keep
#   the operator's CLAUDE.md, memory, plugins, hooks and MCP servers out of the run.
# - Tools are Bash/Read/Write/Edit only; web tools are removed. `dontAsk` with
#   `--permission-prompts none` denies anything not pre-approved instead of waiting.
# - The OS sandbox blocks network for shell commands (and so for Python) and denies
#   reading the repository, where the answer key and the generator live; permission
#   deny rules do the same for the Read and Edit tools.

CLAUDE_TOOLS = "Bash,Read,Write,Edit"
# Any shell command is allowed: the sandbox, not a command list, is the boundary. Prefix
# rules such as `Bash(python3 *)` denied compound commands (`ls && head x.csv`), and in
# the first smoke run Haiku gave up after one denial instead of retrying with python3.
# Reads inside the working directory need no rule; `Edit(./**)` covers Write too and
# matches only the working directory (`./` is relative to it, `//` would be absolute).
CLAUDE_ALLOWED = ["Bash", "Edit(./**)"]
REPO_ROOT = Path(__file__).resolve().parents[1]
_INPUT_NAMES = {"batches.csv", "suppliers.csv", "maintenance.csv"}
_MAX_ARTIFACT_BYTES = 2_000_000


def _repo_paths_to_hide() -> list[str]:
    """Top-level repository entries, except the one holding the running Python (a venv)."""
    python = Path(sys.executable).absolute()
    return [str(p) for p in sorted(REPO_ROOT.iterdir()) if not python.is_relative_to(p)]


def claude_command(spec: ModelSpec, prompt: str, claude_bin: str = "claude",
                   hidden: tuple[Path, ...] = ()) -> list[str]:
    """`hidden`: more directories to keep out of reach, e.g. the answer key of the run."""
    # The sandbox's denyRead binds shell commands only; the Read tool needs deny rules.
    rules = ["//" + Path(d).absolute().as_posix().lstrip("/") + "/**" for d in (REPO_ROOT, *hidden)]
    settings = {
        "autoMemoryEnabled": False,
        "disableAllHooks": True,
        "permissions": {"deny": [f"{tool}({r})" for r in rules for tool in ("Read", "Edit")]},
    }
    if spec.cli_sandbox:
        settings["sandbox"] = {
            "enabled": True,
            "failIfUnavailable": True,
            "allowUnsandboxedCommands": False,
            "network": {"allowedDomains": []},
            "filesystem": {"denyRead": _repo_paths_to_hide() + [str(Path(d).absolute()) for d in hidden]},
        }
    cmd = [
        claude_bin, "-p", prompt,
        "--model", spec.model_id,
        "--output-format", "stream-json", "--verbose",
        "--max-turns", str(spec.max_turns),
        "--permission-mode", "dontAsk", "--permission-prompts", "none",
        "--tools", CLAUDE_TOOLS,
        "--allowedTools", *CLAUDE_ALLOWED,
        "--disallowedTools", "WebFetch", "WebSearch",
        "--safe-mode",
        "--strict-mcp-config", "--mcp-config", '{"mcpServers": {}}',
        "--setting-sources", "project",
        "--settings", json.dumps(settings),
        "--no-session-persistence",
    ]
    if spec.effort:
        cmd += ["--effort", spec.effort]
    return cmd


def claude_env() -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "CLAUDE_CODE_EFFORT_LEVEL", "ANTHROPIC_MODEL")}
    # `python3` in the run is the benchmark's own interpreter, with the pinned libraries.
    env["PATH"] = str(Path(sys.executable).parent) + os.pathsep + env.get("PATH", "")
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
    env["MPLBACKEND"] = "Agg"
    return env


def _parse_stream(stdout: str) -> tuple[list[dict], dict | None]:
    events = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            events.append({"type": "unparsed", "text": line})
    final = next((e for e in reversed(events) if e.get("type") == "result"), None)
    return events, final


def _tool_uses(events: list[dict]) -> list[dict]:
    uses = []
    for e in events:
        if e.get("type") != "assistant":
            continue
        for block in e.get("message", {}).get("content", []) or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                uses.append({"name": block.get("name"), "input": block.get("input", {})})
    return uses


def run_claude_cli(spec: ModelSpec, prompt: str, files: list[Path], artifacts_dir: Path | None = None,
                   claude_bin: str = "claude", hidden: tuple[Path, ...] = ()) -> RunResult:
    """One `claude -p` run in a scratch directory holding only the task files."""
    start, result = time.monotonic(), RunResult(text="")
    workdir = Path(tempfile.mkdtemp(prefix="edabench_claude_"))
    try:
        for f in files:
            shutil.copy(f, workdir / Path(f).name)
        try:
            proc = subprocess.run(
                claude_command(spec, prompt + CLI_NOTE, claude_bin, hidden), cwd=workdir, env=claude_env(),
                capture_output=True, text=True, timeout=spec.timeout_s, stdin=subprocess.DEVNULL,
            )
            stdout, stderr, code = proc.stdout, proc.stderr, proc.returncode
        except subprocess.TimeoutExpired as e:
            stdout = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
            stderr, code = f"timed out after {spec.timeout_s} s", None
        events, final = _parse_stream(stdout)
        uses = _tool_uses(events)
        result.transcript, result.n_tool_calls = events, len(uses)
        if final is not None:
            result.text = final.get("result") or ""
            result.n_model_calls = final.get("num_turns", 0)
            result.usage = {k: final.get(k) for k in ("usage", "modelUsage", "total_cost_usd", "duration_api_ms") if k in final}
            # A denied tool call is a harness problem, not the model's: the report flags it.
            result.usage["permission_denials"] = len(final.get("permission_denials") or [])
            subtype = final.get("subtype", "")
            result.hit_turn_limit = subtype == "error_max_turns"
            if final.get("is_error") and not result.hit_turn_limit:
                result.error = f"{subtype}: {result.text or final.get('errors')}"
        else:
            result.error = f"no result event (exit code {code}): {stderr.strip()[-2000:]}"
        if artifacts_dir is not None:
            _save_cli_artifacts(workdir, uses, artifacts_dir)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    result.duration_s = round(time.monotonic() - start, 1)
    return result


def _save_cli_artifacts(workdir: Path, uses: list[dict], out: Path) -> None:
    """Files the model wrote (scripts, tables) and every shell command it ran."""
    out.mkdir(parents=True, exist_ok=True)
    for f in sorted(workdir.rglob("*")):
        if f.is_file() and f.name not in _INPUT_NAMES and f.stat().st_size <= _MAX_ARTIFACT_BYTES:
            dest = out / f.relative_to(workdir)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(f, dest)
    commands = [u["input"].get("command", "") for u in uses if u["name"] == "Bash"]
    (out / "commands.sh").write_text("\n\n".join(commands) + "\n")


def save_api_artifacts(transcript: list[dict], out: Path) -> None:
    """Every `run_python` call of an API run as a numbered cell."""
    out.mkdir(parents=True, exist_ok=True)
    cells = []
    for m in transcript:
        for tc in m.get("tool_calls", []) or []:
            try:
                cells.append(json.loads(tc["function"]["arguments"])["code"])
            except (json.JSONDecodeError, KeyError, TypeError):
                cells.append(f"# unparsable arguments: {tc['function'].get('arguments')!r}")
    for i, code in enumerate(cells, 1):
        (out / f"cell_{i:02d}.py").write_text(code + "\n")


def run_model(spec: ModelSpec, prompt: str, files: list[Path], temperature: float,
              artifacts_dir: Path | None = None, hidden: tuple[Path, ...] = ()) -> RunResult:
    if spec.backend == "openai_compatible":
        result = run_openai_compatible(spec, prompt, files, temperature)
        if artifacts_dir is not None:
            save_api_artifacts(result.transcript, artifacts_dir)
        return result
    if spec.backend == "claude_cli":
        return run_claude_cli(spec, prompt, files, artifacts_dir, hidden=hidden)
    raise ValueError(f"{spec.name}: unknown backend {spec.backend!r}")
