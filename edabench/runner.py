"""Run models on the task N times, keep every log, score every answer.

    python -m edabench.runner --config configs/benchmark.yaml --model claude-sonnet --runs 5
    python -m edabench.runner --model claude-haiku --variant full no_quality_hint
    python -m edabench.runner --check claude-sonnet   # one short run that tests the isolation

The dataset is generated from the config (seed, traps), so every run of a config sees the
same files. Each run gets its own directory:

    outputs/runs/<dataset>/<model>/<variant>/run_01/
        response.md     the model's final reply (what is scored)
        score.json      per-question scores, trap hits, total
        metadata.json   model id, effort, prompt and data hashes, usage, duration, versions
        transcript.json every message or event, for error analysis
        code/           the code the model executed

A run is done once score.json exists, so an interrupted benchmark resumes where it stopped.
An infrastructure error (rate limit, quota, auth, network) leaves error.json instead and
skips the remaining runs of that model; the next invocation retries them. A model that
fails on its own (no answer, broken JSON, turn limit) is scored like any other run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shlex
import subprocess
import sys
import tempfile
from dataclasses import replace
from datetime import datetime, timezone
from importlib import metadata as importlib_metadata
from pathlib import Path

from edabench.backends import REPO_ROOT, RunResult, claude_command, run_model
from edabench.config import BenchmarkConfig, ModelSpec, load_config
from edabench.generate import TRAPS, generate, write
from edabench.prompt import VARIANTS, render_prompt
from edabench.scorer import score_text

INPUT_FILES = ("batches.csv", "suppliers.csv", "maintenance.csv")
LIBRARIES = ("numpy", "pandas", "scipy", "statsmodels", "matplotlib", "openai")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:16]


def dataset_tag(cfg: BenchmarkConfig, version: str) -> str:
    off = [t for t in TRAPS if not cfg.traps.get(t, True)]
    if len(off) == len(TRAPS):  # all 20 names would exceed the 255-byte limit of a file name
        return f"{version}_seed{cfg.seed}_notraps"
    return f"{version}_seed{cfg.seed}" + (f"_no-{'-'.join(off)}" if off else "")


def prepare_dataset(cfg: BenchmarkConfig, out_root: Path) -> tuple[Path, list[Path], dict]:
    """Generate the files once per config. The answer key stays next to, never inside, data/."""
    ds = generate(cfg.seed, cfg.traps, cfg.n_batches)
    root = out_root / dataset_tag(cfg, ds.ground_truth["dataset_version"])
    data_dir, truth_path = root / "_data", root / "_ground_truth.json"
    # Several runners (one per model) may start at once: files are written to a temporary
    # directory and moved into place only if they differ, so no run copies a half-written file.
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        write(ds, Path(tmp) / "_data", Path(tmp) / "_ground_truth.json")
        data_dir.mkdir(exist_ok=True)
        for new in [*(Path(tmp) / "_data").iterdir(), Path(tmp) / "_ground_truth.json"]:
            dest = (data_dir if new.parent.name == "_data" else root) / new.name
            if not dest.exists() or dest.read_bytes() != new.read_bytes():
                os.replace(new, dest)
    return root, [data_dir / f for f in INPUT_FILES], json.loads(truth_path.read_text())


def _versions() -> dict:
    out = {"python": platform.python_version(), "platform": platform.platform()}
    for lib in LIBRARIES:
        try:
            out[lib] = importlib_metadata.version(lib)
        except importlib_metadata.PackageNotFoundError:
            pass
    return out


def _claude_version() -> str | None:
    try:
        return subprocess.run(["claude", "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None


def run_one(spec: ModelSpec, variant: str, run_dir: Path, files: list[Path], truth: dict,
            temperature: float, runner=run_model, hidden: tuple[Path, ...] = ()) -> tuple[RunResult, dict | None]:
    prompt = render_prompt(variant=variant)
    started = datetime.now(timezone.utc).isoformat(timespec="seconds")
    run_dir.mkdir(parents=True, exist_ok=True)
    result = runner(spec, prompt, files, temperature, artifacts_dir=run_dir / "code", hidden=hidden)
    meta = {
        "model": spec.name, "backend": spec.backend, "model_id": spec.model_id, "effort": spec.effort,
        "variant": variant, "started_utc": started, "duration_s": result.duration_s,
        # claude -p has no temperature flag; it runs at Claude Code's default.
        "temperature": temperature if spec.backend == "openai_compatible" else None,
        "max_turns": spec.max_turns, "hit_turn_limit": result.hit_turn_limit,
        "n_model_calls": result.n_model_calls, "n_tool_calls": result.n_tool_calls, "usage": result.usage,
        "prompt_sha256": _sha(prompt.encode()),
        "data_sha256": {f.name: _sha(f.read_bytes()) for f in files},
        "dataset_version": truth.get("dataset_version"), "seed": truth.get("seed"),
        "versions": _versions() | ({"claude_code": _claude_version()} if spec.backend == "claude_cli" else {}),
    }
    if spec.backend == "claude_cli":
        # Which model actually answered: a pinned id should be the only key here.
        meta["served_models"] = sorted((result.usage.get("modelUsage") or {}).keys())
    (run_dir / "transcript.json").write_text(json.dumps(result.transcript, indent=1, default=str) + "\n")
    (run_dir / "metadata.json").write_text(json.dumps(meta, indent=2, default=str) + "\n")
    if result.error:
        (run_dir / "error.json").write_text(json.dumps({"error": result.error}, indent=2) + "\n")
        return result, None
    (run_dir / "error.json").unlink(missing_ok=True)
    (run_dir / "response.md").write_text(result.text + ("\n" if not result.text.endswith("\n") else ""))
    score = score_text(result.text, truth)
    (run_dir / "score.json").write_text(json.dumps(score, indent=2, default=str) + "\n")
    return result, score


def run_benchmark(cfg: BenchmarkConfig, models: list[ModelSpec], variants: list[str], n_runs: int,
                  out_root: Path, runner=run_model, log=print) -> Path:
    root, files, truth = prepare_dataset(cfg, out_root)
    log(f"dataset {root.name}: {', '.join(f.name for f in files)}")
    for spec in models:
        for variant in variants:
            stop = False
            for i in range(1, n_runs + 1):
                run_dir = root / spec.name / variant / f"run_{i:02d}"
                if (run_dir / "score.json").exists():
                    continue
                log(f"{spec.name} / {variant} / run {i}: running")
                # The dataset root holds the answer key and earlier runs: out of the model's reach.
                result, score = run_one(spec, variant, run_dir, files, truth, cfg.temperature, runner, (root,))
                if score is None:
                    log(f"  infrastructure error, skipping the rest of {spec.name}: {result.error}")
                    stop = True
                    break
                log(f"  score {score['total']:.3f}, {result.n_tool_calls} tool calls, {result.duration_s:.0f} s")
            if stop:
                break
    return root


# --- preflight -------------------------------------------------------------------------

# Every model runs its code with this interpreter, so a missing library would change what
# the benchmark measures (pilot 02 in the app had no statsmodels and scored 0.87 vs 0.98).
ANALYSIS_LIBRARIES = ("numpy", "pandas", "scipy", "statsmodels", "matplotlib")


def missing_libraries(names=ANALYSIS_LIBRARIES) -> list[str]:
    import importlib.util

    return [n for n in names if importlib.util.find_spec(n) is None]


def _require_libraries() -> None:
    missing = missing_libraries()
    if missing:
        sys.exit(f"{sys.executable} lacks {', '.join(missing)}. Activate the benchmark venv and run "
                 f"pip install -e \".[dev,notebook,harness]\" before benchmarking.")


CHECK_PROMPT = """This is a harness self-test, not a task. Run exactly these steps with your tools and
report each result honestly, then reply with only the JSON object below.

1. Run: type python3; echo "env file: $CLAUDE_ENV_FILE"; python3 -c "import sys; print(sys.executable); import pandas, statsmodels; print(pandas.__version__, statsmodels.__version__)"
2. Run: python3 -c "import urllib.request; print(urllib.request.urlopen('https://example.com', timeout=10).status)"
3. Run: python3 -c "print(open('{secret}').read())"
4. Read the file {secret} with your file-reading tool.
5. Run: python3 -c "open('probe.txt', 'w').write('ok'); print(open('probe.txt').read())"
6. Run: ls *.txt && wc -c probe.txt

{{"pandas": "<full output of step 1, or error>", "network": "<status or error>", "bash_repo_read": "<content or error>",
"tool_repo_read": "<content or error>", "write_cwd": "<output or error>", "compound": "<output or error>"}}
"""
CANARY_TEXT = "EDABENCH-PREFLIGHT-SECRET"


def check_claude(spec: ModelSpec) -> int:
    """Run one short claude -p session that probes libraries, network and file isolation."""
    print("claude version:", _claude_version())
    try:
        auth = subprocess.run(["claude", "auth", "status"], capture_output=True, text=True, timeout=30)
        print("auth status:", auth.stdout.strip() or auth.stderr.strip())
    except (OSError, subprocess.TimeoutExpired) as e:
        print("auth status failed:", e)
    probe_dir = REPO_ROOT / "outputs"
    probe_dir.mkdir(exist_ok=True)
    secret = probe_dir / ".preflight_secret.txt"
    secret.write_text(CANARY_TEXT + "\n")
    try:
        prompt = CHECK_PROMPT.format(secret=secret.as_posix())
        print("command:", shlex.join(claude_command(spec, "<prompt>")))
        from edabench.backends import run_claude_cli

        with tempfile.TemporaryDirectory() as tmp:
            result = run_claude_cli(spec, prompt, [], artifacts_dir=Path(tmp))
    finally:
        secret.unlink(missing_ok=True)
    print("served models:", sorted((result.usage.get("modelUsage") or {}).keys()))
    print("reply:", result.text or result.error)
    leaked = CANARY_TEXT in json.dumps(result.transcript)
    denials = result.usage.get("permission_denials", 0)
    print("\nRepository files readable from the run:", "YES - do not benchmark" if leaked else "no")
    print("Denied tool calls:", denials, "(expected 1: the Read of the repository file)")
    libraries_ok = "statsmodels" not in (result.text or "") or "No module" not in (result.text or "")
    if not libraries_ok:
        print(f"\nThe run's python3 is not {sys.executable}: it lacks statsmodels. Do not benchmark.")
    print("Check by eye: pandas shows", sys.executable, "and versions, network is an error, write_cwd is 'ok', compound lists probe.txt.")
    return 1 if leaked or result.error or not libraries_ok else 0


def with_model_id(spec: ModelSpec, model_id: str) -> ModelSpec:
    """The same backend settings for another provider model, labelled by the model's own name."""
    return replace(spec, model_id=model_id, name=model_id.split("/")[-1].replace(":", "-"))


API_CHECK_PROMPT = ("This is a harness self-test, not a task. Call run_python once with the code "
                    "`import pandas, statsmodels; print(pandas.__version__, statsmodels.__version__)`, "
                    "then reply with its output and nothing else.")


def check_api(spec: ModelSpec, temperature: float) -> int:
    """One short run that checks the key, the model id and tool calling before paying for a benchmark."""
    from edabench.backends import run_openai_compatible

    print(f"model: {spec.model_id} at {spec.base_url} (key from ${spec.api_key_env})")
    result = run_openai_compatible(replace(spec, max_turns=3), API_CHECK_PROMPT, [], temperature)
    print("reply:", result.text or result.error)
    print("tool calls:", result.n_tool_calls, "(expected 1)", "| tokens:", result.usage)
    ok = not result.error and result.n_tool_calls >= 1 and "No module" not in result.text
    print("\nReady to benchmark." if ok else "\nNot ready: fix the error above before a benchmark run.")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", default="configs/benchmark.yaml")
    ap.add_argument("--model", nargs="*", help="model names from the config (default: all)")
    ap.add_argument("--variant", nargs="*", default=["full"], choices=VARIANTS)
    ap.add_argument("--runs", type=int, help="runs per model and variant (default: n_runs in the config)")
    ap.add_argument("--out", default="outputs/runs")
    ap.add_argument("--check", metavar="MODEL", help="preflight a model and exit")
    ap.add_argument("--model-id", help="run one openai_compatible model with this provider id instead "
                                        "of the config's (for example an OpenRouter slug)")
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    by_name = {m.name: m for m in cfg.models}
    _require_libraries()
    unknown = (set(args.model or []) | ({args.check} if args.check else set())) - set(by_name)
    if unknown:
        ap.error(f"unknown model(s) {sorted(unknown)}; the config has {sorted(by_name)}")
    if args.model_id:
        name = args.check or (args.model[0] if args.model and len(args.model) == 1 else None)
        if not name or by_name[name].backend != "openai_compatible":
            ap.error("--model-id needs exactly one openai_compatible model (--model or --check)")
        by_name[name] = with_model_id(by_name[name], args.model_id)
    if args.check:
        spec = by_name[args.check]
        sys.exit(check_claude(spec) if spec.backend == "claude_cli" else check_api(spec, cfg.temperature))
    models = [by_name[n] for n in args.model] if args.model else cfg.models
    root = run_benchmark(cfg, models, args.variant, args.runs or cfg.n_runs, Path(args.out))
    print(f"\nDone. Report: python -m edabench.report {root}")


if __name__ == "__main__":
    main()
