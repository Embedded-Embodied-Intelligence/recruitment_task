"""The expert method recovers the planted answers on many seeds, not just on seed 42.

This protects the answer key against a lucky seed: if a question's truth were only
reachable by chance, a fair model could lose points that no analyst could earn.
"""

import numpy as np
import pandas as pd
import pytest
import statsmodels.formula.api as smf

from edabench.generate import DIRECT_DRIVERS, HUMIDITY_OPTIMUM, generate
from tests.test_generate import reference_clean

FORMULA = (
    "y ~ C(line) + C(supplier_name) + C(shift) + mold_temp + humidity_pct + I(humidity_pct**2)"
    "+ cycle_time_s + machine_age_years + ambient_temp_c + regime"
)
SEEDS = range(42, 52)


def model_frame(seed: int) -> pd.DataFrame:
    ds = generate(seed)
    df = reference_clean(ds.batches, ds.suppliers).dropna(subset=["mold_temp", "humidity_pct"])
    df["regime"] = ((df["line"] == "L2") & (df["production_date"] >= "2025-06-16")).astype(int)
    d, n = df["defective_units"], df["units_produced"]
    df["y"] = np.log((d + 0.5) / (n - d + 0.5))
    return df


@pytest.mark.parametrize("seed", SEEDS)
def test_reference_recovers_driver_set_supplier_and_optimum(seed):
    df = model_frame(seed)
    full = smf.ols(FORMULA, df).fit(cov_type="HC3")
    op = smf.ols(FORMULA.replace("C(line)", "C(operator_id)"), df).fit()
    p = {
        "mold_temp": full.pvalues["mold_temp"],
        "humidity_pct": float(full.f_test("humidity_pct = 0, I(humidity_pct ** 2) = 0").pvalue),
        "cycle_time_s": full.pvalues["cycle_time_s"],
        "shift": full.pvalues["C(shift)[T.Night]"],
        "machine_age_years": full.pvalues["machine_age_years"],
        "ambient_temp_c": full.pvalues["ambient_temp_c"],
        "operator_id": op.compare_f_test(smf.ols(FORMULA, df).fit())[1],
    }
    assert sorted(k for k, v in p.items() if v < 0.001) == DIRECT_DRIVERS

    sup = {"Alpha": 0.0, **{s: full.params[f"C(supplier_name)[T.{s}]"] for s in ("Beta", "Gamma")}}
    assert min(sup, key=sup.get) == "Beta"

    h_star = -full.params["humidity_pct"] / (2 * full.params["I(humidity_pct ** 2)"])
    assert abs(h_star - HUMIDITY_OPTIMUM) < 2
