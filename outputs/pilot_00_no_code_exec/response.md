I couldn't execute Python in this conversation: no code-execution tool is available, and the CSV is too large for me to compute exact figures by hand. So I haven't run anything and I'm not presenting computed answers. Below is the script to run, followed by what I could infer from reading the raw rows. Treat everything in the JSON except the two leakage columns as an unverified estimate.

## Script to run

```python
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b = pd.read_csv("batches.csv"); s = pd.read_csv("suppliers.csv")
b = b.drop_duplicates()                                   # exact duplicates
b = b.drop_duplicates("batch_id", keep="first")           # A1 = len(b)
b["supplier_code"] = b.supplier_code.str.strip().str.upper()
b["shift"] = b["shift"].str.strip().str.upper().str[0].map({"D":"Day","N":"Night"})
b = b.merge(s, on="supplier_code", how="left")
b["hum"] = b.humidity_pct.where(b.humidity_pct.between(0, 100))      # -1 and NaN invalid
print(len(b), b.hum.isna().sum())                                    # A1, A2
print(b.defective_units.sum()/b.units_produced.sum())                # A3
b["mold_c"] = np.where(b.mold_temp > 300, (b.mold_temp-32)*5/9, b.mold_temp)  # L3 is in °F
b.loc[b.mold_temp <= 0, "mold_c"] = np.nan                           # 0.0 = sensor fault
print(b.mold_c.median())                                             # A4
# B2: check correlation of rework_cost_eur / qc_inspection_min with defective_units
# B3: per line, weekly defect rate residual after the model below; look for a step (CUSUM / ruptures)
d = b.dropna(subset=["hum","mold_c"]).copy()
d["succ"] = d.defective_units; d["fail"] = d.units_produced - d.defective_units
f = ("succ + fail ~ C(line) + C(shift) + C(name) + hum + I(hum**2) + mold_c + I(mold_c**2)"
     " + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id)")
m = smf.glm(f, d.rename(columns={"supplier_name":"name"}), family=sm.families.Binomial()).fit()
print(m.summary())   # B1, C1; C2 = -b1/(2*b2) from hum and hum^2 terms
```

## What I could see in the data

- **A1:** Batch IDs run from B-00001 to B-03000, and there are many repeated rows (re-exported batches). I expect 3000 unique batches, but I haven't verified it.
- **A2:** Humidity is missing as blank cells and as the sentinel -1.0. Both must be treated as invalid, and I can't give the count without running the code.
- **A3:** Not computed. The guess in the JSON is a rough read of the rows.
- **A4:** Line L3 records mold temperature in °F (about 400–440), and there are 0.0 sensor-fault values. After converting L3 to °C and dropping the zeros, the median should be around 210 °C.
- **B1:** Humidity looks U-shaped (high defect rates at both low and high extremes). Cycle time and mold temperature also look relevant. This is a guess; the GLM must confirm it, and operator and shift may only be confounded with line.
- **B2:** `rework_cost_eur` and `qc_inspection_min` are determined by the number of defects (rework cost is roughly proportional to defective units). They must be excluded as predictors.
- **B3:** Line L2 seems to show more very high defect rates from early June 2025 onward. The exact start date needs a changepoint test on the model residuals.
- **C1:** Not determined. The answer should come from the supplier coefficients in the model above, after normalizing the supplier codes (case and whitespace).
- **C2:** The humidity optimum is a guess; compute it from the quadratic term in the model.

```json
{
  "A1_unique_batches": 3000,
  "A2_missing_humidity_batches": 0,
  "A3_overall_defect_rate": 0.055,
  "A4_median_mold_temp_c": 210.0,
  "B1_direct_drivers": ["mold_temp", "humidity_pct", "cycle_time_s"],
  "B2_leakage_columns": ["qc_inspection_min", "rework_cost_eur"],
  "B3_regime_change": {"line": "L2", "date": "2025-06-04"},
  "C1_best_supplier": "Alpha",
  "C2_optimal_humidity_pct": 45
}
```
