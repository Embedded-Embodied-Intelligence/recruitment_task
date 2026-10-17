"""Generator tests: reproducibility, trap injection, ablation switches and DGP sanity.

The DGP checks re-run the analysis a careful analyst would do, so they also prove the
planted effects are detectable in the published data (construct validity).
"""

import json

import numpy as np
import pandas as pd
import pytest

from edabench.generate import CANARY, TRAPS, generate, resolve_traps, write

SEED = 42


@pytest.fixture(scope="module")
def full():
    return generate(SEED)


@pytest.fixture(scope="module")
def clean():
    return generate(SEED, {t: False for t in TRAPS})


def reference_clean(df: pd.DataFrame, suppliers: pd.DataFrame) -> pd.DataFrame:
    """The cleaning a careful analyst should do; mirrors the traps in docs/task_design.md."""
    df = df.drop_duplicates().copy()
    df["shift"] = df["shift"].str.strip().str[0].str.upper().map({"D": "Day", "N": "Night"})
    df["supplier_code"] = df["supplier_code"].str.strip().str.upper()
    df = df.merge(suppliers, on="supplier_code", how="left", validate="many_to_one")
    df["humidity_pct"] = df["humidity_pct"].where(df["humidity_pct"] >= 0)
    df["mold_temp"] = df["mold_temp"].where(df["mold_temp"] > 0)
    f = df["line"] == "L3"
    df.loc[f, "mold_temp"] = (df.loc[f, "mold_temp"] - 32) * 5 / 9
    df["rate"] = df["defective_units"] / df["units_produced"]
    return df


def pooled(g: pd.DataFrame) -> float:
    return g["defective_units"].sum() / g["units_produced"].sum()


# --- reproducibility -------------------------------------------------------------

def test_same_seed_same_bytes(tmp_path):
    for name in ("a", "b"):
        write(generate(SEED), tmp_path / name, tmp_path / name / "gt.json")
    for f in ("batches.csv", "suppliers.csv", "gt.json"):
        assert (tmp_path / "a" / f).read_bytes() == (tmp_path / "b" / f).read_bytes()


def test_different_seed_differs(full):
    assert not full.batches.equals(generate(SEED + 1).batches)


def test_unknown_trap_rejected():
    with pytest.raises(ValueError):
        resolve_traps({"duplicate": False})


def test_canary_everywhere(tmp_path, full):
    write(full, tmp_path / "data", tmp_path / "gt.json")
    assert CANARY in (tmp_path / "data" / "CANARY.txt").read_text()
    assert json.loads((tmp_path / "gt.json").read_text())["canary"] == CANARY


# --- trap injection --------------------------------------------------------------

def test_t1_duplicates(full, clean):
    gt = full.ground_truth["questions"]["A1"]
    assert full.batches.duplicated().sum() == gt["naive"] - gt["truth"] > 0
    assert full.batches["batch_id"].nunique() == gt["truth"]
    assert clean.batches.duplicated().sum() == 0


def test_t2_hidden_missing(full, clean):
    hum, mold = full.batches["humidity_pct"], full.batches["mold_temp"]
    assert (hum == -1).sum() > hum.isna().sum() > 0
    assert (mold == 0).sum() > 0
    assert (clean.batches["humidity_pct"] < 0).sum() == 0
    assert (clean.batches["mold_temp"] == 0).sum() == 0


def test_t3_mixed_units(full, clean):
    by_line = full.batches.query("mold_temp > 0").groupby("line")["mold_temp"].median()
    assert by_line["L3"] > 380 and by_line.drop("L3").between(195, 225).all()
    assert clean.batches.groupby("line")["mold_temp"].median().between(195, 225).all()


def test_t4_inconsistent_labels(full, clean):
    assert full.batches["shift"].nunique() > 2
    assert full.batches["supplier_code"].nunique() > 3
    assert set(clean.batches["shift"]) == {"Day", "Night"}
    assert set(clean.batches["supplier_code"]) == {"SP-01", "SP-02", "SP-03"}


def test_t8_leakage_columns(full, clean):
    df = reference_clean(full.batches, full.suppliers)
    assert df["rework_cost_eur"].corr(df["defective_units"]) > 0.95
    assert "rework_cost_eur" not in clean.batches and "qc_inspection_min" not in clean.batches


def test_ablation_changes_only_the_switched_trap(full):
    no_dups = generate(SEED, {"duplicates": False})
    dedup = full.batches.drop_duplicates().sort_values("batch_id").reset_index(drop=True)
    pd.testing.assert_frame_equal(dedup, no_dups.batches)


# --- planted effects are real and detectable ---------------------------------------

def test_t5_pooled_differs_from_mean(full):
    a3 = full.ground_truth["questions"]["A3"]
    assert abs(a3["naive"] - a3["truth"]) > 0.002


def test_t6_humidity_u_shape_invisible_to_pearson(full):
    df = reference_clean(full.batches, full.suppliers).dropna(subset=["humidity_pct"])
    assert abs(df["rate"].corr(df["humidity_pct"])) < 0.1
    bins = df.groupby(pd.cut(df["humidity_pct"], [15, 25, 40, 50, 65, 75]), observed=True).apply(pooled)
    assert bins.iloc[2] < bins.iloc[0] and bins.iloc[2] < bins.iloc[-1]


def test_t7_confounder_correlates_but_has_no_direct_effect(full):
    df = reference_clean(full.batches, full.suppliers).dropna()
    assert df["rate"].corr(df["machine_age_years"]) > 0.2
    t = _ols_t(df)
    assert abs(t["machine_age_years"]) < 2.5 and abs(t["ambient_temp_c"]) < 2.5
    assert min(abs(t["mold_temp"]), abs(t["cycle_time_s"]), abs(t["night"]), abs(t["hum_sq"])) > 4


def test_t9_simpson_reversal(full):
    df = reference_clean(full.batches, full.suppliers)
    overall = df.groupby("supplier_name").apply(pooled)
    assert overall.idxmax() == "Beta"
    within = df.groupby(["line", "supplier_name"]).apply(pooled).unstack()
    assert (within.idxmin(axis=1) == "Beta").all()


def test_t10_regime_change(full, clean):
    df = reference_clean(full.batches, full.suppliers).query("line == 'L2'")
    after = df["production_date"] >= "2025-06-16"
    assert pooled(df[after]) > 1.3 * pooled(df[~after])
    assert clean.ground_truth["questions"]["B3"]["truth"] is None


def _ols_t(df: pd.DataFrame) -> pd.Series:
    """t-statistics of an OLS on the empirical logit, controlling for line and supplier."""
    X = pd.get_dummies(df[["line", "supplier_name"]], drop_first=True).astype(float)
    X["night"] = (df["shift"] == "Night").astype(float)
    for c in ("mold_temp", "cycle_time_s", "machine_age_years", "ambient_temp_c"):
        X[c] = df[c]
    X["hum_sq"] = (df["humidity_pct"] - 45) ** 2
    X["regime"] = ((df["line"] == "L2") & (df["production_date"] >= "2025-06-16")).astype(float)
    X.insert(0, "const", 1.0)
    r = df["rate"].clip(1e-4, 1 - 1e-4)
    y = np.log(r / (1 - r))
    A = X.to_numpy()
    beta, *_ = np.linalg.lstsq(A, y.to_numpy(), rcond=None)
    resid = y.to_numpy() - A @ beta
    se = np.sqrt(np.diag(np.linalg.inv(A.T @ A)) * resid.var(ddof=A.shape[1]))
    return pd.Series(beta / se, index=X.columns)
