"""Generator tests: reproducibility, trap injection, ablation switches and DGP sanity.

The DGP checks re-run the analysis a careful analyst would do, so they also prove the
planted effects are detectable in the published data (construct validity).
"""

import json

import numpy as np
import pandas as pd
import pytest

from edabench.generate import (
    CANARY,
    HUMIDITY_OPT_ALPHA,
    HUMIDITY_OPT_DRIED,
    HUMIDITY_OPTIMUM,
    TRAPS,
    V4_TRAPS,
    generate,
    resolve_traps,
    write,
)

SEED = 42


@pytest.fixture(scope="module")
def full():
    return generate(SEED)


@pytest.fixture(scope="module")
def clean():
    return generate(SEED, {t: False for t in TRAPS})


DATE_FORMATS = ("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y")


def parse_dates_per_line(df: pd.DataFrame) -> pd.Series:
    """Each line's export uses one format; it is the only candidate that parses every row."""
    out = pd.Series(pd.NaT, index=df.index, dtype="datetime64[ns]")
    for line, rows in df.groupby("line")["production_date"]:
        fits = [f for f in DATE_FORMATS if pd.to_datetime(rows, format=f, errors="coerce").notna().all()]
        assert len(fits) == 1, (line, fits)
        out[rows.index] = pd.to_datetime(rows, format=fits[0])
    return out


def sensor_offset(df: pd.DataFrame, line: str, since: str, controls: list[str]) -> float:
    """Jump of one line's readings at a date, relative to lines without a jump (DiD),
    adjusted for ambient temperature, which moves every mold."""
    d = df[df["line"].isin([line, *controls]) & df["mold_temp"].notna()]
    X = pd.get_dummies(d["line"], drop_first=True).astype(float)
    X["ambient"] = d["ambient_temp_c"]
    X["post"] = ((d["line"] == line) & (d["production_date"] >= since)).astype(float)
    X.insert(0, "const", 1.0)
    beta, *_ = np.linalg.lstsq(X.to_numpy(), d["mold_temp"].to_numpy(), rcond=None)
    return float(beta[-1])


def qc_change(df: pd.DataFrame, min_t: float = 8.0) -> tuple[str | None, str | None]:
    """The line and date where rework cost per recorded defect jumps most (T17).

    Rework is booked for every defective part, so a jump in cost per *recorded* defect
    means QC started to record fewer of them. Without a real change the largest of the
    ~900 candidate splits stays far below `min_t`.
    """
    best = (min_t, None, None)
    d = df[df["defective_units"] > 0]
    ratio = d["rework_cost_eur"] / d["defective_units"]
    for line in sorted(d["line"].unique()):
        r, dates = ratio[d["line"] == line], d.loc[d["line"] == line, "production_date"]
        for day in sorted(dates.unique())[20:-20]:
            after = dates >= day
            t = (r[after].mean() - r[~after].mean()) / np.sqrt(r[after].var() / after.sum() + r[~after].var() / (~after).sum())
            if t > best[0]:
                best = (t, line, day)
    return best[1], best[2]


def reference_clean(df: pd.DataFrame, suppliers: pd.DataFrame, maintenance: pd.DataFrame,
                    fix_sensor: bool = True) -> pd.DataFrame:
    """The cleaning a careful analyst should do; mirrors the traps in docs/task_design.md.

    Everything it needs is in the published files. From v4 the clues are not spelt out:
    the date format of each line, the size of the sensor offset and the QC change are
    measured in the data; the log only gives the sensor replacement and the cleanings.
    """
    df = df.drop_duplicates().copy()
    df["production_date"] = parse_dates_per_line(df).dt.strftime("%Y-%m-%d")
    df["shift"] = df["shift"].str.strip().str[0].str.upper().map({"D": "Day", "N": "Night"})
    df["supplier_code"] = df["supplier_code"].str.strip().str.upper()
    df = df.merge(suppliers, on="supplier_code", how="left", validate="many_to_one")
    df["humidity_pct"] = df["humidity_pct"].where(df["humidity_pct"] >= 0)
    df["mold_temp"] = df["mold_temp"].where(df["mold_temp"] > 0)
    f = df["line"] == "L3"
    df.loc[f, "mold_temp"] = (df.loc[f, "mold_temp"] - 32) * 5 / 9

    date = pd.to_datetime(df["production_date"])
    # The replaced sensor: measure its jump against L2 and L4 (L3 has a jump of its own,
    # a real one: its defects follow, test_t16). Below 0.5 degC it is calibrated.
    replaced = maintenance.query("event == 'sensor_replacement'").iloc[0]
    offset = sensor_offset(df, replaced["line"], replaced["date"], ["L2", "L4"])
    if fix_sensor and abs(offset) >= 0.5:
        drifted = (df["line"] == replaced["line"]) & (date >= replaced["date"])
        df.loc[drifted, "mold_temp"] -= round(offset, 1)
    if "rework_cost_eur" in df:
        qc_line, qc_date = qc_change(df)
        df["qc_change"] = ((df["line"] == qc_line) & (df["production_date"] >= qc_date)).astype(float)

    cleanings = maintenance.query("event == 'mold_cleaning'").assign(clean_date=lambda m: pd.to_datetime(m["date"]))
    df = pd.merge_asof(
        df.assign(_date=date).sort_values("_date"),
        cleanings[["line", "clean_date"]].sort_values("clean_date"),
        left_on="_date", right_on="clean_date", by="line", direction="backward",
    )
    df["days_since_cleaning"] = (df["_date"] - df["clean_date"]).dt.days
    df = df.drop(columns=["_date", "clean_date"])
    df["rate"] = df["defective_units"] / df["units_produced"]
    return df


def cleaned(ds) -> pd.DataFrame:
    return reference_clean(ds.batches, ds.suppliers, ds.maintenance)


def pooled(g: pd.DataFrame) -> float:
    return g["defective_units"].sum() / g["units_produced"].sum()


# --- reproducibility -------------------------------------------------------------

def test_same_seed_same_bytes(tmp_path):
    for name in ("a", "b"):
        write(generate(SEED), tmp_path / name, tmp_path / name / "gt.json")
    for f in ("batches.csv", "suppliers.csv", "maintenance.csv", "gt.json"):
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
    df = cleaned(full)
    same_qc = df[df["qc_change"] == 0]  # T17: L3 records fewer defects after its QC change
    assert same_qc["rework_cost_eur"].corr(same_qc["defective_units"]) > 0.95
    assert "rework_cost_eur" not in clean.batches and "qc_inspection_min" not in clean.batches


def test_ablation_changes_only_the_switched_trap(full):
    no_dups = generate(SEED, {"duplicates": False})
    by_id = lambda df: df.sort_values("batch_id").reset_index(drop=True)
    pd.testing.assert_frame_equal(by_id(full.batches.drop_duplicates()), by_id(no_dups.batches))


@pytest.mark.parametrize("trap", TRAPS)
def test_ablation_keeps_common_random_numbers(full, trap):
    """Switching off any trap leaves unrelated draws alone, e.g. which readings are missing.

    Before v3 the defect counts came from rng.binomial, whose draw count depends on p, so
    every trap that changed p also reshuffled the missing values and the duplicates.
    """
    variant = generate(SEED, {trap: False})
    key = lambda df: df.drop_duplicates().sort_values("batch_id").set_index("batch_id")
    a, b = key(full.batches), key(variant.batches)
    assert a.index.equals(b.index)
    missing = lambda df: df["humidity_pct"].isna() | (df["humidity_pct"] < 0)
    assert missing(a).equals(missing(b))
    if trap not in ("mediator", "simpson_paradox"):  # T14: the cycle time follows the supplier's recipe
        assert a["cycle_time_s"].equals(b["cycle_time_s"])


# --- planted effects are real and detectable ---------------------------------------

def test_t5_pooled_differs_from_mean(full):
    a3 = full.ground_truth["questions"]["A3"]
    assert abs(a3["naive"] - a3["truth"]) > 0.002


def test_t6_humidity_u_shape_invisible_to_pearson(full):
    df = cleaned(full).dropna(subset=["humidity_pct"])
    assert abs(df["rate"].corr(df["humidity_pct"])) < 0.1
    h = HUMIDITY_OPTIMUM
    bins = df.groupby(pd.cut(df["humidity_pct"], [0, h - 15, h - 5, h + 5, h + 15, 100]), observed=True).apply(pooled)
    assert bins.iloc[2] < bins.iloc[0] and bins.iloc[2] < bins.iloc[-1]


def test_c2_optimum_is_not_guessable(full):
    """Neither the range midpoint, the mean nor the pooled optimum gives Alpha's optimum."""
    c2 = full.ground_truth["questions"]["C2"]
    assert c2["scale"] > 5 and abs(c2["naive"] - c2["truth"]) == pytest.approx(c2["scale"])
    hum = cleaned(full)["humidity_pct"].dropna()
    assert abs((hum.min() + hum.max()) / 2 - c2["truth"]) > c2["scale"]
    assert abs(hum.mean() - c2["truth"]) > 3


def test_batch_ids_do_not_reveal_the_count(full):
    nums = full.batches["batch_id"].str[2:].astype(int)
    assert nums.max() > 10 * full.ground_truth["questions"]["A1"]["truth"]
    assert not nums.drop_duplicates().is_monotonic_increasing


def test_t7_confounder_correlates_but_has_no_direct_effect(full):
    df = cleaned(full).dropna()
    assert df["rate"].corr(df["machine_age_years"]) > 0.2
    t = _ols_t(df)
    assert abs(t["machine_age_years"]) < 2.5 and abs(t["ambient_temp_c"]) < 2.5
    assert min(abs(t["mold_temp"]), abs(t["cycle_time_s"]), abs(t["night"]), abs(t["hum_sq"])) > 4


def test_t9_simpson_reversal(full):
    df = cleaned(full)
    overall = df.groupby("supplier_name").apply(pooled)
    assert overall.idxmax() == "Beta"
    within = df.groupby(["line", "supplier_name"]).apply(pooled).unstack()
    assert (within["Beta"] < within["Alpha"]).all()


def test_t10_regime_change(full, clean):
    df = cleaned(full).query("line == 'L2'")
    after = df["production_date"] >= "2025-06-16"
    assert pooled(df[after]) > 1.3 * pooled(df[~after])
    assert clean.ground_truth["questions"]["B3"]["truth"] is None


def test_t11_humidity_optimum_depends_on_the_resin(full):
    df = cleaned(full).dropna(subset=["humidity_pct", "mold_temp"])
    t_alpha = _ols(df[df["supplier_name"] == "Alpha"])
    t_dried = _ols(df[df["supplier_name"] != "Alpha"])
    optimum = lambda b: -b["hum"] / (2 * b["hum_sq"])
    assert abs(optimum(t_alpha) - HUMIDITY_OPT_ALPHA) < 1.5
    assert abs(optimum(t_dried) - HUMIDITY_OPT_DRIED) < 1.5
    assert abs(optimum(_ols(df)) - full.ground_truth["questions"]["C2"]["naive"]) < 1.5


def _step(df: pd.DataFrame, line: str, since: str, until: str = "9999") -> tuple[float, float]:
    """Jump of the readings (ambient-adjusted) and of the empirical defect logit at a date,
    against L4, using the batches before `until` only."""
    d = df[df["line"].isin([line, "L4"]) & df["mold_temp"].notna() & (df["production_date"] < until)]
    after, on = d["production_date"] >= since, d["line"] == line
    logit = lambda g: np.log(pooled(g) / (1 - pooled(g)))
    did = (logit(d[on & after]) - logit(d[on & ~after])) - (logit(d[~on & after]) - logit(d[~on & ~after]))
    return sensor_offset(d, line, since, ["L4"]), did


def test_t12_sensor_drift_is_measured_not_read(full):
    """The log only says the sensor was replaced; the offset must come from the data."""
    assert not full.maintenance["note"].str.contains(r"\d", regex=True).any()
    raw = reference_clean(full.batches, full.suppliers, full.maintenance, fix_sensor=False)
    assert abs(sensor_offset(raw, "L1", "2025-04-14", ["L2", "L4"]) - 8.0) < 0.5
    readings, logit = _step(raw, "L1", "2025-04-14")
    assert readings > 6 and abs(logit) < 0.1  # hotter readings, same defects: the sensor
    a4 = full.ground_truth["questions"]["A4"]
    assert a4["naive"] - a4["truth"] >= 0.5


def test_t16_real_setpoint_change_moves_the_defects(full):
    """L3 jumps too, but its defects follow the effect of temperature: a real change."""
    readings, logit = _step(cleaned(full), "L3", "2025-05-19", until="2025-07-21")  # before T17
    assert 4.5 < readings < 7.5
    assert logit > 0.1  # 6 degC x 0.03 per degC = 0.18 on the logit
    assert "L3" not in set(full.maintenance.query("event != 'mold_cleaning'")["line"])


def test_t14_cycle_time_follows_the_recipe(full):
    df = cleaned(full)
    by_grade = df.groupby("resin_grade")["cycle_time_s"].mean()
    assert by_grade["PP-H420"] - by_grade["PP-H350"] > 5
    q = full.ground_truth["questions"]["C1"]
    assert (q["truth"], q["naive"]) == ("Gamma", "Beta")
    off = generate(SEED, {"mediator": False})
    assert set(off.suppliers["recipe_cycle_time_s"]) == {30}
    assert off.ground_truth["questions"]["C1"]["truth"] == "Beta"


def test_t15_dates_need_a_format_per_line(full, clean):
    raw = full.batches.drop_duplicates()
    iso = pd.to_datetime(cleaned(clean)["production_date"]).sort_values().reset_index(drop=True)
    with pytest.raises(ValueError):
        pd.to_datetime(raw["production_date"])  # the format of the first row does not fit all
    for kw in ({"format": "mixed"}, {"format": "mixed", "dayfirst": True}):
        assert not pd.to_datetime(raw["production_date"], **kw).sort_values().reset_index(drop=True).equals(iso)
    assert (parse_dates_per_line(raw).sort_values().dt.strftime("%F").tolist() == iso.dt.strftime("%F").tolist())
    assert clean.batches["production_date"].str.match(r"\d{4}-\d{2}-\d{2}$").all()


def test_t17_qc_change_lowers_recorded_defects_only(full):
    df = cleaned(full)
    line, day = qc_change(df)
    assert line == "L3" and abs((pd.Timestamp(day) - pd.Timestamp("2025-07-21")).days) <= 7
    l3, after = df["line"] == "L3", df["production_date"] >= "2025-07-21"
    assert pooled(df[l3 & after]) < 0.7 * pooled(df[l3 & ~after])
    cost = lambda g: g["rework_cost_eur"].sum() / g["defective_units"].sum()
    assert cost(df[l3 & after]) > 1.8 * cost(df[l3 & ~after])
    assert df.loc[l3 & ~after, "qc_inspection_min"].mean() - df.loc[l3 & after, "qc_inspection_min"].mean() > 5
    b3 = full.ground_truth["questions"]["B3"]
    assert b3["truth"]["line"] == "L2" and b3["naive"] == {"line": "L3", "date": "2025-07-21"}


def test_t13_cleaning_gaps_confound_ambient_temperature(full):
    df = cleaned(full).dropna()
    fit = lambda d: _ols(d, t_stats=True, interaction=True)
    with_log, without_log = fit(df), fit(df.drop(columns="days_since_cleaning"))
    assert with_log["days_since_cleaning"] > 8
    assert abs(without_log["ambient_temp_c"]) > 2 > abs(with_log["ambient_temp_c"])
    summer = pd.to_datetime(df["production_date"]).dt.month.isin([7, 8])
    assert df.loc[summer, "days_since_cleaning"].mean() > 1.5 * df.loc[~summer, "days_since_cleaning"].mean()


def test_counterfactual_answers(full):
    q = full.ground_truth["questions"]
    assert q["C1"]["truth"] == "Gamma" != q["C1"]["naive"]
    assert q["C3"]["naive"] < q["C3"]["truth"] < q["A3"]["truth"]


def test_ablated_v3_traps_reset_their_answers():
    off = {"interaction": False, "sensor_drift": False, "hidden_driver": False, "mediator": False}
    q = generate(SEED, off).ground_truth["questions"]
    assert q["C2"]["truth"] == HUMIDITY_OPTIMUM and abs(q["C2"]["naive"] - HUMIDITY_OPTIMUM) < 2
    assert q["C3"]["truth"] == q["A3"]["truth"]
    assert q["C1"]["truth"] == "Beta"


def test_ablated_v4_traps_reset_their_answers():
    ds = generate(SEED, {t: False for t in V4_TRAPS})
    q = ds.ground_truth["questions"]
    assert "naive" not in q["B3"] and q["C1"]["truth"] == "Beta"
    df = cleaned(ds)
    assert df["qc_change"].sum() == 0 or qc_change(df)[0] != "L3"  # no real QC change to find
    readings, _ = _step(df, "L3", "2025-05-19")
    assert abs(readings) < 1


def _ols(df: pd.DataFrame, t_stats: bool = False, interaction: bool = False) -> pd.Series:
    """OLS on the empirical logit with every candidate; coefficients or t-statistics.

    With `interaction`, Alpha batches get their own humidity curve (T11).
    """
    X = pd.get_dummies(df[["line", "supplier_name"]], drop_first=True).astype(float)
    X["night"] = (df["shift"] == "Night").astype(float)
    for c in ("mold_temp", "cycle_time_s", "machine_age_years", "ambient_temp_c", "days_since_cleaning"):
        if c in df:
            X[c] = df[c]
    X["hum"] = df["humidity_pct"]
    X["hum_sq"] = df["humidity_pct"] ** 2
    if interaction:
        alpha = (df["supplier_name"] == "Alpha").astype(float)
        X["hum_alpha"], X["hum_sq_alpha"] = X["hum"] * alpha, X["hum_sq"] * alpha
    X["regime"] = ((df["line"] == "L2") & (df["production_date"] >= "2025-06-16")).astype(float)
    if "qc_change" in df:
        X["qc_change"] = df["qc_change"]
    X = X.loc[:, X.std() > 0]
    X.insert(0, "const", 1.0)
    d, n = df["defective_units"], df["units_produced"]
    y = np.log((d + 0.5) / (n - d + 0.5))
    A = X.to_numpy()
    beta, *_ = np.linalg.lstsq(A, y.to_numpy(), rcond=None)
    if not t_stats:
        return pd.Series(beta, index=X.columns)
    resid = y.to_numpy() - A @ beta
    se = np.sqrt(np.diag(np.linalg.inv(A.T @ A)) * resid.var(ddof=A.shape[1]))
    return pd.Series(beta / se, index=X.columns)


def _ols_t(df: pd.DataFrame) -> pd.Series:
    """t-statistics of an OLS on the empirical logit, controlling for line and supplier."""
    X = pd.get_dummies(df[["line", "supplier_name"]], drop_first=True).astype(float)
    X["night"] = (df["shift"] == "Night").astype(float)
    for c in ("mold_temp", "cycle_time_s", "machine_age_years", "ambient_temp_c", "days_since_cleaning"):
        X[c] = df[c]
    alpha = df["supplier_name"] == "Alpha"
    X["hum_sq"] = (df["humidity_pct"] - np.where(alpha, HUMIDITY_OPT_ALPHA, HUMIDITY_OPT_DRIED)) ** 2
    X["regime"] = ((df["line"] == "L2") & (df["production_date"] >= "2025-06-16")).astype(float)
    X["qc_change"] = df["qc_change"]
    X.insert(0, "const", 1.0)
    r = df["rate"].clip(1e-4, 1 - 1e-4)
    y = np.log(r / (1 - r))
    A = X.to_numpy()
    beta, *_ = np.linalg.lstsq(A, y.to_numpy(), rcond=None)
    resid = y.to_numpy() - A @ beta
    se = np.sqrt(np.diag(np.linalg.inv(A.T @ A)) * resid.var(ddof=A.shape[1]))
    return pd.Series(beta / se, index=X.columns)
