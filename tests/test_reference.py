"""The expert method recovers the planted answers on many seeds, not just on seed 42.

This protects the answer key against a lucky seed: if a question's truth were only
reachable by chance, a fair model could lose points that no analyst could earn.
"""

import numpy as np
import pandas as pd
import pytest
import statsmodels.formula.api as smf

from edabench.generate import CLEANING_PLAN_DAYS, DIRECT_DRIVERS, DRIFT_C, HUMIDITY_OPT_ALPHA, generate
from tests.test_generate import cleaned, qc_change, reference_clean, sensor_offset

HUMIDITY = "C(supplier_name):humidity_pct + C(supplier_name):I(humidity_pct**2)"
FORMULA = (
    f"y ~ C(line) + C(supplier_name) + C(shift) + mold_temp + {HUMIDITY}"
    " + cycle_time_s + machine_age_years + ambient_temp_c + regime + qc_change + days_since_cleaning"
)
SEEDS = range(42, 52)


def model_frame(seed: int) -> tuple[pd.DataFrame, dict]:
    ds = generate(seed)
    df = cleaned(ds).dropna(subset=["mold_temp", "humidity_pct"])
    df["regime"] = ((df["line"] == "L2") & (df["production_date"] >= "2025-06-16")).astype(int)
    d, n = df["defective_units"], df["units_produced"]
    df["y"] = np.log((d + 0.5) / (n - d + 0.5))
    return df, ds.ground_truth["questions"]


def expected_rate(fit, df: pd.DataFrame, **changes) -> float:
    """Pooled defect rate predicted by the fitted model after changing some columns."""
    p = 1 / (1 + np.exp(-fit.predict(df.assign(**changes))))
    return float((p * df["units_produced"]).sum() / df["units_produced"].sum())


@pytest.mark.parametrize("seed", SEEDS)
def test_reference_recovers_drivers_supplier_optimum_and_cleaning(seed):
    every, q = model_frame(seed)
    df = every[~every["cleaning_unlogged"]]  # T20: the days since cleaning are unknown in the log gap
    full = smf.ols(FORMULA, df).fit(cov_type="HC3")
    op = smf.ols(FORMULA.replace("C(line)", "C(operator_id)"), df).fit()
    humidity_terms = [k for k in full.params.index if "humidity_pct" in k]
    p = {
        "mold_temp": full.pvalues["mold_temp"],
        "humidity_pct": float(full.f_test(", ".join(f"{k} = 0" for k in humidity_terms)).pvalue),
        "cycle_time_s": full.pvalues["cycle_time_s"],
        "shift": full.pvalues["C(shift)[T.Night]"],
        "machine_age_years": full.pvalues["machine_age_years"],
        "ambient_temp_c": full.pvalues["ambient_temp_c"],
        "operator_id": op.compare_f_test(smf.ols(FORMULA, df).fit())[1],
    }
    assert sorted(k for k, v in p.items() if v < 0.001) == DIRECT_DRIVERS

    # C1: the new resin comes with its grade's recipe, so the cycle time moves with it (T14).
    recipe = df["supplier_name"].map(df.groupby("supplier_name")["recipe_cycle_time_s"].first())
    recipes = df.groupby("supplier_name")["recipe_cycle_time_s"].first()
    switch = {
        s: expected_rate(full, df, supplier_name=s, cycle_time_s=(df["cycle_time_s"] - recipe + recipes[s]).clip(18, 45))
        for s in ("Alpha", "Beta", "Gamma")
    }
    assert min(switch, key=switch.get) == q["C1"]["truth"]
    held = {s: expected_rate(full, df, supplier_name=s) for s in ("Alpha", "Beta", "Gamma")}
    assert min(held, key=held.get) == q["C1"]["naive"]

    b = full.params
    alpha_optimum = -b["C(supplier_name)[Alpha]:humidity_pct"] / (2 * b["C(supplier_name)[Alpha]:I(humidity_pct ** 2)"])
    assert abs(alpha_optimum - HUMIDITY_OPT_ALPHA) < 2

    # C3: the model's relative change applied to the observed pooled rate. Rows in the
    # unlogged gap (T20) are left out: their real cleanings followed the plan, so the extra
    # cleanings would change little there.
    days = every["days_since_cleaning"].where(every["cleaning_unlogged"], every["days_since_cleaning"] % CLEANING_PLAN_DAYS)
    ratio = expected_rate(full, every, days_since_cleaning=days) / expected_rate(full, every)
    c3 = q["A3"]["truth"] * ratio
    assert abs(c3 - q["C3"]["truth"]) < 0.3 * q["C3"]["scale"]


@pytest.mark.parametrize("seed", SEEDS)
def test_v4_clues_are_recoverable_from_the_data(seed):
    """Each v4 clue is measured, not read: date formats, the sensor offset, the QC change."""
    ds = generate(seed)
    raw = reference_clean(ds.batches, ds.suppliers, ds.maintenance, fix_sensor=False)
    # ~0.4 degC standard error (mold noise sd 6); A4 below shows what that costs.
    assert abs(sensor_offset(raw, "L1", "2025-04-14", ["L2", "L4"]) - DRIFT_C) < 1.0
    line, day = qc_change(raw)
    assert line == "L3" and abs((pd.Timestamp(day) - pd.Timestamp("2025-07-21")).days) <= 7
    assert abs(cleaned(ds)["mold_temp"].median() - ds.ground_truth["questions"]["A4"]["truth"]) < 0.3
