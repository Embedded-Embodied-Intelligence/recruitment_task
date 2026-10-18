ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/explore.py << 'EOF'
import pandas as pd
b = pd.read_csv("batches.csv", dtype=str, keep_default_na=False)
print(b.shape); print(b.dtypes)
for c in b.columns:
    vals = b[c]
    print(f"\n-- {c}: nunique={vals.nunique()} empty={(vals.str.strip()=='').sum()}")
    print(vals.value_counts().head(12).to_dict() if vals.nunique()<40 else vals.sample(10, random_state=1).tolist())
print("\nduplicate batch_id rows:", b.batch_id.duplicated().sum())
print("fully duplicated rows:", b.duplicated().sum())
print(pd.read_csv("suppliers.csv"))
m = pd.read_csv("maintenance.csv")
print(m.event.value_counts(), m.note.value_counts(dropna=False), m.line.value_counts())
EOF
python3 $TMPDIR/explore.py

cat > $TMPDIR/explore2.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv")
print(b.describe().T)
print(b.isna().sum())
m = pd.read_csv("maintenance.csv")
print(m[m.event!='mold_cleaning'])
print(m.date.min(), m.date.max())
# mold temp distribution check
print(np.histogram(b.mold_temp.dropna(), bins=20))
print("mold_temp <100:", (b.mold_temp<100).sum(), " >300:", (b.mold_temp>300).sum())
print(b[b.mold_temp<150][['batch_id','production_date','line','mold_temp']].head(40))
print("humidity out of [0,100]:", ((b.humidity_pct<0)|(b.humidity_pct>100)).sum())
print(np.histogram(b.humidity_pct.dropna(), bins=20))
print("defective>units:", (b.defective_units>b.units_produced).sum(), "units<=0:", (b.units_produced<=0).sum())
print("date range", b.production_date.min(), b.production_date.max())
print(b.groupby('line').production_date.agg(['min','max']))
# content duplicates ignoring batch_id
cols=[c for c in b.columns if c!='batch_id']
print("content dups:", b.duplicated(subset=cols).sum())
print("bad dates:", pd.to_datetime(b.production_date, errors='coerce').isna().sum())
EOF
python3 $TMPDIR/explore2.py

cat > $TMPDIR/explore3.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv("batches.csv", parse_dates=["production_date"])
b['rate']=b.defective_units/b.units_produced
b['month']=b.production_date.dt.to_period('M')
print(b.groupby(['line','month']).agg(mt=('mold_temp','mean'),n=('batch_id','size'),rate=('rate','mean')).round(4).unstack(0).to_string())
l1=b[b.line=='L1']
for lab,sub in [('before',l1[l1.production_date<'2025-04-14']),('after',l1[l1.production_date>='2025-04-14'])]:
    print(lab, sub.mold_temp.mean().round(2), sub.mold_temp.median(), len(sub))
print(b.groupby('line').mold_temp.median())
EOF
python3 $TMPDIR/explore3.py

python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)" 2>&1; cat > $TMPDIR/model1.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
import statsmodels.api as sm
b = pd.read_csv("batches.csv", parse_dates=["production_date"])
s = pd.read_csv("suppliers.csv")
b = b.merge(s[['supplier_code','supplier_name','resin_grade','pre_dried','recipe_cycle_time_s']], on='supplier_code')
b['fail']=b.defective_units; b['ok']=b.units_produced-b.defective_units
b['rate']=b.defective_units/b.units_produced
print(b.groupby('supplier_name').agg(n=('batch_id','size'),rate=('rate','mean'),pooled=('defective_units','sum'),units=('units_produced','sum')).assign(pooled_rate=lambda d: d.pooled/d.units))
print(b.groupby('shift').rate.mean(), b.groupby('operator_id').rate.mean().describe())
print(b.groupby('line').rate.mean())
print(b.groupby('supplier_code').cycle_time_s.mean(), b.groupby('supplier_code').recipe_cycle_time_s.mean())
print(b[['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','rate']].corr(numeric_only=True)['rate'])
d=b.dropna(subset=['mold_temp','humidity_pct'])
f="fail + ok ~ C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
g=smf.glm("defective_units + ok ~ C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c", data=d, family=sm.families.Binomial()).fit()
print(g.summary())
EOF
python3 $TMPDIR/model1.py 2>&1 | head -150

cat > $TMPDIR/model2.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv", parse_dates=["production_date"])
s = pd.read_csv("suppliers.csv")
b = b.merge(s[['supplier_code','supplier_name','pre_dried']], on='supplier_code')
b['num_id']=b.batch_id.str[2:].astype(int)
b['rate']=b.defective_units/b.units_produced
b['ok']=b.units_produced-b.defective_units
print("batch_id num vs rate corr:", np.corrcoef(b.num_id,b.rate)[0,1].round(3))
print("units vs rate corr:", np.corrcoef(b.units_produced,b.rate)[0,1].round(3))
print("defect count vs units corr:", np.corrcoef(b.units_produced,b.defective_units)[0,1].round(3))
# cycle time: check whether it varies with supplier/line/shift/operator
print(smf.ols("cycle_time_s ~ C(line)+C(shift)+C(supplier_code)+C(operator_id)+mold_temp+humidity_pct+ambient_temp_c+machine_age_years", data=b.dropna()).fit().summary().tables[1].as_text()[:2500])
# mold temp sensor effect on L1
l1=b[(b.line=='L1')].dropna(subset=['mold_temp','humidity_pct']).copy()
l1['post']=(l1.production_date>='2025-04-14').astype(int)
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
d['post_L1']=((d.line=='L1')&(d.production_date>='2025-04-14')).astype(int)
d['L1pre']=((d.line=='L1')&(d.production_date<'2025-04-14')).astype(int)
g=smf.glm("defective_units + ok ~ C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c+L1pre", data=d.assign(ok=d.units_produced-d.defective_units), family=sm.families.Binomial()).fit()
print("L1pre coef", g.params['L1pre'], g.bse['L1pre'])
for dt in ['before','after']:
    sub = l1[(l1.post==0)] if dt=='before' else l1[l1.post==1]
    m=smf.glm("defective_units + (units_produced-defective_units) ~ mold_temp+humidity_pct+cycle_time_s+C(shift)", data=sub, family=sm.families.Binomial()).fit()
    print(dt, m.params.round(4).to_dict())
EOF
python3 $TMPDIR/model2.py 2>&1 | grep -v Warning | head -120

cat > $TMPDIR/sensor.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
b = pd.read_csv("batches.csv", parse_dates=["production_date"]).dropna(subset=['mold_temp'])
b['post']=(b.production_date>='2025-04-14').astype(int)
b['L1']=(b.line=='L1').astype(int)
b['L1post']=b.L1*b.post
b['L1pre']=b.L1*(1-b.post)
print(b.groupby(['line','post']).mold_temp.agg(['mean','std','median','size']).round(2))
m=smf.ols("mold_temp ~ C(line)+C(shift)+C(operator_id)+ambient_temp_c+machine_age_years+cycle_time_s+humidity_pct+L1pre+L1post", data=b.dropna(subset=['humidity_pct'])).fit()
print(m.params[['L1pre','L1post']], m.bse[['L1pre','L1post']])
print(b[(b.line=='L1')&(b.production_date.between('2025-04-07','2025-04-21'))][['production_date','shift','mold_temp']].sort_values('production_date').to_string())
print("overall median", b.mold_temp.median(), "n", b.mold_temp.size)
EOF
python3 $TMPDIR/sensor.py 2>&1 | grep -v Warn

cat > $TMPDIR/model3.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b = pd.read_csv("batches.csv", parse_dates=["production_date"])
s = pd.read_csv("suppliers.csv")
b = b.merge(s[['supplier_code','supplier_name','pre_dried']], on='supplier_code')
b['ok']=b.units_produced-b.defective_units
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
def fit(f, data=d):
    return smf.glm("defective_units + ok ~ "+f, data=data, family=sm.families.Binomial()).fit()
full=fit(base)
print("full llf", full.llf, "AIC", full.aic)
tests={
 'operator':"C(operator_id)", 'shift':"C(shift)", 'machine_age':"machine_age_years", 'ambient':"ambient_temp_c",
 'mold_temp':"mold_temp", 'humidity':"humidity_pct", 'cycle':"cycle_time_s", 'supplier':"C(supplier_code)", 'line':"C(line)"}
for k,t in tests.items():
    red=base
    for term in t.split('+') if False else [t]:
        pass
    # reduced model drops this term
    rterms=[x for x in base.split('+') if x.strip()!=t.strip()]
    if k=='operator': rterms=[x for x in base.split('+') if 'operator' not in x]
    if k=='supplier': rterms=[x for x in base.split('+') if 'supplier' not in x]
    if k=='line': rterms=[x for x in base.split('+') if 'line' not in x]
    r=fit("+".join(rterms))
    lr=2*(full.llf-r.llf); df=full.df_model-r.df_model
    print(f"{k:12s} LR={lr:8.2f} df={df:.0f} p={stats.chi2.sf(lr,df):.3g}")
# nonlinearity
for extra in ["I(humidity_pct**2)","I(mold_temp**2)","I(cycle_time_s**2)","humidity_pct:C(supplier_code)","mold_temp:C(supplier_code)","humidity_pct:C(pre_dried)","humidity_pct:C(line)"]:
    dd=d.assign(pre=d.pre_dried.map({'yes':1,'no':0}))
    f2=base+"+"+extra
    m2=fit(f2, data=dd)
    lr=2*(m2.llf-full.llf); df=m2.df_model-full.df_model
    print(extra, "LR", round(lr,2), "df", df, "p", round(stats.chi2.sf(lr,df),4) if df>0 else None)
EOF
python3 $TMPDIR/model3.py 2>&1 | grep -v -i warn

cat $TMPDIR/../../../../dev/null 2>/dev/null; cd "$PWD" && python3 -c "
import pandas as pd
m=pd.read_csv('maintenance.csv', parse_dates=['date'])
for l,g in m.groupby('line'):
    g=g.sort_values('date'); print(l, g.date.dt.strftime('%m-%d').tolist())
    print('  gaps', g.date.diff().dt.days.dropna().astype(int).tolist())
print(m[m.event!='mold_cleaning'])
print(m.duplicated(['date','line']).sum(),'dup cleaning rows')
"

cat > $TMPDIR/clean.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
b = pd.read_csv("batches.csv", parse_dates=["production_date"])
s = pd.read_csv("suppliers.csv")
b = b.merge(s[['supplier_code','supplier_name','pre_dried']], on='supplier_code')
m = pd.read_csv("maintenance.csv", parse_dates=["date"])
cl = m[m.event=='mold_cleaning']
def dsc(row):
    g = cl[(cl.line==row.line)&(cl.date<=row.production_date)]
    return (row.production_date - g.date.max()).days
b['dsc']=b.apply(dsc,axis=1)
print(b.dsc.describe()); print(b.dsc.value_counts().sort_index().to_string())
b['ok']=b.units_produced-b.defective_units
d=b.dropna(subset=['mold_temp','humidity_pct']).copy()
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
full=smf.glm("defective_units + ok ~ "+base+"+dsc", data=d, family=sm.families.Binomial()).fit()
print("dsc coef", full.params['dsc'], full.bse['dsc'], full.pvalues['dsc'])
# nonlinear: categorical bins
d['bin']=pd.cut(d.dsc,[-1,3,7,10,14,18,22,40],labels=['0-3','4-7','8-10','11-14','15-18','19-22','23+'])
f2=smf.glm("defective_units + ok ~ "+base+"+C(bin)", data=d, family=sm.families.Binomial()).fit()
print(f2.params.filter(like='bin').round(4), f2.pvalues.filter(like='bin').round(4))
d.to_pickle(f"{__import__('os').environ['TMPDIR']}/d.pkl")
EOF
python3 $TMPDIR/clean.py 2>&1 | grep -v -i warn

cat > $TMPDIR/clean2.py << 'EOF'
import pandas as pd, numpy as np, os
import statsmodels.api as sm
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['over14']=(d.dsc>14).astype(int)
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
m=smf.glm("defective_units + ok ~ "+base+"+over14", data=d, family=sm.families.Binomial()).fit()
print("over14", m.params['over14'].round(4), m.pvalues['over14'].round(4))
m2=smf.glm("defective_units + ok ~ "+base+"+dsc:C(line)", data=d, family=sm.families.Binomial()).fit()
print(m2.params.filter(like='dsc').round(4), m2.pvalues.filter(like='dsc').round(3))
d['rate']=d.defective_units/d.units_produced
print(d.groupby('dsc').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_string())
EOF
python3 $TMPDIR/clean2.py 2>&1 | grep -v -i warn

cat > $TMPDIR/regime.py << 'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['ok']=d.units_produced-d.defective_units
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
r0=smf.glm("defective_units + ok ~ "+base, data=d, family=sm.families.Binomial()).fit()
d['resid_dev']=r0.resid_pearson
res=[]
for line in ['L1','L2','L3','L4']:
    sub=d[d.line==line]
    dates=sorted(sub.production_date.unique())[10:-10]
    best=None
    for dt in dates:
        dd=d.assign(step=((d.line==line)&(d.production_date>=dt)).astype(int))
        m=smf.glm("defective_units + ok ~ "+base+"+step", data=dd, family=sm.families.Binomial()).fit()
        lr=2*(m.llf-r0.llf)
        if best is None or lr>best[1]: best=(pd.Timestamp(dt).date(), lr, m.params['step'], m.pvalues['step'])
    print(line, best)
    # rolling mean residual
    s=sub.sort_values('production_date')
    print(s.groupby(s.production_date.dt.to_period('M')).resid_dev.mean().round(2).to_dict())
EOF
python3 $TMPDIR/regime.py

cd "$TMPDIR" && python3 -W ignore regime.py 2>/dev/null | grep -v -i warn

cat > $TMPDIR/regime2.py << 'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['ok']=d.units_produced-d.defective_units
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
r0=smf.glm("defective_units + ok ~ "+base, data=d, family=sm.families.Binomial()).fit()
for line,dt in [('L2','2025-05-27'),('L1','2025-08-15'),('L4','2025-02-05'),('L3','2025-09-01')]:
    sub=d[d.line==line].copy(); sub['post']=(sub.production_date>=dt).astype(int)
    print(line, dt, 'n_pre', (sub.post==0).sum(), 'n_post', sub.post.sum())
    print(sub.groupby('post').agg(rate=('defective_units','sum'), units=('units_produced','sum'), mt=('mold_temp','mean'), hum=('humidity_pct','mean'), ct=('cycle_time_s','mean'), amb=('ambient_temp_c','mean'), age=('machine_age_years','mean'), night=('shift', lambda x:(x=='Night').mean())).assign(rate=lambda x: x.rate/x.units).round(4))
    dd=d.assign(step=((d.line==line)&(d.production_date>=dt)).astype(int))
    m=smf.glm("defective_units + ok ~ "+base+"+step", data=dd, family=sm.families.Binomial()).fit()
    print(' step coef', round(m.params['step'],4), 'se', round(m.bse['step'],4), 'p', m.pvalues['step'])
    # raw vs model-based by month
EOF
cd "$TMPDIR" && python3 regime2.py 2>/dev/null

cat > $TMPDIR/regime3.py << 'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['ok']=d.units_produced-d.defective_units
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
r0=smf.glm("defective_units + ok ~ "+base, data=d, family=smf.families.Binomial() if False else __import__('statsmodels.api',fromlist=['x']).families.Binomial()).fit()
sub=d[d.line=='L2'].sort_values('production_date')
for dt in sorted(sub.production_date.unique()):
    if pd.Timestamp('2025-05-10')<=pd.Timestamp(dt)<=pd.Timestamp('2025-06-10'):
        dd=d.assign(step=((d.line=='L2')&(d.production_date>=dt)).astype(int))
        m=smf.glm("defective_units + ok ~ "+base+"+step", data=dd, family=__import__('statsmodels.api',fromlist=['x']).families.Binomial()).fit()
        print(pd.Timestamp(dt).date(), round(2*(m.llf-r0.llf),2), round(m.params['step'],4))
print(sub[(sub.production_date>='2025-05-15')&(sub.production_date<='2025-06-05')][['production_date','shift','operator_id','supplier_code','humidity_pct','mold_temp','defective_units','units_produced']].sort_values('production_date').to_string())
EOF
cd "$TMPDIR" && python3 regime3.py 2>/dev/null

cat > $TMPDIR/final.py << 'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
b = pd.read_csv("batches.csv", parse_dates=["production_date"])
s = pd.read_csv("suppliers.csv")
print("A1 unique normalized ids:", b.batch_id.str.strip().str.upper().nunique(), "rows", len(b))
print("A2 humidity missing:", b.humidity_pct.isna().sum(), " A2 invalid (<0 or >100):", ((b.humidity_pct<0)|(b.humidity_pct>100)).sum())
print("A3 total defect rate:", b.defective_units.sum()/b.units_produced.sum(), b.defective_units.sum(), b.units_produced.sum())
print("A4 median mold_temp:", b.mold_temp.median(), b.mold_temp.notna().sum())
# leakage: units_produced vs good units
good=b.units_produced-b.defective_units
print("good units min/max", good.min(), good.max(), " rate vs units corr", np.corrcoef(b.units_produced, b.defective_units/b.units_produced)[0,1].round(3))
# L1 sensor offset test
d=b.dropna(subset=['mold_temp']).copy()
d['L1pre']=((d.line=='L1')&(d.production_date<'2025-04-14')).astype(int)
mt=smf.ols("mold_temp ~ C(line)+C(shift)+C(operator_id)+ambient_temp_c+machine_age_years+cycle_time_s+L1pre", data=d.dropna(subset=['humidity_pct'])).fit()
print("L1pre offset:", round(mt.params['L1pre'],3), "se", round(mt.bse['L1pre'],3))
# counterfactual supplier
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl').merge(s[['supplier_code','supplier_name']], on='supplier_code', how='left', suffixes=('_x',''))
d=d.drop(columns=[c for c in d.columns if c.endswith('_x')], errors='ignore')
d['ok']=d.units_produced-d.defective_units
base="C(line)+C(shift)+C(operator_id)+C(supplier_code)+mold_temp+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c"
mod=smf.glm("defective_units + ok ~ "+base, data=d, family=sm.families.Binomial()).fit()
for step in [False]:
    out={}
    for code,name in zip(s.supplier_code, s.supplier_name):
        x=d.copy(); x['supplier_code']=code; x['cycle_time_s']=30.0
        p=mod.predict(x)
        out[name]=(p*x.units_produced).sum()/x.units_produced.sum()
    print("C1 counterfactual:", {k:round(v,5) for k,v in out.items()})
print("C1 raw pooled (complete cases):", d.groupby('supplier_name').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(5).to_dict())
# C2 humidity curve for Alpha
alpha=d.assign(supplier_code='SP-01')
hs=np.linspace(12.1,72.3,601)
rs=[]
for h in hs:
    x=alpha.copy(); x['humidity_pct']=h
    rs.append(((mod.predict(x)*x.units_produced).sum()/x.units_produced.sum()))
rs=np.array(rs); i=rs.argmin()
print("C2 min humidity", round(hs[i],2), rs[i], "at endpoints", rs[0], rs[-1])
# quadratic check
mq=smf.glm("defective_units + ok ~ "+base+"+I(humidity_pct**2)", data=d, family=sm.families.Binomial()).fit()
print("quadratic coefs:", mq.params['humidity_pct'], mq.params['I(humidity_pct ** 2)'], "vertex", -mq.params['humidity_pct']/(2*mq.params['I(humidity_pct ** 2)']))
EOF
cd "$TMPDIR" && python3 final.py 2>/dev/null

cd "$TMPDIR" && python3 final.py 2>&1 | grep -v -i "warn\|wls_results" | tail -30

python3 $TMPDIR/final.py 2>&1 | grep -v -i "warn\|wls_results" | tail -30
