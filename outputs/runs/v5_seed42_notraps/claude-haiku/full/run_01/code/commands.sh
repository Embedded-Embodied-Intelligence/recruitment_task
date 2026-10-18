pwd && ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l "$f"; head -5 "$f"; done

cat > $TMPDIR/load.py << 'EOF'
import pandas as pd
b = pd.read_csv("batches.csv", dtype=str, keep_default_na=False)
print(b.shape); print(b.dtypes)
for c in b.columns:
    vals = b[c]
    print(c, "nunique", vals.nunique(), "empty", (vals.str.strip()=="").sum())
print(b["line"].value_counts(dropna=False))
print(b["shift"].value_counts(dropna=False))
print(b["operator_id"].value_counts(dropna=False))
print(b["supplier_code"].value_counts(dropna=False))
print(b["production_date"].str.len().value_counts())
bad = b[~b["production_date"].str.match(r"^\d{4}-\d{2}-\d{2}$", na=False)]
print("bad dates:", len(bad)); print(bad.head(20).to_string())
dup = b[b.duplicated(keep=False)]
print("exact dup rows:", len(dup), "unique dup rows:", b.duplicated().sum())
print("dup batch_id:", b["batch_id"].duplicated().sum())
print(b[b["batch_id"].duplicated(keep=False)].sort_values("batch_id").head(30).to_string())
EOF
python3 $TMPDIR/load.py

cat > $TMPDIR/num.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv", dtype=str, keep_default_na=False)
num = ["machine_age_years","ambient_temp_c","mold_temp","humidity_pct","cycle_time_s","units_produced","defective_units"]
for c in num:
    s = b[c]
    conv = pd.to_numeric(s.str.strip(), errors="coerce")
    nonnum = s[conv.isna()]
    print("==", c, "non-numeric:", nonnum.value_counts().head(10).to_dict(), "count", len(nonnum))
    print(conv.describe().round(3).to_dict())
    print("sorted low:", sorted(conv.dropna().unique())[:8], "high:", sorted(conv.dropna().unique())[-8:])
EOF
python3 $TMPDIR/num.py

cat > $TMPDIR/chk.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv")
print(b["production_date"].min(), b["production_date"].max())
print("batch_id pattern bad:", (~b.batch_id.str.match(r"^B-\d{6}$")).sum())
print("batch_id stripped/upper dup:", b.batch_id.str.strip().str.upper().duplicated().sum())
print("defect>produced:", (b.defective_units>b.units_produced).sum(), "units==0:", (b.units_produced==0).sum())
print("defect rate range:", (b.defective_units/b.units_produced).describe().round(4).to_dict())
print("content dup excluding id:", b.drop(columns="batch_id").duplicated().sum())
d = pd.to_datetime(b.production_date)
print("weekday counts:", d.dt.day_name().value_counts().to_dict())
print("dates per line:", b.groupby("line").production_date.nunique().to_dict())
print(b.groupby("line").agg(n=("batch_id","size"), dr=("defective_units","sum"), up=("units_produced","sum")).assign(rate=lambda x: x.dr/x.up).round(4))
print(b.groupby("supplier_code").agg(n=("batch_id","size"), dr=("defective_units","sum"), up=("units_produced","sum"), ct=("cycle_time_s","mean"), hum=("humidity_pct","mean"), mt=("mold_temp","mean")).assign(rate=lambda x: x.dr/x.up).round(4))
EOF
python3 $TMPDIR/chk.py

cat maintenance.csv; echo; cat suppliers.csv; echo; ls -la .claude; find .claude -type f | head -50

cat > $TMPDIR/sensor.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["period"]=np.where(b.date<"2025-04-14","pre","post")
print(b.groupby(["line","period"]).mold_temp.agg(["count","mean","median","std","min","max"]).round(2))
print(b.groupby(["line","period"]).ambient_temp_c.agg(["mean"]).round(2))
# within-day/line sensitivity: mold temp vs ambient and cycle
import statsmodels.formula.api as smf
EOF
python3 $TMPDIR/sensor.py 2>&1 | head -60

python3 -c "import statsmodels, sklearn, scipy; print(statsmodels.__version__, sklearn.__version__, scipy.__version__)" 2>&1; python3 -c "import pandas; print(pandas.__version__)"

python3 -c "import statsmodels; print(statsmodels.__version__)" 2>&1; python3 -c "import scipy; print(scipy.__version__)" 2>&1; python3 -c "import numpy; print(numpy.__version__)" 2>&1

cat > $TMPDIR/mt.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["post"]=(b.date>="2025-04-14").astype(int)
b["L1pre"]=((b.line=="L1")&(b.post==0)).astype(int)
d=b.dropna(subset=["mold_temp"])
m=smf.ols("mold_temp ~ C(line) + ambient_temp_c + C(supplier_code) + cycle_time_s + C(shift) + machine_age_years + L1pre", data=d).fit()
print(m.summary().tables[1])
m2=smf.ols("mold_temp ~ C(line) + ambient_temp_c + C(supplier_code) + cycle_time_s + C(shift) + machine_age_years + post*C(line)", data=d).fit()
print(m2.summary().tables[1])
EOF
python3 $TMPDIR/mt.py

cat > $TMPDIR/glm.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["rate"]=b.defective_units/b.units_produced
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
print("complete rows", len(d))
f="defective_units + ok ~ C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
d["ok"]=d.units_produced-d.defective_units
m=smf.glm("defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c", data=d, family=sm.families.Binomial()).fit()
print(m.summary())
print("dispersion (Pearson chi2/df):", m.pearson_chi2/m.df_resid)
EOF
python3 $TMPDIR/glm.py

cat > $TMPDIR/glm2.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["ok"]=b.units_produced-b.defective_units
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base, data=d, family=sm.families.Binomial()).fit()
m1=smf.glm(base+"+C(operator_id)", data=d, family=sm.families.Binomial()).fit()
from scipy import stats
lr=2*(m1.llf-m0.llf); df=m1.df_model-m0.df_model
print("operator LR", round(lr,2), "df", df, "p", stats.chi2.sf(lr,df))
m2=smf.glm(base+"+humidity_pct:C(supplier_code)", data=d, family=sm.families.Binomial()).fit()
print(m2.summary().tables[1])
lr=2*(m2.llf-m0.llf); print("humidity x supplier LR", round(lr,2), "p", stats.chi2.sf(lr,2))
m3=smf.glm(base+"+mold_temp:C(line)", data=d, family=sm.families.Binomial()).fit()
lr=2*(m3.llf-m0.llf); print("mold x line LR", round(lr,2), "p", stats.chi2.sf(lr,3))
m4=smf.glm(base+"+cycle_time_s:C(supplier_code)", data=d, family=sm.families.Binomial()).fit()
lr=2*(m4.llf-m0.llf); print("cycle x supplier LR", round(lr,2), "p", stats.chi2.sf(lr,2))
m5=smf.glm(base+"+C(operator_id)+ambient_temp_c+machine_age_years", data=d, family=sm.families.Binomial()).fit()
lr=2*(m5.llf-m0.llf); print("ambient+age+operator LR", round(lr,2))
print(m0.summary().tables[1])
d["res"]=d.defective_units/d.units_produced-m0.predict(d)
d["wk"]=d.date.dt.to_period("M")
print(d.groupby(["line","wk"]).apply(lambda g: pd.Series({"obs":g.defective_units.sum()/g.units_produced.sum(),"exp":(m0.predict(g)*g.units_produced).sum()/g.units_produced.sum()})).round(4).unstack(0).to_string())
EOF
python3 $TMPDIR/glm2.py 2>&1 | grep -v Warning

cat > $TMPDIR/nl.py << 'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["ok"]=b.units_produced-b.defective_units
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base,data=d,family=sm.families.Binomial()).fit()
d["pred"]=m0.predict(d)
d["expd"]=d.pred*d.units_produced
print("dispersion", round(m0.pearson_chi2/m0.df_resid,3))
for name,add in [("hum2","+I(humidity_pct**2)"),("hum_spline","+bs(humidity_pct)"),("mold2","+I(mold_temp**2)"),("cyc2","+I(cycle_time_s**2)")]:
    try:
        f=base+add if name!="hum_spline" else base+"+ np.maximum(humidity_pct-30,0)+np.maximum(humidity_pct-50,0)"
        m=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
        lr=2*(m.llf-m0.llf); print(name, round(lr,2), "p", round(stats.chi2.sf(lr,1 if name!="hum_spline" else 2),5))
    except Exception as e: print(name,"err",e)
# binned humidity effect
d["hbin"]=pd.cut(d.humidity_pct,bins=np.arange(10,80,5))
g=d.groupby("hbin",observed=True).apply(lambda x: pd.Series({"n":len(x),"obs":x.defective_units.sum()/x.units_produced.sum(),"exp":x.expd.sum()/x.units_produced.sum()}),include_groups=False)
print(g.round(4).to_string())
d["mbin"]=pd.cut(d.mold_temp,bins=np.arange(190,235,4))
g=d.groupby("mbin",observed=True).apply(lambda x: pd.Series({"n":len(x),"obs":x.defective_units.sum()/x.units_produced.sum(),"exp":x.expd.sum()/x.units_produced.sum()}),include_groups=False)
print(g.round(4).to_string())
d["wk"]=d.date.dt.to_period("M")
t=d.groupby(["line","wk"]).apply(lambda x: pd.Series({"obs":x.defective_units.sum()/x.units_produced.sum(),"exp":x.expd.sum()/x.units_produced.sum()}),include_groups=False)
print(t.round(4).unstack(0).to_string())
EOF
python3 $TMPDIR/nl.py

cat > $TMPDIR/cp.py << 'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["ok"]=b.units_produced-b.defective_units
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base,data=d,family=sm.families.Binomial()).fit()
d["expd"]=m0.predict(d)*d.units_produced
print("rank", np.linalg.matrix_rank(m0.model.exog), m0.model.exog.shape)
res=[]
for line,g in d.groupby("line"):
    g=g.sort_values("date")
    dates=sorted(g.date.unique())
    best=None
    for cut in dates[10:-10]:
        pre=g[g.date<cut]; post=g[g.date>=cut]
        O1,E1=pre.defective_units.sum(),pre.expd.sum()
        O2,E2=post.defective_units.sum(),post.expd.sum()
        O=O1+O2; E=E1+E2
        # Poisson LR for ratio shift
        ll=lambda o,e: o*np.log(o/e) if o>0 else 0
        r=2*(ll(O1,E1)+ll(O2,E2)-ll(O,E))
        # Ratio pre/post
        if best is None or r>best[0]: best=(r,pd.Timestamp(cut).date(),round(O1/E1,3),round(O2/E2,3))
    res.append((line,)+best)
for r in res: print(r)
EOF
python3 $TMPDIR/cp.py

cat > $TMPDIR/diag.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
print(pd.crosstab(b.operator_id,[b.shift]).to_string())
print(pd.crosstab(b.operator_id,b.line).to_string())
b["wk"]=b.date.dt.to_period("M")
t=b.groupby(["line","wk"]).agg(n=("batch_id","size"),units=("units_produced","mean"),ct=("cycle_time_s","mean"),mt=("mold_temp","mean"),hum_na=("humidity_pct",lambda x: x.isna().mean()),mt_na=("mold_temp",lambda x: x.isna().mean()),dr=("defective_units","sum"),up=("units_produced","sum"))
t["rate"]=t.dr/t.up
print(t.drop(columns=["dr","up"]).round(3).to_string())
EOF
python3 $TMPDIR/diag.py

cat > $TMPDIR/diag.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
print(pd.crosstab(b.operator_id,b["shift"]).to_string())
print(pd.crosstab(b.operator_id,b.line).to_string())
b["wk"]=b.date.dt.to_period("M")
t=b.groupby(["line","wk"]).agg(n=("batch_id","size"),units=("units_produced","mean"),ct=("cycle_time_s","mean"),mt=("mold_temp","mean"),hum_na=("humidity_pct",lambda x: x.isna().mean()),mt_na=("mold_temp",lambda x: x.isna().mean()),dr=("defective_units","sum"),up=("units_produced","sum"))
t["rate"]=t.dr/t.up
print(t.drop(columns=["dr","up"]).round(3).to_string())
EOF
python3 $TMPDIR/diag.py

cat > $TMPDIR/stuck.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b=b.sort_values(["date","batch_id"]).reset_index(drop=True)
print("humidity top repeats:"); print(b.humidity_pct.value_counts().head(10).to_string())
print("mold top repeats:"); print(b.mold_temp.value_counts().head(10).to_string())
print("ambient top repeats:"); print(b.ambient_temp_c.value_counts().head(5).to_string())
# runs of identical consecutive values per line
for col in ["humidity_pct","mold_temp"]:
    for line,g in b.groupby("line"):
        v=g[col]
        run=(v!=v.shift()).cumsum()
        rl=g.groupby(run)[col].agg(["size","first"])
        mx=rl["size"].max()
        if mx>=3: print(col,line,"longest identical run",mx, rl.sort_values("size").tail(3).to_dict("index"))
# humidity sensor per line over time: monthly count of valid values
b["m"]=b.date.dt.to_period("M")
print(b.assign(hv=b.humidity_pct.notna()).groupby(["line"]).hv.mean().round(3).to_dict())
print(b.assign(mv=b.mold_temp.notna()).groupby(["line"]).mv.mean().round(3).to_dict())
EOF
python3 $TMPDIR/stuck.py

cat > $TMPDIR/cum.py << 'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["ok"]=b.units_produced-b.defective_units
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base,data=d,family=sm.families.Binomial()).fit()
d["E"]=m0.predict(d)*d.units_produced
d["wk"]=d.date.dt.to_period("W")
t=d.groupby(["line","wk"]).agg(O=("defective_units","sum"),E=("E","sum"),U=("units_produced","sum"))
t["oe"]=(t.O/t.E).round(3)
print(t.oe.unstack(0).to_string())
for line in ["L1","L2","L3","L4"]:
    x=d[d.line==line].sort_values("date")
    cs=(x.defective_units-x.E).cumsum()
    print(line, "cum O-E range", round(cs.min(),1), round(cs.max(),1), "final", round(cs.iloc[-1],1))
EOF
python3 $TMPDIR/cum.py

cat > $TMPDIR/clean.py << 'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b = pd.read_csv("batches.csv")
b["date"]=pd.to_datetime(b.production_date)
b["ok"]=b.units_produced-b.defective_units
m=pd.read_csv("maintenance.csv",parse_dates=["date"])
cl=m[m.event=="mold_cleaning"][["date","line"]]
def last_clean(row):
    c=cl[(cl.line==row.line)&(cl.date<=row.date)]
    return (row.date-c.date.max()).days if len(c) else np.nan
b["days_since"]=b.apply(last_clean,axis=1)
print(b.days_since.describe().round(2).to_dict())
print("missing before first clean:", b.days_since.isna().sum())
print(b.days_since.value_counts().sort_index().to_string())
b.to_pickle(f"{__import__('os').environ['TMPDIR']}/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base,data=d,family=sm.families.Binomial()).fit()
m1=smf.glm(base+"+days_since",data=d,family=sm.families.Binomial()).fit()
print("m1 dispersion", round(m1.pearson_chi2/m1.df_resid,3), "days coef", m1.params["days_since"], m1.bse["days_since"])
m2=smf.glm(base+"+C(days_since)",data=d,family=sm.families.Binomial()).fit()
print("LR days (cat vs none)", round(2*(m2.llf-m0.llf),2))
EOF
python3 $TMPDIR/clean.py

cat > $TMPDIR/dsb.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
b["rate"]=b.defective_units/b.units_produced
g=b.groupby("days_since").agg(n=("batch_id","size"),D=("defective_units","sum"),U=("units_produced","sum"))
g["rate"]=(g.D/g.U).round(4)
print(g.to_string())
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
d["post14"]=(d.days_since>14).astype(int)
d["over"]=np.maximum(d.days_since-14,0)
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
d["ok"]=d.units_produced-d.defective_units
for extra in ["+post14","+over","+post14+over","+np.maximum(days_since-13,0)","+np.maximum(days_since-10,0)","+np.maximum(days_since-7,0)"]:
    m=smf.glm(base+extra,data=d,family=sm.families.Binomial()).fit()
    print(extra, "dispersion", round(m.pearson_chi2/m.df_resid,3), "llf", round(m.llf,2), {k:round(v,5) for k,v in m.params.items() if "days" in k or "post" in k or "over" in k or "np.max" in k})
EOF
python3 $TMPDIR/dsb.py

cat > $TMPDIR/dsb2.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
d["ok"]=d.units_produced-d.defective_units
d["dbin"]=pd.cut(d.days_since,[-1,6,13,20,34],labels=["0-6","7-13","14-20","21+"])
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base,data=d,family=sm.families.Binomial()).fit()
m1=smf.glm(base+"+C(dbin)",data=d,family=sm.families.Binomial()).fit()
print(m1.params.filter(like="dbin").round(4).to_string(), m1.bse.filter(like="dbin").round(4).to_string())
lr=2*(m1.llf-m0.llf); print("LR dbin", round(lr,2), "p", stats.chi2.sf(lr,3))
m2=smf.glm(base+"+C(days_since)",data=d,family=sm.families.Binomial()).fit()
lr=2*(m2.llf-m0.llf); print("LR days categorical", round(lr,2), "df", m2.df_model-m0.df_model, "p", stats.chi2.sf(lr,m2.df_model-m0.df_model))
m3=smf.glm(base+"+days_since",data=d,family=sm.families.Binomial()).fit()
lr=2*(m3.llf-m0.llf); print("LR linear days", round(lr,2))
print("m0 llf", m0.llf, "m0 dispersion", m0.pearson_chi2/m0.df_resid)
EOF
python3 $TMPDIR/dsb2.py

cat > $TMPDIR/quasi.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
d["ok"]=d.units_produced-d.defective_units
d["cl"]=d.line+"_"+d.production_date
full="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)"
m=smf.glm(full,data=d,family=sm.families.Binomial()).fit(scale="X2")
mc=smf.glm(full,data=d,family=sm.families.Binomial()).fit(cov_type="cluster",cov_kwds={"groups":pd.factorize(d.cl)[0]})
print("scale", round(m.scale,3))
tab=pd.DataFrame({"coef":m.params,"p_quasi":m.pvalues,"p_cluster":mc.pvalues})
print(tab.round(4).to_string())
# drop-one tests with quasi scale
base=m0=smf.glm(full,data=d,family=sm.families.Binomial()).fit()
def dropTest(term_str, label):
    f=full.replace(term_str,"")
    mm=smf.glm(f,data=d,family=sm.families.Binomial()).fit()
    lr=2*(m.llf if False else base.llf-mm.llf)
    df=base.df_model-mm.df_model
    print(f"{label:22s} LR={lr:8.2f} df={df:.0f} quasi-p={stats.chi2.sf(lr/m.scale, df):.4g}")
for t,l in [("+C(shift)","shift"),("+C(supplier_code)","supplier"),("+mold_temp","mold_temp"),("+humidity_pct","humidity"),("+cycle_time_s","cycle_time"),("+machine_age_years","machine_age"),("+ambient_temp_c","ambient"),("+C(operator_id)","operator"),("+C(line)","line")]:
    dropTest(t,l)
EOF
python3 $TMPDIR/quasi.py

cat > $TMPDIR/quasi2.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
d["ok"]=d.units_produced-d.defective_units
terms={"line":"C(line)","shift":"C(shift)","supplier":"C(supplier_code)","mold":"mold_temp","humidity":"humidity_pct","cycle":"cycle_time_s","age":"machine_age_years","ambient":"ambient_temp_c","operator":"C(operator_id)"}
def fit(ts):
    f="defective_units + ok ~ "+"+".join(terms[t] for t in ts)
    return smf.glm(f,data=d,family=sm.families.Binomial()).fit()
full_ts=list(terms)
full_op=[t for t in full_ts if t!="line"]
mf=fit(full_op)
phi=mf.pearson_chi2/mf.df_resid
print("dispersion (operator model):", round(phi,3), "rank", np.linalg.matrix_rank(mf.model.exog), mf.model.exog.shape[1])
print(pd.DataFrame({"coef":mf.params,"p_quasi":mf.pvalues}).round(4).to_string())
for t in full_op:
    red=fit([x for x in full_op if x!=t])
    lr=2*(mf.llf-red.llf); df=mf.df_model-red.df_model
    print(f"drop {t:10s} LR={lr:9.2f} df={df:.0f} quasi-p={stats.chi2.sf(lr/phi,df):.4g}")
m_line=fit([x for x in full_ts if x!="operator"])
phi2=m_line.pearson_chi2/m_line.df_resid
print("with line instead of operator dispersion", round(phi2,3))
for t in ["line","operator"]:
    pass
lr=2*(mf.llf-m_line.llf); df=mf.df_model-m_line.df_model
print("operator vs line-only (within-line operator effect) LR", round(lr,2),"df",df,"quasi-p",round(stats.chi2.sf(lr/phi,df),4))
EOF
python3 $TMPDIR/quasi2.py

cat > $TMPDIR/cp2.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
b["ok"]=b.units_produced-b.defective_units
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
f="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm("defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s",data=d,family=sm.families.Binomial()).fit()
phi=m0.pearson_chi2/m0.df_resid
print("phi (no operator)", round(phi,3))
d["E"]=m0.predict(d)*d.units_produced
def scan(x, label):
    x=x.sort_values("date")
    best=(0,None)
    for cut in sorted(x.date.unique())[15:-15]:
        pre=x[x.date<cut]; post=x[x.date>=cut]
        O1,E1=pre.defective_units.sum(),pre.E.sum(); O2,E2=post.defective_units.sum(),post.E.sum()
        ll=lambda o,e: o*np.log(o/e)
        r=2*(ll(O1,E1)+ll(O2,E2)-ll(O1+O2,E1+E2))/phi
        if r>best[0]: best=(r,pd.Timestamp(cut).date(),round(O1/E1,3),round(O2/E2,3))
    return best
for line in ["L1","L2","L3","L4"]:
    print(line, scan(d[d.line==line],line))
print("L1 at sensor date 2025-04-14:")
x=d[d.line=="L1"]
pre=x[x.date<"2025-04-14"]; post=x[x.date>="2025-04-14"]
for nm,g in [("pre",pre),("post",post)]: print(nm, round(g.defective_units.sum()/g.E.sum(),3))
ll=lambda o,e: o*np.log(o/e)
O1,E1,O2,E2=pre.defective_units.sum(),pre.E.sum(),post.defective_units.sum(),post.E.sum()
print("LR at sensor date scaled", round(2*(ll(O1,E1)+ll(O2,E2)-ll(O1+O2,E1+E2))/phi,2))
# missing-data rows
bm=b[b.humidity_pct.isna()|b.mold_temp.isna()].copy()
print("missing rows", len(bm), "rate", round(bm.defective_units.sum()/bm.units_produced.sum(),4))
print(bm.groupby("line").apply(lambda g: pd.Series({"n":len(g),"rate":g.defective_units.sum()/g.units_produced.sum()}),include_groups=False).round(4))
EOF
python3 $TMPDIR/cp2.py

cat > $TMPDIR/c.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
b["ok"]=b.units_produced-b.defective_units
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
d["over14"]=np.maximum(d.days_since-14,0)
d["post14"]=(d.days_since>14).astype(int)
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s"
m0=smf.glm(base,data=d,family=sm.families.Binomial()).fit(); phi=m0.pearson_chi2/m0.df_resid
m1=smf.glm(base+"+post14:C(line)",data=d,family=sm.families.Binomial()).fit()
lr=2*(m1.llf-m0.llf); print("post14 by line LR/phi", round(lr/phi,2), "df 4 p", round(stats.chi2.sf(lr/phi,4),4))
print(m1.params.filter(like="post14").round(4).to_string())
m2=smf.glm(base+"+post14",data=d,family=sm.families.Binomial()).fit()
print("post14 overall coef", round(m2.params["post14"],4), "se", round(m2.bse["post14"],4), "LR/phi", round(2*(m2.llf-m0.llf)/phi,2))
# humidity shape within Alpha
a=d[d.supplier_code=="SP-01"]
print("Alpha n", len(a))
ma=smf.glm("defective_units + ok ~ C(line)+C(shift)+mold_temp+humidity_pct+cycle_time_s",data=a,family=sm.families.Binomial()).fit()
mq=smf.glm("defective_units + ok ~ C(line)+C(shift)+mold_temp+humidity_pct+I(humidity_pct**2)+cycle_time_s",data=a,family=sm.families.Binomial()).fit()
print("Alpha hum linear", round(ma.params["humidity_pct"],5), "quad", mq.params.filter(like="I(").round(6).to_dict(), mq.pvalues.filter(like="I(").round(4).to_dict())
b1=a.assign(bin=pd.cut(a.humidity_pct,[10,20,30,40,50,60,75])).groupby("bin",observed=True).apply(lambda g: pd.Series({"n":len(g),"rate":g.defective_units.sum()/g.units_produced.sum()}),include_groups=False)
print(b1.round(4).to_string())
# humidity interaction on supplier for quasi test
mi=smf.glm(base+"+humidity_pct:C(supplier_code)",data=d,family=sm.families.Binomial()).fit()
print("hum x supplier quasi p", round(stats.chi2.sf(2*(mi.llf-m0.llf)/phi,2),4))
# units_produced vs rate relation
print("corr rate vs units", round(np.corrcoef(b.units_produced, b.defective_units/b.units_produced)[0,1],4))
print("corr defect vs units", round(np.corrcoef(b.units_produced, b.defective_units)[0,1],4))
EOF
python3 $TMPDIR/c.py

cat > $TMPDIR/final.py << 'EOF'
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore")
import statsmodels.api as sm
import statsmodels.formula.api as smf
b=pd.read_pickle(os.environ["TMPDIR"]+"/b.pkl")
s=pd.read_csv("suppliers.csv")
b=b.merge(s,on="supplier_code",how="left")
b["ok"]=b.units_produced-b.defective_units
print("A1 unique batches", b.batch_id.nunique())
print("A2 humidity missing", b.humidity_pct.isna().sum())
print("A3 overall rate", repr(b.defective_units.sum()/b.units_produced.sum()))
print("A4 median mold", b.mold_temp.median(), "n", b.mold_temp.notna().sum())
print("humidity max", b.humidity_pct.max())
d=b.dropna(subset=["mold_temp","humidity_pct"]).copy()
base="defective_units + ok ~ C(line)+C(shift)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+post14"
d["post14"]=(d.days_since>14).astype(int)
m=smf.glm(base,data=d,family=sm.families.Binomial()).fit()
print(m.params.round(5).to_string())
# imputed full data for prediction
f=b.copy()
f["post14"]=(f.days_since>14).astype(int)
f["mold_temp"]=f.mold_temp.fillna(d.mold_temp.mean())
f["humidity_pct"]=f.humidity_pct.fillna(d.humidity_pct.mean())
f["ok"]=f.units_produced-f.defective_units
pf=m.predict(f)
# C1 counterfactual, cycle=30 for all, all batches
rows=[]
for sc,name in s.set_index("supplier_code").supplier_name.items():
    g=f.copy(); g["supplier_code"]=sc; g["cycle_time_s"]=30.0
    p=m.predict(g)
    rows.append((name, round((p*g.units_produced).sum()/g.units_produced.sum(),6)))
print("C1 counterfactual", rows)
# complete-case version
rows2=[]
for sc,name in s.set_index("supplier_code").supplier_name.items():
    g=d.copy(); g["supplier_code"]=sc; g["cycle_time_s"]=30.0
    p=m.predict(g)
    rows2.append((name, round((p*g.units_produced).sum()/g.units_produced.sum(),6)))
print("C1 complete-case", rows2)
# C3 counterfactual: post14 -> 0, keep recorded defects scaled by model ratio
g=f.copy()
p_old=pf
g2=f.copy(); g2["post14"]=0
p_new=m.predict(g2)
D_new=f.defective_units*(p_new/p_old)
print("C3 with cleaning", round(D_new.sum()/f.units_produced.sum(),6), "baseline", round(f.defective_units.sum()/f.units_produced.sum(),6))
# C2 Alpha
ga=f[f.supplier_code=="SP-01"].copy()
hs=np.linspace(12.1,72.3,613)
best=None
for h in hs:
    g=ga.copy(); g["humidity_pct"]=h
    p=m.predict(g); r=(p*g.units_produced).sum()/g.units_produced.sum()
    if best is None or r<best[1]: best=(h,r)
print("C2 best humidity", best)
EOF
python3 $TMPDIR/final.py
