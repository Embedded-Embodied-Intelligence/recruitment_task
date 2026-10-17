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


@dataclass(frozen=True)
class BenchmarkConfig:
    seed: int
    n_runs: int
    temperature: float
    traps: dict[str, bool]
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
        models=models,
    )
