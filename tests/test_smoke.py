"""Smoke test: the package imports and the shipped config is valid."""

from pathlib import Path

import pytest

import edabench
from edabench.config import load_config

ROOT = Path(__file__).resolve().parents[1]


def test_package_imports():
    assert edabench.__version__


def test_default_config_loads():
    cfg = load_config(ROOT / "configs" / "benchmark.yaml")
    assert cfg.n_runs >= 1
    assert all(m.model_id != "auto" for m in cfg.models)


def test_auto_model_is_rejected(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text(
        "seed: 1\nn_runs: 1\ntemperature: 0\ntraps: {}\n"
        "models: [{name: x, backend: openai_compatible, model_id: auto}]\n"
    )
    with pytest.raises(ValueError):
        load_config(bad)
