# Harness: running models on the task

The harness answers two questions the single pilots could not: how much a model's score
varies from run to run, and how models and prompt variants compare once that spread is
known. It runs each model N times on the same files, keeps every log and scores every
answer with `edabench.scorer`.

```
configs/benchmark.yaml -> runner (N runs per model x prompt variant) -> outputs/runs/... -> report
```

## 1. Two backends, one task

| | `claude_cli` | `openai_compatible` |
|---|---|---|
| Models | Claude Haiku / Sonnet / Opus 5.5 | Gemini 3.8 Flash (AI Studio), gpt-oss-120b (Groq) |
| Access | Claude Code `claude -p` on a Pro login | free API keys, from environment variables |
| Code execution | Claude Code's own tools (Bash, Read, Write, Edit) | one tool, `run_python`, executed by `edabench.sandbox` (a Jupyter kernel) |
| Isolation | OS sandbox: no network, the repository and the answer key unreadable | kernel without network, scratch directory with the three files |
| Turn limit | `--max-turns`; at the limit the run ends without an answer | at the limit the model is asked for its final answer without tools |

Both get `task/prompt.md` as rendered by `edabench.prompt` plus a two-line note on how to
run code, so the task text is identical across models. Neither gets `docs/`, `eval/` or
any file other than `batches.csv`, `suppliers.csv` and `maintenance.csv`.

### Why `claude -p` and not the Claude app

The pilots ran in the Claude app, which cannot be scripted, keeps no logs of the code and
mixes in the user's memory and preferences. `claude -p` runs the same models headless, on
the same Pro plan, with a pinned model id and effort and a full event log. The flags were
checked against Claude Code 2.1.302 and its documentation (see the comment block in
`edabench/backends.py`), and `python -m edabench.runner --check claude-haiku` verifies them
on the machine that runs the benchmark:

- `ANTHROPIC_API_KEY` is removed from the environment, because print mode prefers it over
  the login and would bill the API. `--bare` is not used for the same reason.
- `--safe-mode`, an empty MCP config, `--setting-sources project`, auto memory and hooks
  off: the operator's CLAUDE.md, memory, plugins and MCP servers stay out of the run.
- Tools are Bash, Read, Write and Edit; WebFetch and WebSearch are removed.
  `--permission-mode dontAsk --permission-prompts none` denies anything not pre-approved.
  Any shell command is pre-approved, because the sandbox is the boundary: in the first
  smoke run a command allowlist (`Bash(python3 *)`) denied `ls && head x.csv`, and Haiku
  stopped to ask for permission instead of retrying. Denied calls are counted in
  `metadata.json` and the report warns about them.
- The sandbox (`sandbox.enabled`, `failIfUnavailable`) blocks network for every shell
  command, so Python cannot download data or packages, and `denyRead` plus permission deny
  rules keep the repository and the run's answer key out of reach.
- `python3` resolves to the benchmark's virtual environment, so the model gets the
  pinned pandas, statsmodels and scipy.

The sandbox needs macOS, Linux or WSL2 (on Linux: `bubblewrap` and `socat`). On native
Windows set `cli_sandbox: false` for the Claude models and accept that their code then has
network access; the report should say so.

### Why our own sandbox for the free APIs

Free chat APIs only return text. The model gets one tool, `run_python`, which executes in a
Jupyter kernel started in a scratch directory with the three files. Variables persist
between calls like in the Claude app. Socket connections fail inside the kernel and proxy
variables point to a closed port, so pip and HTTP fail. Each call has a 120 s limit; a call
that ignores the interrupt restarts the kernel and the model is told its variables are
lost. Output is truncated (head and tail kept) before it reaches the model.

This sandbox is best-effort, not a security boundary: the code runs as the current user,
so a model that went looking could read files elsewhere on the disk. Run it on a machine
or container where that does not matter.

### Free-tier budgets

Groq's free tier for gpt-oss-120b allows about 8k tokens per minute and 200k per day, so
its config shows shorter tool outputs (`max_output_chars: 1500`), keeps only the last three
outputs in the context (`keep_tool_outputs: 3`) and pauses between calls. That is a real
handicap and the report must name it: a low score there can mean "ran out of context", not
"cannot do EDA". Gemini's free tier is limited by requests per minute (`min_interval_s: 7`).
The OpenAI client retries rate-limit errors with backoff; an error that survives the
retries stops that model and the next invocation resumes it.

## 2. Repeats, variants, resume

- **N runs** (`n_runs: 5` in the config, `--runs` on the command line). The score is a
  random variable: pilots 01 and 02 differed by one category answer (C1), worth 0.12.
- **Prompt variants** (`--variant`): `full` is the task as published; `no_quality_hint`
  removes the one line asking to check data quality. The difference measures how much a
  model cleans data unprompted, which is the skill the traps test.
- **Temperature** is 1.0 for the APIs (provider default; we measure typical behaviour).
  `claude -p` has no temperature flag and runs at Claude Code's default; metadata records
  `null` for it.
- **Resume.** A run is done once `score.json` exists. An infrastructure error (quota,
  rate limit, auth) writes `error.json`, stops that model and is retried on the next
  invocation. A model's own failure (no answer, broken JSON, turn limit) is scored like
  any other run, because it is part of what the benchmark measures.

## 3. What a run leaves behind

```
outputs/runs/v3_seed42/
    _data/                      the three files given to the model
    _ground_truth.json          answer key for this config (never given to the model)
    claude-sonnet/full/run_01/
        response.md             final reply, the only thing scored
        score.json              per-question scores, trap hits, total
        metadata.json           model id, effort, served model, prompt and data hashes,
                                usage, duration, library and Claude Code versions
        transcript.json         every message or stream event
        code/                   scripts the model wrote, commands.sh or cell_XX.py
    results.csv, summary.md, heatmap.png   from edabench.report
```

`metadata.json` stores `served_models` for Claude runs: the model that actually answered,
read from Claude Code's usage report, so a silent fallback would be visible.

## 4. Report

`python -m edabench.report outputs/runs/v3_seed42` writes:

- the total per model and variant: count, mean, sd, min, max, format compliance, tool calls;
- the mean and sd per question (and `heatmap.png`);
- how often each trap caught the model (answer closer to the naive answer than the truth);
- the most common wrong items in the set answers B1 and B2;
- the prompt-ablation effect per model and question;
- whether the ranking of models changes with equal question weights.

With 5 runs per cell, two models whose means differ by less than their run-to-run sd are
not ranked; the report shows the sd next to every mean for that reason.

## 5. Commands

```bash
python -m edabench.runner --check claude-haiku                    # isolation preflight, one short run
python -m edabench.runner --model claude-haiku claude-sonnet --variant full no_quality_hint --runs 5
python -m edabench.runner --model gemini-flash --runs 5           # needs GEMINI_API_KEY
python -m edabench.report outputs/runs/v3_seed42
```

The same as Makefile targets: `make check-claude`, `make bench MODELS="claude-haiku" RUNS=5`,
`make report`.
