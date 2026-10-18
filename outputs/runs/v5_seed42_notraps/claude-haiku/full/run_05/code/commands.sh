pwd && ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/explore.py << 'EOF'
import pandas as pd
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape); print(b.dtypes)
for c in b.columns:
    vals = b[c]
    print('\n##', c, 'nunique', vals.nunique(), 'empty', (vals.str.strip()=='').sum())
    if vals.nunique() < 25: print(vals.value_counts(dropna=False).to_dict())
    else: print(vals.sample(15, random_state=1).tolist())
print('\nduplicate batch_id rows:', b.batch_id.duplicated().sum(), 'full dup rows:', b.duplicated().sum())
print(open('suppliers.csv').read())
m = pd.read_csv('maintenance.csv', dtype=str, keep_default_na=False)
print(m.event.value_counts(), m.note.value_counts())
print(m.line.value_counts())
print(m[m.event!='mold_cleaning'])
EOF
python3 $TMPDIR/explore.py

cat > $TMPDIR/explore2.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units']
for c in num:
    s = b[c]
    bad = s[pd.to_numeric(s, errors='coerce').isna() & (s.str.strip()!='')]
    print(c, 'non-numeric nonblank:', bad.unique()[:20], 'blank:', (s.str.strip()=='').sum())
    x = pd.to_numeric(s, errors='coerce')
    print(x.describe().round(2).to_dict())
print(b.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$').all(), b.production_date.min(), b.production_date.max())
print(b.loc[~b.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$'),'production_date'].unique()[:20])
for c in ['humidity_pct','mold_temp']:
    x = pd.to_numeric(b[c], errors='coerce')
    print(c, 'values <=1:', (x<=1).sum(), 'neg:', (x<0).sum(), '>100:', (x>100).sum())
    print(sorted(x.dropna().unique())[:10], sorted(x.dropna().unique())[-10:])
b['units_produced_n']=pd.to_numeric(b.units_produced)
b['defective_n']=pd.to_numeric(b.defective_units)
print('defective>units', (b.defective_n>b.units_produced_n).sum(), 'units<=0', (b.units_produced_n<=0).sum())
print(b.groupby('line').mold_temp.apply(lambda s: pd.to_numeric(s,errors='coerce').describe()[['mean','50%','min','max']].round(1).to_dict()))
b['mt']=pd.to_numeric(b.mold_temp,errors='coerce')
b['hum']=pd.to_numeric(b.humidity_pct,errors='coerce')
b['date']=pd.to_datetime(b.production_date)
print(b.groupby(['line', b.date.dt.to_period('M')]).mt.median().unstack(0).round(1))
print(b.groupby(['line', b.date.dt.to_period('M')]).hum.median().unstack(0).round(1))
EOF
python3 $TMPDIR/explore2.py

cat > $TMPDIR/explore3.py << 'EOF'
import pandas as pd, numpy as np
b = pd.read_csv('batches.csv')
b['date']=pd.to_datetime(b.production_date)
b['dr']=b.defective_units/b.units_produced
b['after']=(b.date>=pd.Timestamp('2025-04-14'))
print(b.groupby(['line','after']).agg(mt_mean=('mold_temp','mean'),mt_med=('mold_temp','median'),n=('mold_temp','count'),dr=('dr','mean')).round(4))
# daily mold temp relative to line-day mean across lines
print(b.groupby(['line', b.date.dt.to_period('M')]).dr.mean().unstack(0).round(4))
# L1 weekly around change
l1=b[b.line=='L1'].copy()
l1['wk']=l1.date.dt.to_period('W')
print(l1.groupby('wk').agg(mt=('mold_temp','mean'),dr=('dr','mean'),n=('dr','size')).round(3).to_string())
EOF
python3 $TMPDIR/explore3.py

cat > $TMPDIR/explore4.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
b = pd.read_csv('batches.csv')
b['date']=pd.to_datetime(b.production_date)
b['post']=(b.date>=pd.Timestamp('2025-04-14')).astype(int)
print('A1', b.batch_id.nunique())
print('A2 humidity missing', b.humidity_pct.isna().sum())
print('A3', b.defective_units.sum()/b.units_produced.sum(), b.defective_units.sum(), b.units_produced.sum())
print('A4 median mold', b.mold_temp.median(), b.mold_temp.count())
print(b.groupby(['line','post']).mold_temp.quantile([.1,.25,.5,.75,.9]).unstack().round(2))
m = smf.ols('mold_temp ~ C(line)*post + ambient_temp_c + cycle_time_s + C(shift) + machine_age_years + C(supplier_code) + C(operator_id)', data=b).fit()
print(m.summary().tables[1])
EOF
python3 $TMPDIR/explore4.py 2>&1 | head -120

cat > $TMPDIR/model1.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm, statsmodels.formula.api as smf
b = pd.read_csv('batches.csv')
s = pd.read_csv('suppliers.csv')
b = b.merge(s, on='supplier_code', how='left')
b['date']=pd.to_datetime(b.production_date)
b['fail']=b.units_produced-b.defective_units
b['dr']=b.defective_units/b.units_produced
d = b.dropna(subset=['mold_temp','humidity_pct']).copy()
print('n model', len(d))
f = 'defective_units + fail ~ C(line) + C(shift) + C(operator_id) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c'
g = smf.glm('defective_units + fail ~ C(line) + C(shift) + C(operator_id) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c', data=d, family=sm.families.Binomial()).fit()
print(g.summary().tables[1])
print('dispersion', g.pearson_chi2/g.df_resid)
EOF
python3 $TMPDIR/model1.py 2>&1 | grep -v Warning | head -80

cat > $TMPDIR/prep.py << 'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm, statsmodels.formula.api as smf
def load():
    b = pd.read_csv('batches.csv')
    s = pd.read_csv('suppliers.csv')
    m = pd.read_csv('maintenance.csv')
    b = b.merge(s, on='supplier_code', how='left')
    b['date']=pd.to_datetime(b.production_date)
    b['fail']=b.units_produced-b.defective_units
    b['dr']=b.defective_units/b.units_produced
    mc = m[m.event=='mold_cleaning'].copy(); mc['date']=pd.to_datetime(mc.date)
    def days_since(row):
        c = mc[(mc.line==row.line)&(mc.date<=row.date)]
        return (row.date - c.date.max()).days if len(c) else np.nan
    b['days_since_clean']=b.apply(days_since, axis=1)
    return b, m, mc
EOF
cat > $TMPDIR/model2.py << 'EOF'
import sys; sys.path.insert(0, '/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_qqnhgzqf/..')
import os
os.chdir('/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_qqnhgzqf')
exec(open(os.environ['TMPDIR']+'/prep.py').read())
b,m,mc = load()
print(b.days_since_clean.describe())
print(b.days_since_clean.isna().sum())
print(b.groupby(pd.cut(b.days_since_clean,[-1,3,7,10,13,14,20,30,60,200])).dr.agg(['mean','size']).round(4))
mc2 = mc.sort_values(['line','date']).groupby('line').date.apply(lambda s: s.diff().dt.days.describe()[['min','max','mean']])
print(mc2)
print(mc.groupby('line').date.agg(['min','max','count']))
EOF
python3 $TMPDIR/model2.py

cat > $TMPDIR/model3.py << 'EOF'
import os; os.chdir('/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_qqnhgzqf')
exec(open(os.environ['TMPDIR']+'/prep.py').read())
import warnings; warnings.filterwarnings('ignore')
b,m,mc = load()
d = b.dropna(subset=['mold_temp','humidity_pct']).copy()
print('n', len(d))
base = 'C(line) + C(shift) + C(operator_id) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c'
def fit(f, data=d):
    return smf.glm('defective_units + fail ~ '+f, data=data, family=sm.families.Binomial()).fit()
g0 = fit(base)
g1 = fit(base+' + days_since_clean')
g2 = fit(base+' + days_since_clean + C(supplier_code):humidity_pct')
g3 = fit(base+' + days_since_clean + pre_dried:humidity_pct')
g4 = fit(base+' + days_since_clean + C(supplier_code):humidity_pct + C(supplier_code):cycle_time_s + C(supplier_code):mold_temp')
for n,g in [('g0',g0),('g1',g1),('g2',g2),('g3',g3),('g4',g4)]:
    print(n, 'AIC', round(g.aic,1), 'disp', round(g.pearson_chi2/g.df_resid,3))
print(g1.summary().tables[1].as_text()[-1500:])
print(g2.summary().tables[1].as_text()[-1200:])
print(g4.summary().tables[1].as_text()[-1800:])
EOF
python3 $TMPDIR/model3.py

cat > $TMPDIR/corr.py << 'EOF'
import os; os.chdir('/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_qqnhgzqf')
exec(open(os.environ['TMPDIR']+'/prep.py').read())
import warnings; warnings.filterwarnings('ignore')
b,m,mc = load()
cols=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','days_since_clean','dr']
print(b[cols].corr().round(3).to_string())
print(b.groupby('supplier_name')[['humidity_pct','cycle_time_s','mold_temp','ambient_temp_c','dr']].mean().round(3))
print(b.groupby(['supplier_name','pre_dried'])[['humidity_pct']].agg(['mean','std']).round(2))
print(b.groupby('shift')[['cycle_time_s','mold_temp','humidity_pct','dr']].mean().round(3))
print(b.groupby('line')[['humidity_pct','cycle_time_s','mold_temp','ambient_temp_c','dr','machine_age_years']].mean().round(3))
print(pd.crosstab(b.operator_id,b.line))
print(b.groupby('operator_id').dr.mean().round(4).to_string())
EOF
python3 $TMPDIR/corr.py

cat > $TMPDIR/dup.py << 'EOF'
import os; os.chdir('/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_qqnhgzqf')
import pandas as pd, re
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.batch_id.str.match(r'^B-\d{6}$').all(), b.batch_id.str.len().value_counts().to_dict())
norm = b.batch_id.str.upper().str.replace(r'[^0-9]','',regex=True)
print('normalized dup', norm.duplicated().sum())
cols=[c for c in b.columns if c!='batch_id']
print('content dup excluding id', b.duplicated(subset=cols).sum())
print(b[b.duplicated(subset=cols, keep=False)].sort_values(cols).head(20).to_string())
print(b[b.duplicated(subset=['production_date','line','operator_id','units_produced'], keep=False)].sort_values(['production_date','line']).to_string())
EOF
python3 $TMPDIR/dup.py

cat > $TMPDIR/resid.py << 'EOF'
import os; os.chdir('/private/var/folders/7h/28064gg93518rt30grsmrxk80000gn/T/edabench_claude_qqnhgzqf')
exec(open(os.environ['TMPDIR']+'/prep.py').read())
import warnings; warnings.filterwarnings('ignore')
b,m,mc = load()
d = b.dropna(subset=['mold_temp','humidity_pct']).copy()
f='C(line) + C(shift) + C(operator_id) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
g = smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
d['pred']=g.predict(d)*d.units_produced
d['res']=(d.defective_units-d.pred)
d['wk']=d.date.dt.to_period('M')
t = d.groupby(['line','wk']).agg(obs=('defective_units','sum'),exp=('pred','sum'),n=('units_produced','sum')).reset_index()
t['ratio']=t.obs/t.exp
print(t.pivot(index='wk',columns='line',values='ratio').round(3))
# cusum of residual by line
for L in ['L1','L2','L3','L4']:
    x = d[d.line==L].sort_values('date')
    cs = x.res.cumsum()
    print(L, 'max cusum', round(cs.max(),1), x.loc[cs.idxmax(),'date'].date(), 'min', round(cs.min(),1), x.loc[cs.idxmin(),'date'].date())
d.to_pickle(os.environ['TMPDIR']+'/d.pkl')
EOF
python3 $TMPDIR/resid.py

cat > $TMPDIR/cp.py << 'EOF'
import os; os.environ.setdefault('TMPDIR','/tmp')
import pandas as pd, numpy as np
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
phi = 2.26
res=[]
for L in ['L1','L2','L3','L4']:
    x = d[d.line==L].sort_values('date').reset_index(drop=True)
    best=None
    for i in range(30, len(x)-30):
        a = x.iloc[:i]; c = x.iloc[i:]
        # expected-to-observed ratio shift; z from Poisson-ish with dispersion
        oa, ea = a.defective_units.sum(), a.pred.sum()
        oc, ec = c.defective_units.sum(), c.pred.sum()
        ra, rc = oa/ea, oc/ec
        r0 = (oa+oc)/(ea+ec)
        ll = lambda o,e,r: o*np.log(r*e)-r*e if o>0 else -r*e
        L1 = ll(oa,ea,ra)+ll(oc,ec,rc)-(ll(oa,ea,r0)+ll(oc,ec,r0))
        stat = 2*L1/phi
        if best is None or stat>best[0]: best=(stat, x.date.iloc[i].date(), round(ra,3), round(rc,3))
    print(L, best)
EOF
python3 $TMPDIR/cp.py

cat > $TMPDIR/tr.py << 'EOF'
import os
import pandas as pd, numpy as np
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['q']=d.date.dt.to_period('Q')
print(d.groupby(['line','q']).agg(units=('units_produced','mean'),defs=('defective_units','mean'),dr=('dr','mean'),n=('dr','size')).round(3).to_string())
print(d.groupby(['line','q']).apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).unstack(0).round(4))
print(d.groupby(['line','q']).apply(lambda x: x.pred.sum()/x.units_produced.sum()).unstack(0).round(4))
EOF
python3 $TMPDIR/tr.py

cat > $TMPDIR/shape.py << 'EOF'
import os
import pandas as pd, numpy as np
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
def agg(col, bins):
    t = d.groupby(pd.cut(d[col], bins)).apply(lambda x: pd.Series({'dr':x.defective_units.sum()/x.units_produced.sum(),'n':len(x)}))
    print(t.round(4).to_string())
agg('humidity_pct', [10,15,20,25,30,35,40,45,50,55,60,65,75])
agg('mold_temp', [185,195,200,205,208,210,212,215,220,240])
agg('cycle_time_s', [15,22,25,28,30,32,35,40,50])
agg('machine_age_years', [0,3,5,7,9,11,13,18])
agg('ambient_temp_c', [5,12,16,20,24,28,35])
print(d.groupby('supplier_name').apply(lambda x: pd.Series({'dr':x.defective_units.sum()/x.units_produced.sum()})))
EOF
python3 $TMPDIR/shape.py

cat > $TMPDIR/nl.py << 'EOF'
import os
import pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
d['hum2']=(d.humidity_pct-30)**2
d['mt2']=(d.mold_temp-210)**2
d['ct2']=(d.cycle_time_s-30)**2
def fit(f):
    return smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
base='C(line) + C(shift) + C(operator_id) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
g0=fit(base); print('base AIC',round(g0.aic,1))
for nm,f in [('hum2',base+'+hum2'),('mt2',base+'+mt2'),('ct2',base+'+ct2'),('hum x alpha', base+'+humidity_pct:C(supplier_code)+hum2'),
             ('line x days',base+'+C(line):days_since_clean'),('line x hum', base+'+C(line):humidity_pct'),('shift x hum', base+'+C(shift):humidity_pct'),('op-only shift', 'C(line)+C(shift)+humidity_pct+mold_temp+cycle_time_s+days_since_clean+C(supplier_code)')]:
    g=fit(f); print(nm, 'AIC', round(g.aic,1), 'LR-ish dAIC', round(g.aic-g0.aic,1))
g=fit(base+'+hum2'); print(g.params[['humidity_pct','hum2']], g.bse[['humidity_pct','hum2']])
EOF
python3 $TMPDIR/nl.py

cat > $TMPDIR/lr.py << 'EOF'
import os
import pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
def fit(f):
    g=smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
    return g
phi_ref = None
full = 'C(line)*C(shift)'
terms = {
 'hum':'humidity_pct','mt':'mold_temp','ct':'cycle_time_s','age':'machine_age_years','amb':'ambient_temp_c','days':'days_since_clean','shift':'C(shift)','sup':'C(supplier_code)','op_in_line':'C(operator_id)','line':'C(line)'
}
rest = ' + '.join(terms.values())
g_full = fit('C(operator_id)+' + rest.replace('C(line)+','').replace('+ C(line)','') + ' ')
EOF
cat > $TMPDIR/lr.py << 'EOF'
import os
import pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
def fit(f):
    return smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
full_terms = ['C(operator_id)','C(shift)','C(supplier_code)','humidity_pct','mold_temp','cycle_time_s','machine_age_years','ambient_temp_c','days_since_clean']
full = fit(' + '.join(full_terms))
phi = full.pearson_chi2/full.df_resid
print('full df_resid', full.df_resid, 'phi', round(phi,3))
for t in full_terms:
    red_terms=[x for x in full_terms if x!=t]
    red = fit(' + '.join(red_terms))
    dd = red.deviance-full.deviance; ddf = red.df_resid-full.df_resid
    F = dd/ddf/phi
    p = stats.f.sf(F, ddf, full.df_resid)
    print(f'{t:22s} dropdf={ddf:3.0f} F={F:8.2f} p={p:.3g}')
EOF
python3 $TMPDIR/lr.py

cat > $TMPDIR/lr2.py << 'EOF'
import os
import pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
print(pd.crosstab(d.operator_id, d['shift']).T.to_string())
def fit(f):
    return smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
base=['C(line)','C(shift)','C(supplier_code)','humidity_pct','mold_temp','cycle_time_s','machine_age_years','ambient_temp_c','days_since_clean']
full = fit(' + '.join(base+['C(operator_id)']))
phi = full.pearson_chi2/full.df_resid
print('full rank df_resid', full.df_resid, 'df_model', full.df_model, 'phi', round(phi,3))
red = fit(' + '.join(base))
dd = red.deviance-full.deviance; ddf = full.df_model-red.df_model
F=dd/ddf/phi; print('operator within line: ddf', ddf, 'F', round(F,2), 'p', stats.f.sf(F, ddf, full.df_resid))
for t in ['C(line)','C(shift)','C(supplier_code)','humidity_pct','mold_temp','cycle_time_s','machine_age_years','ambient_temp_c','days_since_clean']:
    r = fit(' + '.join([x for x in base+['C(operator_id)'] if x!=t]))
    dd=r.deviance-full.deviance; ddf=full.df_model-r.df_model
    F=dd/ddf/phi; print(f'{t:20s} ddf={ddf:.0f} F={F:.2f} p={stats.f.sf(F,ddf,full.df_resid):.3g}')
EOF
python3 $TMPDIR/lr2.py

cat > $TMPDIR/cp2.py << 'EOF'
import os
import pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
d = pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
f='C(line) + C(operator_id) + C(shift) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
g=smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
phi=g.pearson_chi2/g.df_resid; print('phi',round(phi,3))
d['pred']=g.predict(d)*d.units_produced
for L in ['L1','L2','L3','L4']:
    x=d[d.line==L]
    pre=x[x.date<'2025-04-14']; post=x[x.date>='2025-04-14']
    print(L,'04-14 ratio pre',round(pre.defective_units.sum()/pre.pred.sum(),3),'post',round(post.defective_units.sum()/post.pred.sum(),3))
phi=phi
res=[]
for L in ['L1','L2','L3','L4']:
    x=d[d.line==L].sort_values('date').reset_index(drop=True)
    stats=[]
    for i in range(30,len(x)-30):
        a=x.iloc[:i]; c=x.iloc[i:]
        oa,ea,oc,ec=a.defective_units.sum(),a.pred.sum(),c.defective_units.sum(),c.pred.sum()
        ra,rc,r0=oa/ea,oc/ec,(oa+oc)/(ea+ec)
        ll=lambda o,e,r: o*np.log(r*e)-r*e
        stats.append((2*(ll(oa,ea,ra)+ll(oc,ec,rc)-ll(oa,ea,r0)-ll(oc,ec,r0))/phi, x.date.iloc[i].date(), round(ra,3), round(rc,3)))
    print(L, max(stats))
EOF
python3 $TMPDIR/cp2.py

cat > $TMPDIR/answers.py << 'EOF'
import os
import pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf
exec(open(os.environ['TMPDIR']+'/prep.py').read())
b,m,mc = load()
d = b.dropna(subset=['mold_temp','humidity_pct']).copy()
f='C(line) + C(operator_id) + C(shift) + C(supplier_code) + humidity_pct + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
g=smf.glm('defective_units + fail ~ '+f, data=d, family=sm.families.Binomial()).fit()
print('model ok, phi', round(g.pearson_chi2/g.df_resid,3))
# C1
rec = 30.0
print('recipe cycle per supplier', pd.read_csv('suppliers.csv')[['supplier_name','recipe_cycle_time_s']].values.tolist())
print('--- C1 (all batches with supplier X, cycle=recipe 30, other as recorded) ---')
for code,name in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    x=d.copy(); x['supplier_code']=code; x['cycle_time_s']=rec
    p=g.predict(x)*x.units_produced
    print(name, round(p.sum()/x.units_produced.sum(),5))
print('actual (recorded) model-based rates by supplier')
d['p']=g.predict(d)*d.units_produced
print(d.groupby('supplier_name').apply(lambda x: x.p.sum()/x.units_produced.sum()).round(5))
# C2
a = d[d.supplier_code=='SP-01']
print('Alpha humidity range', a.humidity_pct.min(), a.humidity_pct.max(), 'n', len(a))
grid=np.round(np.arange(12.1,72.31,0.1),2)
rates=[]
for h in grid:
    x=a.copy(); x['humidity_pct']=h
    rates.append((g.predict(x)*x.units_produced).sum()/x.units_produced.sum())
rates=np.array(rates); i=rates.argmin()
print('C2 argmin humidity', grid[i], rates[i], 'at max', rates[-1])
# C3
d2=d.copy()
new=[]
for L in ['L1','L2','L3','L4']:
    c=mc[mc.line==L].date.sort_values().tolist()
    end=pd.Timestamp('2025-09-30')
    last=c[-1]
    extra=[]
    t=c[-1]
    # add synthetic cleanings every 14 days after each actual cleaning until end
    events=sorted(set(c))
    allev=[]
    for e in events:
        k=e
        while k<=end:
            allev.append(k); k=k+pd.Timedelta(days=14)
    allev=sorted(set(allev))
    new.append((L,allev))
new=dict(new)
def days_new(row):
    ev=[e for e in new[row.line] if e<=row.date]
    return (row.date-max(ev)).days
d2['dsc_new']=d2.apply(days_new,axis=1)
print('days_since before/after mean', d2.days_since_clean.mean().round(3), d2.dsc_new.mean().round(3), 'max new', d2.dsc_new.max())
x=d2.copy(); x['days_since_clean']=x.dsc_new
ratio = g.predict(x)/g.predict(d2)
print('C3 rate: recorded-based', (d2.defective_units*ratio).sum()/d2.units_produced.sum(), 'actual A3(on same subset)', d2.defective_units.sum()/d2.units_produced.sum())
print('full data A3', b.defective_units.sum()/b.units_produced.sum())
EOF
python3 $TMPDIR/answers.py

cat >> $TMPDIR/answers.py << 'EOF'
full=b.copy()
full['dsc_new']=full.apply(days_new,axis=1)
keep=full.index.isin(d2.index)
ratio_full=pd.Series(1.0,index=full.index)
ratio_full[d2.index]=ratio.values
print('C3 full-data (missing rows unchanged)', (full.defective_units*ratio_full).sum()/full.units_produced.sum())
print('missing-row defects share', full.loc[~keep,'defective_units'].sum(), full.loc[~keep,'units_produced'].sum())
EOF
python3 $TMPDIR/answers.py 2>/dev/null | tail -2
