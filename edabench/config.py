"""Load and validate the experiment config (configs/*.yaml)."""

from dataclasses import dataclass, field
from pathlib import Path

import yaml


@dataclass(frozen=True)
class ModelSpec:
    name: str        # label used in reports
    backend: str     # "openai_compatible" | "claude_cli"
    model_id: str    # exact model id sent to the provider (pinned, never "auto")
    base_url: str | None = None
    api_key_env: str | None = None  # env var holding the key; keys never live in the config
    effort: str | None = None       # claude_cli only: effort level passed to Claude Code
    max_turns: int = 40             # model calls per run, tool calls included
    # Free tiers limit tokens per minute, so a backend may need a smaller context:
    max_output_chars: int = 4000    # tool output shown to the model per call
    keep_tool_outputs: int | None = None  # older tool outputs are elided beyond this many
    min_interval_s: float = 0.0     # pause between requests (requests-per-minute limits)
    timeout_s: int = 3600           # wall-clock limit for one run
    cli_sandbox: bool = True        # claude_cli only: OS sandbox without network (not on native Windows)


@dataclass(frozen=True)
class BenchmarkConfig:
    seed: int
    n_runs: int
    temperature: float
    traps: dict[str, bool]
    n_batches: int = 3000
    models: list[ModelSpec] = field(default_factory=list)


def load_config(path: str | Path) -> BenchmarkConfig:
    raw = yaml.safe_load(Path(path).read_text())
    models = [ModelSpec(**m) for m in raw.get("models", [])]
    for m in models:
        if m.model_id == "auto":
            raise ValueError(f"{m.name}: model_id must be pinned, 'auto' breaks reproducibility")
    return BenchmarkConfig(
        seed=int(raw["seed"]),
        n_runs=int(raw["n_runs"]),
        temperature=float(raw["temperature"]),
        traps=dict(raw["traps"]),
        n_batches=int(raw.get("dataset", {}).get("n_batches", 3000)),
        models=models,
    )
