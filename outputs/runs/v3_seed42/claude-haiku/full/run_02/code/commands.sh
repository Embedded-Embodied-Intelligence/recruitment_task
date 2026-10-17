ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv && echo && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('==',c,'nunique',df[c].nunique(),'empty',(df[c].str.strip()=='').sum())
    if df[c].nunique()<40: print(vc.to_dict())
    else: print(df[c].head(3).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d)); print(d.head(6).to_string())
print('exact dup rows', df.duplicated().sum())
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(df[c],errors='coerce')
    bad=df.loc[x.isna()&(df[c].str.strip()!=''),c].unique()
    print(c,'nonnum:',bad[:10],'n_nan',x.isna().sum(),'min',x.min(),'max',x.max(),'median',x.median())
print(df.production_date.min(),df.production_date.max())
print(pd.to_datetime(df.production_date,errors='coerce').isna().sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp); df['hum']=pd.to_numeric(df.humidity_pct,errors='coerce')
print(len(df), df.batch_id.nunique())
print('humidity values <0 or >100:', df.loc[(df.hum<0)|(df.hum>100),'hum'].value_counts().to_dict())
print('humidity blank:', (df.humidity_pct.str.strip()=='').sum())
print('mold temp hist'); print(np.histogram(df.mt,bins=[-1,1,50,100,150,180,200,230,260,300,350,400,500]))
print(df.loc[df.mt<100,['batch_id','production_date','line','mt']].head(20).to_string())
print((df.mt<100).sum(), 'low mt rows', df.loc[df.mt<100,'mt'].round(1).value_counts().head(10).to_dict())
print(df.groupby('line').mt.describe())
print(df.loc[df.mt>300,['production_date','line','mt']].head(20).to_string())
print('n >300', (df.mt>300).sum(), 'n 150-300',((df.mt>150)&(df.mt<=300)).sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp); df['d']=pd.to_datetime(df.production_date)
v=df[df.mt>0].copy()
v['m']=v.d.dt.to_period('M')
print(v.groupby(['m','line']).mt.median().unstack().round(1))
l3=v[v.line=='L3']
print('L3 min/max', l3.mt.min(), l3.mt.max())
print('L3 over 300 share by month'); print(l3.assign(f=l3.mt>300).groupby('m').f.mean().round(2).to_dict())
l1=v[v.line=='L1'].copy()
l1['w']=l1.d.dt.to_period('W')
print(l1.groupby('w').mt.median().round(1).to_string())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
df['mt']=pd.to_numeric(df.mold_temp); df['d']=pd.to_datetime(df.production_date)
v=df[(df.mt>0)].copy()
v.loc[v.line=='L3','mt']=(v.loc[v.line=='L3','mt']-32)*5/9
l1=v[(v.line=='L1')&(v.d>='2025-04-01')&(v.d<='2025-04-25')]
print(l1.groupby('d').mt.agg(['median','count']).round(1).to_string())
# compare L1 vs others by month after conversion
print(v.assign(m=v.d.dt.to_period('M')).groupby(['m','line']).mt.median().unstack().round(1))
"

python3 -c "import pandas, numpy; print(pandas.__version__, numpy.__version__)"; python3 -c "import statsmodels; print('sm', statsmodels.__version__)"; python3 -c "import sklearn; print('sk', sklearn.__version__)"; python3 -c "import scipy; print('scipy', scipy.__version__)"; echo $TMPDIR; mkdir -p /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && echo ok

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -I clean.py

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -I -c "
import pandas as pd, numpy as np
df=pd.read_pickle('clean.pkl')
print('A3', df.defective_units.sum()/df.units_produced.sum())
print('A3 mean of batch rate', df.defect_rate.mean())
print('A4 median mold C', df.mold_c.median(), 'n', df.mold_c.notna().sum())
print('A4 raw-no-correction median C (for comparison)', df.loc[df.mold_raw_valid & (df.line!='L3'),'mold_temp'].median())
print(df[['defect_rate','defective_units','units_produced','qc_inspection_min','rework_cost_eur','cycle_time_s','mold_c','humidity','ambient_temp_c','machine_age_years']].corr().round(3).to_string())
# rework cost vs defective units
import numpy as np
print('rework/defect ratio', (df.rework_cost_eur/df.defective_units).describe().round(3).to_dict())
print('qc vs defect rate by line'); print(df.groupby('line').qc_inspection_min.mean().round(2).to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -I -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
df=pd.read_pickle('clean.pkl')
d=df[df.humidity_valid & df.mold_c.notna()].copy()
d['fail']=d.units_produced-d.defective_units
f='defective_units + fail ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
m=smf.glm('defective_units + fail ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + C(operator_id)', data=d, family=sm.families.Binomial()).fit()
print(m.summary2().tables[1].round(4).to_string())
print('dev',m.deviance, 'pearson chi2/df', m.pearson_chi2/m.df_resid)
" 2>&1 | head -80

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -I -c "
import pandas as pd, numpy as np
df=pd.read_pickle('clean.pkl')
print(pd.crosstab(df.operator_id, df.line).to_string())
print(pd.crosstab(df.operator_id, df['shift']).T.to_string())
print(pd.crosstab(df.supplier_code, df.line))
print(pd.crosstab(df.supplier_code, df['shift']))
"

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > feat.py <<'EOF'
import pandas as pd, numpy as np
from clean import clean, DATA, SCRATCH

def cleanings():
    m = pd.read_csv(f'{DATA}/maintenance.csv', parse_dates=['date'])
    c = m[m.event == 'mold_cleaning'][['date', 'line']]
    return c

def add_days_since(df, cl=None):
    if cl is None:
        cl = cleanings()
    out = []
    for line, g in df.groupby('line'):
        dates = np.sort(cl.loc[cl.line == line, 'date'].values)
        # for each batch: most recent cleaning on or before its production date (cleaning before first shift)
        idx = np.searchsorted(dates, g.date.values, side='right') - 1
        last = pd.Series(pd.NaT, index=g.index)
        ok = idx >= 0
        last[ok] = dates[idx[ok]]
        out.append(last.rename('last_clean'))
    df = df.copy()
    df['last_clean'] = pd.concat(out)
    df['days_since_clean'] = (df.date - df.last_clean).dt.days
    return df

if __name__ == '__main__':
    df = pd.read_pickle(f'{SCRATCH}/clean.pkl')
    df = add_days_since(df)
    print(df.days_since_clean.describe())
    print('missing last_clean', df.last_clean.isna().sum())
    df.to_pickle(f'{SCRATCH}/feat.pkl')
    d = df.copy()
    d['bin'] = pd.cut(d.days_since_clean, [-1, 0, 3, 6, 9, 12, 14, 17, 21, 30, 60])
    print(d.groupby('bin', observed=True).agg(n=('batch_id', 'size'), rate=('defect_rate', 'mean'), pooled=('defective_units', 'sum'), units=('units_produced', 'sum')).assign(pooled_rate=lambda x: x.pooled / x.units).round(4).to_string())
EOF
python3 -I feat.py

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 feat.py

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
df=pd.read_pickle('feat.pkl')
d=df[df.humidity_valid & df.mold_c.notna()].copy()
d['fail']=d.units_produced-d.defective_units
for form in ['mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean',
             'mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(operator_id) + days_since_clean']:
    m=smf.glm('defective_units + fail ~ '+form, data=d, family=sm.families.Binomial()).fit()
    print(m.params.round(4).to_string()); print(m.bse.round(4).to_string()) if False else None
    print('pearson/df', round(m.pearson_chi2/m.df_resid,3), 'AIC', round(m.aic,1))
    print(m.summary2().tables[1][['P>|z|']].round(4).T.to_string())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
df=pd.read_pickle('feat.pkl')
d=df[df.humidity_valid & df.mold_c.notna()].copy()
d['fail']=d.units_produced-d.defective_units
m=smf.glm('defective_units + fail ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean', data=d, family=sm.families.Binomial()).fit()
d['mu']=m.predict(d)*d.units_produced
d['res']=(d.defective_units-d.mu)/np.sqrt(d.mu*(1-m.predict(d)))
d['m']=d.date.dt.to_period('M')
print(d.groupby(['m','line']).res.mean().unstack().round(2).to_string())
print(d.groupby('line').res.agg(['mean','std']).round(2))
d['w']=d.date.dt.to_period('W')
print(d[d.line=='L4'].groupby('w').res.mean().round(2).to_string())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > resid.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
df = pd.read_pickle('feat.pkl')
d = df[df.humidity_valid & df.mold_c.notna()].copy()
d['fail'] = d.units_produced - d.defective_units
FORM = 'mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean'
m = smf.glm('defective_units + fail ~ ' + FORM, data=d, family=sm.families.Binomial()).fit()
p = m.predict(d)
d['mu'] = p * d.units_produced
d['res'] = (d.defective_units - d.mu) / np.sqrt(d.mu * (1 - p))
EOF
python3 -c "
from resid import *
l2=d[d.line=='L2'].sort_values('date').copy()
# cumulative sum of residuals, change point = argmax |cusum|
c=l2.res.cumsum()
k=int(np.argmax(np.abs(c.values-np.arange(1,len(c)+1)/len(c)*c.values[-1])))
print('L2 change point approx', l2.date.iloc[k].date(), 'index',k,'of',len(l2))
# split means test: for each candidate split date
best=None
for dt in pd.date_range('2025-02-01','2025-08-01'):
    a=l2[l2.date<dt].res; b=l2[l2.date>=dt].res
    if len(a)<30 or len(b)<30: continue
    t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
    if best is None or abs(t)>abs(best[1]): best=(dt.date(),t,a.mean(),b.mean(),len(a),len(b))
print('best split', best)
print(l2.groupby(l2.date.dt.to_period('W')).res.agg(['mean','size']).round(2).loc['2025-04-20':'2025-06-15'].to_string())
"


cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from resid import *
def scan(x):
    best=None
    for dt in pd.date_range('2025-02-01','2025-08-15'):
        a=x[x.date<dt].res; b=x[x.date>=dt].res
        if len(a)<30 or len(b)<30: continue
        t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(t)>abs(best[1]): best=(str(dt.date()),round(t,2),round(a.mean(),2),round(b.mean(),2))
    return best
for ln in ['L1','L2','L3','L4']:
    print(ln, scan(d[d.line==ln]))
# compare with uncorrected L1 temps: refit model using raw recorded L1 temp
e=df[df.humidity_valid & df.mold_raw_valid].copy()
e.loc[e.line=='L3','mold_c']=(e.loc[e.line=='L3','mold_temp']-32)*5/9
e['fail']=e.units_produced-e.defective_units
mm=smf.glm('defective_units + fail ~ mold_c + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean', data=e, family=sm.families.Binomial()).fit()
pp=mm.predict(e); e['mu']=pp*e.units_produced; e['res']=(e.defective_units-e.mu)/np.sqrt(e.mu*(1-pp))
print('uncorrected L1 (no bias fix) scan:', scan(e[e.line=='L1']))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from resid import *
e=df[df.humidity_valid & df.mold_raw_valid].copy()
# raw mold temperature in C (only L3 unit conversion, no sensor correction)
e['mraw']=np.where(e.line=='L3',(e.mold_temp-32)*5/9,e.mold_temp)
e['post']=((e.line=='L1')&(e.date>='2025-04-14')).astype(int)
e['fail']=e.units_produced-e.defective_units
f='mraw + post + humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean'
mm=smf.glm('defective_units + fail ~ '+f, data=e, family=sm.families.Binomial()).fit()
print(mm.params[['mraw','post']].round(4).to_dict(), mm.bse[['mraw','post']].round(4).to_dict())
print('implied post shift in mold units = post/mraw =', round(mm.params['post']/mm.params['mraw'],2))
# L2 post indicator in corrected model
d2=d.copy(); d2['l2post']=((d2.line=='L2')&(d2.date>='2025-06-15')).astype(int)
m2=smf.glm('defective_units + fail ~ '+FORM+' + l2post', data=d2, family=sm.families.Binomial()).fit()
print('L2 post coef', round(m2.params['l2post'],4), 'se', round(m2.bse['l2post'],4), 'pearson/df', round(m2.pearson_chi2/m2.df_resid,3))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from resid import *
e=df[df.humidity_valid & df.mold_raw_valid].copy()
e['mraw']=np.where(e.line=='L3',(e.mold_temp-32)*5/9,e.mold_temp)
e['fail']=e.units_produced-e.defective_units
e['l1post']=((e.line=='L1')&(e.date>='2025-04-14')).astype(int)
base='humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean'
for b in [0,4,8,10,12,14,16]:
    e['mc']=e.mraw - b*e.l1post
    mm=smf.glm('defective_units + fail ~ mc + '+base, data=e, family=sm.families.Binomial()).fit()
    print('bias',b,'llf',round(mm.llf,2),'coef mc',round(mm.params['mc'],4))
# quadratic check with corrected 8
e['mc']=e.mraw-8*e.l1post
mq=smf.glm('defective_units + fail ~ mc + I(mc**2) + '+base, data=e, family=sm.families.Binomial()).fit()
print('quad llf',round(mq.llf,2), mq.params[['mc','I(mc ** 2)']].round(5).to_dict())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from resid import *
e=df[df.humidity_valid & df.mold_raw_valid].copy()
e['mraw']=np.where(e.line=='L3',(e.mold_temp-32)*5/9,e.mold_temp)
e['fail']=e.units_produced-e.defective_units
e['l1post']=((e.line=='L1')&(e.date>='2025-04-14')).astype(int)
base='humidity + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_code) + C(line) + days_since_clean'
for b in [0,6,8,10,12,14]:
    e['mc']=e.mraw - b*e.l1post
    mm=smf.glm('defective_units + fail ~ bs(mc, df=5) + '+base, data=e, family=sm.families.Binomial()).fit() if False else None
    import patsy
    mm=smf.glm('defective_units + fail ~ cr(mc, df=5) + '+base, data=e, family=sm.families.Binomial()).fit()
    print('bias',b,'llf',round(mm.llf,2))
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from resid import *
d['l2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
base='mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post'
m0=smf.glm('defective_units + fail ~ '+base+' + C(supplier_code)*humidity', data=d, family=sm.families.Binomial()).fit()
print(m0.params.round(4).to_string())
print('pearson/df', round(m0.pearson_chi2/m0.df_resid,3))
# humidity shape: binned residual rates by supplier with model without humidity
m1=smf.glm('defective_units + fail ~ '+base+' + C(supplier_code)', data=d, family=sm.families.Binomial()).fit()
d['r']=d.defective_units-m1.predict(d)*d.units_produced
d['hb']=pd.cut(d.humidity,[0,10,15,20,25,30,35,40,45,50,55,60,75])
print(d.groupby(['supplier_code','hb'],observed=True).apply(lambda g: pd.Series({'n':len(g),'obs_minus_exp_per_unit':g.r.sum()/g.units_produced.sum()})).round(4).unstack(0).to_string())
print('humidity range', d.humidity.min(), d.humidity.max())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from resid import *
d['l2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['h2']=d.humidity**2
base='mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post'
m=smf.glm('defective_units + fail ~ '+base+' + C(supplier_code)*(humidity+h2)', data=d, family=sm.families.Binomial()).fit()
print(m.params.round(5).to_string())
print('pearson/df', round(m.pearson_chi2/m.df_resid,3), 'llf', round(m.llf,2))
# simple: humidity quadratic common to all suppliers
m2=smf.glm('defective_units + fail ~ '+base+' + C(supplier_code) + humidity + h2', data=d, family=sm.families.Binomial()).fit()
print('common quad llf', round(m2.llf,2), m2.params[['humidity','h2']].round(5).to_dict())
# only Alpha-specific quad, others linear
d['alpha']=(d.supplier_code=='SP-01').astype(int)
m3=smf.glm('defective_units + fail ~ '+base+' + C(supplier_code) + humidity:alpha + h2:alpha + humidity:C(supplier_code)', data=d, family=sm.families.Binomial()).fit()
print('model3 llf', round(m3.llf,2), m3.params.round(5).to_dict())
" 2>&1 | grep -v Warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > full.py <<'EOF'
from resid import *
from scipy import stats
d['l2post'] = ((d.line == 'L2') & (d.date >= '2025-06-15')).astype(int)
d['h2'] = d.humidity ** 2
SUP = 'C(supplier_code)*(humidity + h2)'
def fit(terms):
    f = 'defective_units + fail ~ ' + ' + '.join(terms)
    return smf.glm(f, data=d, family=sm.families.Binomial()).fit()
BASE = ['mold_c', 'cycle_time_s', 'machine_age_years', 'ambient_temp_c', 'C(shift)', 'C(line)', 'days_since_clean', 'l2post', SUP]
full = fit(BASE)
scale = full.pearson_chi2 / full.df_resid
def drop_test(name, terms_drop, extra=None):
    red_terms = [t for t in BASE if t not in terms_drop]
    red = fit(red_terms)
    ddf = full.df_model - red.df_model
    lr = (red.deviance - full.deviance) / scale
    p = stats.chi2.sf(lr, ddf)
    print(f'{name:18s} ddf={ddf:2d} qLR={lr:9.2f} p={p:.4g}')
EOF
python3 -c "
from full import *
print('scale', round(scale,3))
print(full.params.round(5).to_string())
drop_test('mold_c', ['mold_c'])
drop_test('cycle_time', ['cycle_time_s'])
drop_test('machine_age', ['machine_age_years'])
drop_test('ambient', ['ambient_temp_c'])
drop_test('shift', ['C(shift)'])
drop_test('humidity(all)', [SUP])
drop_test('line', ['C(line)'])
drop_test('days_since', ['days_since_clean'])
drop_test('l2post', ['l2post'])
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
terms=[t for t in BASE if t!='C(line)']+['C(operator_id)']
op=smf.glm('defective_units + fail ~ '+' + '.join(terms), data=d, family=sm.families.Binomial()).fit()
ddf=op.df_model-full.df_model
lr=(full.deviance-op.deviance)/scale  # op model is the larger one
print('op vs line ddf',ddf,'(op model is larger; LR of operator-within-line)')
lr=(op.deviance-full.deviance)/scale
print('qLR',round(lr,2),'p',stats.chi2.sf(lr,op.df_model-full.df_model))
# operator within line only, shift/other held fixed; compare operator dummies to line-specific mean
print(op.params.filter(like='operator').round(3).to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
terms=[t for t in BASE if t!='C(line)']+['C(operator_id)']
op=smf.glm('defective_units + fail ~ '+' + '.join(terms), data=d, family=sm.families.Binomial()).fit()
lr=(full.deviance-op.deviance)/scale
p=stats.chi2.sf(lr,20)
print('operator-within-line qLR',round(lr,2),'p',round(p,4), 'scale',round(scale,3))
# per-line operator-only tests
for ln in ['L1','L2','L3','L4']:
    s=d[d.line==ln].copy()
    f0='defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + l2post + C(supplier_code)*(humidity+h2)'
    a=smf.glm('defective_units + fail ~ '+f0, data=s, family=sm.families.Binomial()).fit()
    b=smf.glm('defective_units + fail ~ '+f0+' + C(operator_id)', data=s, family=sm.families.Binomial()).fit()
    sc=a.pearson_chi2/a.df_resid
    q=(a.deviance-b.deviance)/sc; k=b.df_model-a.df_model
    print(ln,'ops',s.operator_id.nunique(),'qLR',round(q,2),'df',k,'p',round(stats.chi2.sf(q,k),4))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
f0='mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + l2post + C(supplier_code)*(humidity+h2)'
for ln in ['L1','L2','L3','L4']:
    s=d[d.line==ln].copy()
    a=smf.glm('defective_units + fail ~ '+f0, data=s, family=sm.families.Binomial()).fit()
    b=smf.glm('defective_units + fail ~ '+f0+' + C(operator_id)', data=s, family=sm.families.Binomial()).fit()
    sc=a.pearson_chi2/a.df_resid
    q=(a.deviance-b.deviance)/sc; k=b.df_model-a.df_model
    print(ln,'ops',s.operator_id.nunique(),'qLR',round(q,2),'df',k,'p',round(stats.chi2.sf(q,k),4))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
import warnings; warnings.filterwarnings('ignore')
# (1) profile L2 start date
F0=[t for t in BASE if t!='l2post']
res=[]
for dt in pd.date_range('2025-06-01','2025-06-30'):
    d['l2x']=((d.line=='L2')&(d.date>=dt)).astype(int)
    m=smf.glm('defective_units + fail ~ '+' + '.join(F0)+' + l2x', data=d, family=sm.families.Binomial()).fit()
    res.append((str(dt.date()), round(m.llf,2)))
res=sorted(res,key=lambda x:-x[1]); print('best L2 start dates', res[:5])
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
import warnings; warnings.filterwarnings('ignore')
F0=[t for t in BASE if t!='l2post']
m0=smf.glm('defective_units + fail ~ '+' + '.join(F0), data=d, family=sm.families.Binomial()).fit()
p=m0.predict(d); d['res']=(d.defective_units-p*d.units_produced)/np.sqrt(p*(1-p)*d.units_produced)
x=d[(d.line=='L2')&(d.date>='2025-06-09')&(d.date<='2025-06-20')].sort_values('date')
print(x.groupby('date').agg(n=('res','size'),res=('res','mean'),rate=('defect_rate','mean'),shift=('shift','first')).round(3).to_string())
print('all dates L2 before/after count', (x.date<'2025-06-16').sum(), (x.date>='2025-06-16').sum())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
import warnings; warnings.filterwarnings('ignore')
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
mod=smf.glm('defective_units + fail ~ '+' + '.join(BASE), data=d, family=sm.families.Binomial()).fit()
print('pearson/df', round(mod.pearson_chi2/mod.df_resid,3))
# C1: counterfactual single supplier, complete cases
rows=[]
for s in ['SP-01','SP-02','SP-03']:
    x=d.copy(); x['supplier_code']=s; x['h2']=x.humidity**2
    p=mod.predict(x)
    rows.append((s, round((p*x.units_produced).sum()/x.units_produced.sum(),5)))
print('C1 counterfactual pooled rate by supplier (complete cases):', rows)
print('factual model pooled vs observed on same batches:', round((mod.predict(d)*d.units_produced).sum()/d.units_produced.sum(),5), round(d.defective_units.sum()/d.units_produced.sum(),5))
# C2: Alpha humidity optimum using quadratic
b=mod.params
b1=b['humidity']; b2=b['h2']
print('Alpha optimum humidity', round(-b1/(2*b2),2))
# check predicted rate minimum on grid, Alpha, others at median
g=np.arange(12.5,72.3,0.1)
x=pd.DataFrame({'mold_c':d.mold_c.median(),'cycle_time_s':d.cycle_time_s.median(),'machine_age_years':d.machine_age_years.median(),'ambient_temp_c':d.ambient_temp_c.median(),'shift':'Day','line':'L1','days_since_clean':d.days_since_clean.median(),'l2post':0,'supplier_code':'SP-01','humidity':g,'units_produced':500})
x['h2']=x.humidity**2
pp=mod.predict(x)
print('grid argmin Alpha', round(g[np.argmin(pp)],2), 'min rate', round(pp.min(),5))
# also SP-02/03 optimum for reference
for s in ['SP-02','SP-03']:
    x['supplier_code']=s; pp2=mod.predict(x); print(s,'argmin',round(g[np.argmin(pp2)],2))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > c3.py <<'EOF'
from full import *
import warnings; warnings.filterwarnings('ignore')
from feat import cleanings
d['l2post'] = ((d.line == 'L2') & (d.date >= '2025-06-16')).astype(int)
mod = smf.glm('defective_units + fail ~ ' + ' + '.join(BASE), data=d, family=sm.families.Binomial()).fit()
END = pd.Timestamp('2025-09-30')
cl = cleanings()

def cf_cleanings(line):
    actual = sorted(cl.loc[cl.line == line, 'date'])
    start = [a for a in actual if a <= pd.Timestamp('2025-01-06')][-1]
    later = [a for a in actual if a > pd.Timestamp('2025-01-06')]
    events = [start]
    last = start
    i = 0
    while last < END:
        forced = last + pd.Timedelta(days=14)
        nxt = later[i] if i < len(later) else None
        if nxt is not None and nxt <= forced:
            last = nxt
            i += 1
        else:
            if forced > END:
                break
            last = forced
            # any actual cleaning on the same day is consumed
            if nxt is not None and nxt == forced:
                i += 1
        events.append(last)
    # skip actual cleanings that were passed over
    return events

def days_cf(df):
    out = pd.Series(index=df.index, dtype=float)
    for line, g in df.groupby('line'):
        ev = np.array(sorted(cf_cleanings(line)), dtype='datetime64[ns]')
        idx = np.searchsorted(ev, g.date.values.astype('datetime64[ns]'), side='right') - 1
        last = ev[idx]
        out.loc[g.index] = (g.date.values.astype('datetime64[ns]') - last).astype('timedelta64[D]').astype(float)
    return out

if __name__ == '__main__':
    for ln in ['L1', 'L2', 'L3', 'L4']:
        ev = cf_cleanings(ln)
        gaps = np.diff([e.value for e in ev]) / 86400e9
        print(ln, 'n cleanings cf', len(ev), 'max gap', gaps.max(), 'actual gaps>14', sum(np.diff([a.value for a in sorted(cl.loc[cl.line==ln,'date'])])/86400e9>14))
    d['days_cf'] = days_cf(d)
    print('days_cf range', d.days_cf.min(), d.days_cf.max(), ' actual days range', d.days_since_clean.min(), d.days_since_clean.max())
    print('check actual vs cf (should be <= actual):', (d.days_cf <= d.days_since_clean).all())
    x = d.copy()
    x['days_since_clean'] = x.days_cf
    p_fact = mod.predict(d)
    p_cf = mod.predict(x)
    print('factual pooled (model):', round((p_fact * d.units_produced).sum() / d.units_produced.sum(), 5))
    print('counterfactual pooled (model, complete cases):', round((p_cf * d.units_produced).sum() / d.units_produced.sum(), 5))
    print('observed pooled (same batches):', round(d.defective_units.sum() / d.units_produced.sum(), 5))
    ratio = (p_cf * d.units_produced).sum() / (p_fact * d.units_produced).sum()
    print('calibrated cf = observed * ratio:', round(d.defective_units.sum() / d.units_produced.sum() * ratio, 5))
EOF
python3 c3.py

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from c3 import *
a=df.copy()
a=add_days_since(a) if False else a
from feat import add_days_since
a=add_days_since(a)
a['l2post']=((a.line=='L2')&(a.date>='2025-06-16')).astype(int)
a['h2']=a.humidity**2
# impute missing covariates for the all-batch check only
a['hum_i']=a.humidity.fillna(a.groupby('supplier_code').humidity.transform('median'))
a['mold_i']=a.mold_c.fillna(a.groupby('line').mold_c.transform('median'))
a['humidity_i']=a.hum_i; a['h2']=a.humidity_i**2
a['mold_c']=a.mold_i
a['days_since_clean']=a.days_since_clean
a['days_cf']=days_cf(a)
a['fail']=a.units_produced-a.defective_units
Mi=smf.glm('defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post + C(supplier_code)*(humidity_i+h2)', data=a, family=sm.families.Binomial()).fit()
pf=Mi.predict(a); x=a.copy(); x['days_since_clean']=x.days_cf; pc=Mi.predict(x)
r=(pc*a.units_produced).sum()/(pf*a.units_produced).sum()
print('all-batch imputed: factual pooled',round((pf*a.units_produced).sum()/a.units_produced.sum(),5),'cf',round(a.defective_units.sum()/a.units_produced.sum()*r,5))
# flexible humidity check for Alpha: B-spline on humidity within Alpha only
e=d.copy(); e['alpha']=(e.supplier_code=='SP-01').astype(int)
e['hA']=e.humidity*e.alpha
mm=smf.glm('defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post + C(supplier_code) + C(supplier_code):cr(humidity, df=6)', data=e, family=sm.families.Binomial()).fit()
g=np.arange(13,72,0.25)
xx=pd.DataFrame({'mold_c':e.mold_c.median(),'cycle_time_s':e.cycle_time_s.median(),'machine_age_years':e.machine_age_years.median(),'ambient_temp_c':e.ambient_temp_c.median(),'shift':'Day','line':'L1','days_since_clean':e.days_since_clean.median(),'l2post':0,'supplier_code':'SP-01','humidity':g,'units_produced':500})
pp=mm.predict(xx); print('spline Alpha argmin',g[np.argmin(pp)], 'pooled-llf', round(mm.llf,1), 'vs quad llf', round(mod.llf,1) if False else '')
# leakage check
import statsmodels.api as sm2
X=sm2.add_constant(a[['defective_units','units_produced']]); r2=sm2.OLS(a.qc_inspection_min,X).fit().rsquared
print('R2 qc_inspection on defective & units', round(r2,3))
X2=sm2.add_constant(a[['defective_units']]); print('R2 rework on defective', round(sm2.OLS(a.rework_cost_eur,X2).fit().rsquared,4))
print('R2 qc on units only', round(sm2.OLS(a.qc_inspection_min,sm2.add_constant(a[['units_produced']])).fit().rsquared,3))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
import warnings; warnings.filterwarnings('ignore')
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
g=np.arange(13,72,0.25)
def xgrid():
    return pd.DataFrame({'mold_c':d.mold_c.median(),'cycle_time_s':d.cycle_time_s.median(),'machine_age_years':d.machine_age_years.median(),'ambient_temp_c':d.ambient_temp_c.median(),'shift':'Day','line':'L1','days_since_clean':d.days_since_clean.median(),'l2post':0,'supplier_code':'SP-01','humidity':g,'units_produced':500,'h2':g**2})
for dfk in [4,5,6,8]:
    mm=smf.glm('defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post + C(supplier_code) + C(supplier_code):cr(humidity, df=%d)'%dfk, data=d, family=sm.families.Binomial()).fit()
    pp=mm.predict(xgrid())
    i=np.argmin(pp); print('df',dfk,'argmin',g[i],'llf',round(mm.llf,1), 'rate at 25/30/35', [round(float(pp.iloc[np.argmin(abs(g-v))]),4) for v in [25,30,35]])
# quadratic Alpha-only reference
qm=smf.glm('defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post + C(supplier_code) + C(supplier_code):(humidity+h2)', data=d, family=sm.families.Binomial()).fit()
pp=qm.predict(xgrid()); print('quad argmin',g[np.argmin(pp)],'llf',round(qm.llf,1))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from full import *
import warnings; warnings.filterwarnings('ignore')
d['l2post']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
g=np.arange(13,72,0.25)
def xgrid():
    return pd.DataFrame({'mold_c':d.mold_c.median(),'cycle_time_s':d.cycle_time_s.median(),'machine_age_years':d.machine_age_years.median(),'ambient_temp_c':d.ambient_temp_c.median(),'shift':'Day','line':'L1','days_since_clean':d.days_since_clean.median(),'l2post':0,'supplier_code':'SP-01','humidity':g,'units_produced':500})
for dfk in [8,10,12]:
    mm=smf.glm('defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + days_since_clean + l2post + C(supplier_code) + C(supplier_code):cr(humidity, df=%d)'%dfk, data=d, family=sm.families.Binomial()).fit()
    pp=mm.predict(xgrid())
    print('df',dfk,'argmin',g[np.argmin(pp)],'llf',round(mm.llf,1), 'pearson/df', round(mm.pearson_chi2/mm.df_resid,3))
    print('  curve(all 0.5 steps 15..50):', {int(v):round(float(pp.iloc[np.argmin(abs(g-v))]),4) for v in range(15,51,3)})
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-my80c9ql/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
from c3 import *
d['days_cf']=days_cf(d)
mm=smf.glm('defective_units + fail ~ mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(line) + cr(days_since_clean, df=4) + l2post + C(supplier_code) + C(supplier_code):cr(humidity, df=8)', data=d, family=sm.families.Binomial()).fit()
for s in ['SP-01','SP-02','SP-03']:
    x=d.copy(); x['supplier_code']=s
    print('C1 flex',s, round((mm.predict(x)*x.units_produced).sum()/x.units_produced.sum(),5))
x=d.copy(); x['days_since_clean']=x.days_cf
pf=mm.predict(d); pc=mm.predict(x)
print('C3 flex: factual', round((pf*d.units_produced).sum()/d.units_produced.sum(),5), 'cf', round((pc*d.units_produced).sum()/d.units_produced.sum(),5))
" 2>&1 | grep -v -i warn
