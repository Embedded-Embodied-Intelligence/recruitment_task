"""Build and execute reference/reference_solution.ipynb.

The notebook is the "expert" solution: it reaches every answer from the published data
alone (it never imports the generator), and only its last section compares the result
with the answer key. Source lives here so the notebook is reviewable as plain Python.

    python reference/build_notebook.py
"""

from pathlib import Path

import nbformat
from nbclient import NotebookClient

HERE = Path(__file__).resolve().parent

CELLS: list[tuple[str, str]] = [
    ("md", """# Reference solution: hidden drivers of defects

This notebook solves the task the way a careful analyst would, using only `data/`.
It follows the three EDA steps from the task definition:

1. **Describe** the data (DDA): structure, quality issues, cleaning, A1-A4.
2. **Identify salient features**: leakage, regime change, direct drivers, B1-B3.
3. **Interpret salient features**: the supplier question and the humidity optimum, C1-C2.

It produces `reference_answer.json` in the answer format of the task, then (section 4 only) checks it against the answer key."""),
    ("code", """import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf

DATA = Path("../data")
BLUE, ORANGE, AQUA, GRAY = "#2a78d6", "#eb6834", "#1baf7a", "#8a8984"
plt.rcParams.update({"figure.dpi": 110, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.grid": True, "axes.axisbelow": True, "grid.color": "#e6e5e0", "grid.linewidth": 0.6})
pd.set_option("display.width", 140)

raw = pd.read_csv(DATA / "batches.csv")
suppliers = pd.read_csv(DATA / "suppliers.csv")
print(raw.shape)
raw.head()"""),
    ("md", "## 1. Describe the data\n\n### 1.1 Structure and summary statistics"),
    ("code", "raw.dtypes.to_frame('dtype').T"),
    ("code", "raw.describe().T.round(2)"),
    ("md", """Two values stand out in `describe()` before any plotting:

- `humidity_pct` has a minimum of **-1**, which is impossible for relative humidity, so it is a sentinel for a missing reading.
- `mold_temp` has a minimum of **0** and a maximum above 400, both implausible for one unit of measurement."""),
    ("md", "### 1.2 Categorical columns"),
    ("code", """for col in ["line", "shift", "supplier_code"]:
    print(col, raw[col].map(repr).value_counts().to_dict(), "\\n")"""),
    ("md", "`shift` has spelling variants of two values (`Day`, `day`, `D`, `' Day'`, ...), and `supplier_code` has case and whitespace variants of the three codes in `suppliers.csv`. A join on the raw key would silently drop rows."),
    ("md", "### 1.3 Duplicates"),
    ("code", """print("exact duplicate rows:", raw.duplicated().sum())
print("repeated batch_id:   ", raw["batch_id"].duplicated().sum())
dup_ids = raw.loc[raw["batch_id"].duplicated(), "batch_id"]
print("rows sharing a repeated id that are NOT exact copies:",
      (raw[raw["batch_id"].isin(dup_ids)].drop_duplicates()["batch_id"].duplicated()).sum())"""),
    ("md", "Every repeated `batch_id` is an exact copy of another row (a double export), so dropping exact duplicates is safe and loses no information."),
    ("md", "### 1.4 Mold temperature units"),
    ("code", """valid = raw[raw["mold_temp"] > 0]
print(valid.groupby("line")["mold_temp"].describe().round(1))
print("\\nzeros per line:", raw[raw["mold_temp"] == 0].groupby("line").size().to_dict())"""),
    ("code", """fig, ax = plt.subplots(figsize=(7, 2.6))
for i, (line, g) in enumerate(valid.groupby("line")):
    ax.scatter(g["mold_temp"], np.full(len(g), i) + np.random.default_rng(0).uniform(-0.25, 0.25, len(g)),
               s=8, color=ORANGE if line == "L3" else BLUE, alpha=0.35, linewidths=0)
ax.set_yticks(range(4), sorted(valid["line"].unique()))
ax.set_xlabel("mold_temp as logged")
ax.set_title("Line L3 logs on a different scale", loc="left", fontsize=10)
plt.tight_layout()"""),
    ("md", """L3 sits around 410 while the other lines sit around 210. (410 - 32) × 5/9 ≈ 210, so **L3 logs in °F**. The zeros appear on every line and are sensor failures, not cold molds."""),
    ("md", "### 1.5 Cleaning"),
    ("code", """def clean(raw: pd.DataFrame, suppliers: pd.DataFrame) -> pd.DataFrame:
    df = raw.drop_duplicates().copy()
    df["shift"] = df["shift"].str.strip().str[0].str.upper().map({"D": "Day", "N": "Night"})
    df["supplier_code"] = df["supplier_code"].str.strip().str.upper()
    df = df.merge(suppliers, on="supplier_code", how="left", validate="many_to_one")
    df["humidity_pct"] = df["humidity_pct"].where(df["humidity_pct"] >= 0)   # -1 -> NaN
    df["mold_temp"] = df["mold_temp"].where(df["mold_temp"] > 0)             # 0 -> NaN
    is_f = df["line"] == "L3"
    df.loc[is_f, "mold_temp"] = (df.loc[is_f, "mold_temp"] - 32) * 5 / 9   # degF -> degC
    df["production_date"] = pd.to_datetime(df["production_date"])
    df["rate"] = df["defective_units"] / df["units_produced"]
    return df

df = clean(raw, suppliers)
assert df["shift"].notna().all() and df["supplier_name"].notna().all()
assert df.groupby("line")["mold_temp"].median().between(195, 225).all()
print(df.shape)
df[["shift", "supplier_name"]].value_counts().unstack()"""),
    ("md", "### 1.6 Answers A1-A4"),
    ("code", """answers = {}
answers["A1_unique_batches"] = int(df["batch_id"].nunique())
answers["A2_missing_humidity_batches"] = int(df["humidity_pct"].isna().sum())
answers["A3_overall_defect_rate"] = round(float(df["defective_units"].sum() / df["units_produced"].sum()), 5)
answers["A4_median_mold_temp_c"] = round(float(df["mold_temp"].median()), 2)

print("mean of batch rates (not the overall rate):", round(df["rate"].mean(), 5))
print("missing humidity, NaN only (sentinels ignored):", raw.drop_duplicates()["humidity_pct"].isna().sum())
answers"""),
    ("md", """The overall defect rate is the share of *all produced units* that were defective, so it is a pooled ratio. The mean of batch rates differs because the worst line also makes the smallest batches, which gives each of its few units too much weight."""),
    ("md", "## 2. Identify salient features\n\n### 2.1 Leakage: columns determined by the outcome"),
    ("code", """num = df.select_dtypes("number").drop(columns=["rate"])
num.corrwith(df["defective_units"]).sort_values(ascending=False).round(3).to_frame("r with defective_units")"""),
    ("code", """ratio = df["rework_cost_eur"] / df["defective_units"].replace(0, np.nan)
print("rework cost per defective part: median", round(ratio.median(), 2), "IQR", ratio.quantile([.25, .75]).round(2).tolist())
slope = np.polyfit(df["defective_units"], df["qc_inspection_min"], 1)
print(f"qc minutes = {slope[1]:.1f} + {slope[0]:.3f} x defective_units")"""),
    ("md", """`rework_cost_eur` is almost exactly 4.2 € per defective part, and `qc_inspection_min` grows with the number of defects found. Both are **recorded after quality control and computed from the outcome**. They are excellent "predictors" only because they encode Y, so they must be excluded from any driver analysis (B2)."""),
    ("md", "### 2.2 Univariate view: what a correlation matrix would suggest"),
    ("code", """cands = ["mold_temp", "humidity_pct", "cycle_time_s", "machine_age_years", "ambient_temp_c"]
df[cands].corrwith(df["rate"]).round(3).to_frame("Pearson r with defect rate")"""),
    ("code", """bins = pd.cut(df["humidity_pct"], np.arange(15, 76, 5))
by_hum = df.groupby(bins, observed=True).apply(lambda g: g["defective_units"].sum() / g["units_produced"].sum())
fig, ax = plt.subplots(figsize=(7, 3))
ax.plot([b.mid for b in by_hum.index], by_hum.values * 100, color=BLUE, lw=2, marker="o", ms=6)
ax.set_xlabel("humidity_pct (5-point bins)"); ax.set_ylabel("defect rate, %")
ax.set_title("Humidity has a U-shaped effect despite r ≈ 0", loc="left", fontsize=10)
plt.tight_layout()"""),
    ("md", """Pearson r for humidity is close to 0, yet the binned rate is clearly U-shaped. Linear correlation cannot see a symmetric non-linear effect. `machine_age_years` and `ambient_temp_c`, on the other hand, correlate with the rate. Section 2.4 tests whether those correlations are direct effects or confounding."""),
    ("md", "### 2.3 Regime change over time"),
    ("code", """weekly = (df.set_index("production_date").groupby("line")[["defective_units", "units_produced"]]
          .resample("W").sum())
weekly = (weekly["defective_units"] / weekly["units_produced"]).unstack(0)
fig, ax = plt.subplots(figsize=(8, 3))
others = [l for l in weekly if l != "L2"]
for k, line in enumerate(others):
    ax.plot(weekly.index, weekly[line] * 100, lw=1.2, color=GRAY, alpha=0.6,
            label=", ".join(others) if k == 0 else None)
ax.plot(weekly.index, weekly["L2"] * 100, lw=2, color=ORANGE, label="L2")
ax.legend(ncol=2, frameon=False, fontsize=8); ax.set_ylabel("weekly defect rate, %")
ax.set_title("Weekly defect rate per line", loc="left", fontsize=10)
plt.tight_layout()"""),
    ("md", """All lines drift up in summer (hotter hall, hotter molds), so a changepoint search on raw rates would be confounded by season. The search below therefore runs on **observed / expected** defects, where *expected* comes from a model of the process variables without any time term. For each line it finds the single split date that maximizes the Poisson log-likelihood ratio."""),
    ("code", """base_formula = ("rate ~ C(line) + C(supplier_name) + C(shift) + mold_temp + humidity_pct"
                "+ I(humidity_pct**2) + cycle_time_s")
model_df = df.dropna(subset=["mold_temp", "humidity_pct"]).copy()
base = smf.glm(base_formula, model_df, family=sm.families.Binomial(),
               var_weights=model_df["units_produced"]).fit(scale="X2")
model_df["expected"] = base.predict(model_df) * model_df["units_produced"]

def best_split(g: pd.DataFrame, margin_days: int = 14):
    daily = g.groupby("production_date")[["defective_units", "expected"]].sum().sort_index()
    o, e = daily["defective_units"].to_numpy(), daily["expected"].to_numpy()
    co, ce = o.cumsum(), e.cumsum()
    def seg(oo, ee): return oo * np.log(oo / ee)
    total = seg(co[-1], ce[-1])
    llr = [seg(co[i - 1], ce[i - 1]) + seg(co[-1] - co[i - 1], ce[-1] - ce[i - 1]) - total
           for i in range(margin_days, len(o) - margin_days)]
    i = int(np.argmax(llr)) + margin_days
    return daily.index[i].date(), float(max(llr)), co[i - 1] / ce[i - 1], (co[-1] - co[i - 1]) / (ce[-1] - ce[i - 1])

splits = pd.DataFrame([(l, *best_split(g)) for l, g in model_df.groupby("line")],
                      columns=["line", "split_date", "LLR", "O/E before", "O/E after"]).set_index("line")
splits.round(3)"""),
    ("md", """Only L2 shows a large likelihood ratio: its observed/expected defect ratio jumps by a large factor at one date. The other lines' best splits are noise of much smaller magnitude."""),
    ("code", """regime_line = splits["LLR"].idxmax()
regime_date = splits.loc[regime_line, "split_date"]
df["regime"] = ((df["line"] == regime_line) & (df["production_date"] >= pd.Timestamp(regime_date))).astype(int)
answers["B3_regime_change"] = {"line": regime_line, "date": str(regime_date)}
answers["B3_regime_change"]"""),
    ("md", """### 2.4 Direct drivers: one multivariable model

Each batch is one observation of a noisy process. Besides binomial sampling noise, batches differ by an unobserved batch-level factor, so a large batch is *not* proportionally more informative than a small one. The model is therefore an OLS on the **empirical logit** of each batch, `log((d + 0.5) / (n - d + 0.5))`, with heteroskedasticity-robust (HC3) standard errors. It contains every candidate variable plus the controls (line, supplier, regime). A variable with a *direct* effect keeps a clear signal when everything else is held fixed, while a confounded one loses it."""),
    ("code", """model_df = df.dropna(subset=["mold_temp", "humidity_pct"]).copy()
model_df["y"] = np.log((model_df["defective_units"] + 0.5) / (model_df["units_produced"] - model_df["defective_units"] + 0.5))
full_formula = ("y ~ C(line) + C(supplier_name) + C(shift) + mold_temp + humidity_pct + I(humidity_pct**2)"
                "+ cycle_time_s + machine_age_years + ambient_temp_c + regime")
full = smf.ols(full_formula, model_df).fit(cov_type="HC3")
print(full.summary().tables[1])"""),
    ("code", """op_model = smf.ols(full_formula.replace("C(line)", "C(operator_id)"), model_df).fit()
tests = {
    "mold_temp": full.pvalues["mold_temp"],
    "humidity_pct (linear + squared)": float(full.f_test("humidity_pct = 0, I(humidity_pct ** 2) = 0").pvalue),
    "cycle_time_s": full.pvalues["cycle_time_s"],
    "shift": full.pvalues["C(shift)[T.Night]"],
    "machine_age_years": full.pvalues["machine_age_years"],
    "ambient_temp_c": full.pvalues["ambient_temp_c"],
    # operator_id is nested in line: does replacing line dummies by operator dummies add anything?
    "operator_id (within line)": op_model.compare_f_test(smf.ols(full_formula, model_df).fit())[1],
}
pd.Series(tests, name="p-value").map(lambda p: f"{p:.2e}").to_frame()"""),
    ("md", """Mold temperature, humidity, cycle time and shift are overwhelmingly significant (p < 0.001). Machine age, ambient temperature and operator add nothing once line and mold temperature are in the model:

- **Machine age** correlates with defects only because the oldest presses are on L4, the worst line.
- **Ambient temperature** acts *through* mold temperature (a hot hall heats the molds), so it has no effect of its own.
- **Operators** are tied to lines, and their apparent differences are line differences."""),
    ("md", """#### Side note: a tempting model that gets this wrong

A binomial GLM weighted by batch size looks like the textbook choice for defect counts. It assumes that a batch of 1,000 parts carries twice the information of a batch of 500. With batch-level variation that is false, the standard errors shrink too much, and null effects start to look significant:"""),
    ("code", """glm_df = model_df.assign(rate=model_df["defective_units"] / model_df["units_produced"])
glm = lambda f: smf.glm(f.replace("y ~", "rate ~"), glm_df, family=sm.families.Binomial(),
                        var_weights=glm_df["units_produced"]).fit(scale="X2")
g_full, g_op = glm(full_formula), glm(full_formula.replace("C(line)", "C(operator_id)"))
from scipy import stats
F = (g_full.deviance - g_op.deviance) / (g_full.df_resid - g_op.df_resid) / g_op.scale
print("weighted quasi-binomial GLM, operator within line: p =",
      f"{stats.f.sf(F, g_full.df_resid - g_op.df_resid, g_op.df_resid):.1e}")
print("weighted quasi-binomial GLM, machine age:          p =", f"{g_full.pvalues['machine_age_years']:.1e}")"""),
    ("md", """With this seed the weighted GLM declares the operator effect significant at p < 0.001, even though the operators have no effect by construction. Across 20 seeds the empirical-logit OLS recovered exactly the true driver set every time (`tests/test_reference.py`). This is a statistical trap that comes from the noise structure, which is realistic for production data."""),
    ("code", """name_map = {"mold_temp": "mold_temp", "humidity_pct (linear + squared)": "humidity_pct",
            "cycle_time_s": "cycle_time_s", "shift": "shift", "machine_age_years": "machine_age_years",
            "ambient_temp_c": "ambient_temp_c", "operator_id (within line)": "operator_id"}
answers["B1_direct_drivers"] = sorted(name_map[k] for k, p in tests.items() if p < 0.001)
answers["B2_leakage_columns"] = ["qc_inspection_min", "rework_cost_eur"]
answers["B1_direct_drivers"], answers["B2_leakage_columns"]"""),
    ("md", "## 3. Interpret salient features\n\n### 3.1 Which supplier is best? (Simpson's paradox)"),
    ("code", """pooled = lambda g: g["defective_units"].sum() / g["units_produced"].sum()
overall = df.groupby("supplier_name").apply(pooled).rename("overall")
within = df.groupby(["line", "supplier_name"]).apply(pooled).unstack()
alloc = pd.crosstab(df["line"], df["supplier_name"], normalize="columns").round(2)
print("Defect rate overall:\\n", (overall * 100).round(2).to_string(), "\\n")
print("Defect rate within each line (%):\\n", (within * 100).round(2), "\\n")
print("Where each supplier's batches go (share of supplier's batches):\\n", alloc)"""),
    ("code", """fig, axes = plt.subplots(1, 2, figsize=(9, 3), gridspec_kw={"width_ratios": [1, 3]})
colors = {"Alpha": BLUE, "Beta": ORANGE, "Gamma": AQUA}
axes[0].bar(overall.index, overall * 100, color=[colors[s] for s in overall.index], width=0.6)
axes[0].set_title("Overall", loc="left", fontsize=10); axes[0].set_ylabel("defect rate, %")
w = 0.26
for k, s in enumerate(within.columns):
    axes[1].bar(np.arange(4) + (k - 1) * w, within[s] * 100, width=w - 0.02, color=colors[s], label=s)
axes[1].set_xticks(range(4), within.index); axes[1].legend(frameon=False, fontsize=8, ncol=3)
axes[1].set_title("Within each line", loc="left", fontsize=10)
fig.suptitle("Beta looks worst overall but is best on every line", x=0.01, ha="left", fontsize=11)
plt.tight_layout()"""),
    ("code", """sup = full.params.filter(like="supplier_name")
print("Adjusted supplier effects vs Alpha (logit):\\n", sup.round(3).to_string())
effects = pd.concat([pd.Series({"Alpha": 0.0}), sup.rename(lambda s: s.split("T.")[1].rstrip("]"))])
answers["C1_best_supplier"] = str(effects.idxmin())
answers["C1_best_supplier"]"""),
    ("md", """**Beta looks worst overall but is best within every line.** About 75 % of Beta's batches go to L4, the oldest line with the highest defect rate, while Alpha mostly supplies the better lines. The aggregate comparison mixes up "which supplier" with "which line". After adjusting for line and process conditions, Beta has the lowest defect rate, so switching away from it on the evidence of the overall average would be a costly mistake."""),
    ("md", "### 3.2 Humidity optimum"),
    ("code", """b1, b2 = full.params["humidity_pct"], full.params["I(humidity_pct ** 2)"]
h_star = -b1 / (2 * b2)

rng = np.random.default_rng(0)
boot = []
for _ in range(200):
    s = model_df.sample(len(model_df), replace=True, random_state=rng.integers(1 << 31))
    p = smf.ols(full_formula, s).fit().params
    boot.append(-p["humidity_pct"] / (2 * p["I(humidity_pct ** 2)"]))
lo, hi = np.percentile(boot, [2.5, 97.5])
answers["C2_optimal_humidity_pct"] = round(float(h_star), 1)
print(f"humidity optimum: {h_star:.1f} %  (bootstrap 95% CI {lo:.1f}-{hi:.1f})")"""),
    ("md", """The quadratic term is positive, so the curve has a minimum. The fitted optimum sits in the middle of the observed range (15-75 %), with a narrow bootstrap interval. Operationally, keeping the hall near this humidity, together with cooler molds and no rushed cycles, are the actionable levers."""),
    ("md", "## Answer"),
    ("code", """Path("reference_answer.json").write_text(json.dumps(answers, indent=2) + "\\n")
print(json.dumps(answers, indent=2))"""),
    ("md", """## 4. Check against the answer key

*This section uses `eval/ground_truth.json`, which no model ever sees, and the benchmark's own scorer (`edabench.scorer`, defined in `docs/measure.md`).*"""),
    ("code", """from edabench.scorer import score_text

gt = json.loads(Path("../eval/ground_truth.json").read_text())
result = score_text(json.dumps(answers), gt)
print("total:", result["total"], "| sections:", result["sections"])
pd.DataFrame(result["questions"]).set_index("qid")[["score", "weight", "answer", "truth"]]"""),
]


def build() -> nbformat.NotebookNode:
    nb = nbformat.v4.new_notebook()
    nb.metadata["kernelspec"] = {"name": "python3", "display_name": "Python 3", "language": "python"}
    nb.cells = [nbformat.v4.new_markdown_cell(src) if kind == "md" else nbformat.v4.new_code_cell(src)
                for kind, src in CELLS]
    return nb


if __name__ == "__main__":
    nb = build()
    NotebookClient(nb, timeout=600, kernel_name="python3", resources={"metadata": {"path": str(HERE)}}).execute()
    nbformat.write(nb, HERE / "reference_solution.ipynb")
    print("wrote", HERE / "reference_solution.ipynb")
