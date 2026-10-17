ls -la && for f in *.csv; do echo "== $f"; wc -l "$f"; head -5 "$f"; done

python3 -c "
import pandas as pd
df = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc = df[c].value_counts(dropna=False)
    print('==', c, 'unique=', df[c].nunique(), 'empty=', (df[c].str.strip()=='').sum())
    if df[c].nunique() < 40: print(vc.to_string())
    else: print(df[c].sample(12, random_state=1).tolist())
print('dup batch_id rows:', df.batch_id.duplicated().sum(), 'full dup rows:', df.duplicated().sum())
"
echo ---; cat suppliers.csv; echo ---; python3 -c "
import pandas as pd
m=pd.read_csv('maintenance.csv', dtype=str, keep_default_na=False)
print(m.event.value_counts(), m.line.value_counts(), m.date.min(), m.date.max(), m.note.value_counts())
print(m.date.str.match(r'^\d{4}-\d{2}-\d{2}$').all())
print(m[~m.date.str.match(r'^\d{4}-\d{2}-\d{2}$')])
"

python3 -c "
import pandas as pd, numpy as np
df = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    s=df[c].str.strip()
    bad=s[pd.to_numeric(s, errors='coerce').isna() & (s!='')]
    print(c, 'nonnumeric:', bad.unique()[:10], 'blank:', (s=='').sum())
    v=pd.to_numeric(s, errors='coerce')
    print('   describe:', v.describe().round(2).to_dict())
print(df[df.humidity_pct.str.strip()==''].shape)
# humidity raw values sorted extremes
h=pd.to_numeric(df.humidity_pct, errors='coerce')
print('hum<0', (h<0).sum(), 'hum>100', (h>100).sum(), 'hum==0', (h==0).sum())
print(sorted(df.humidity_pct.unique(), key=lambda x: (x=='', x))[:5], sorted(df.humidity_pct.unique())[-5:])
t=pd.to_numeric(df.mold_temp)
print(np.histogram(t, bins=[0,150,180,200,230,250,300,350,400,500]))
"
echo ---; cat maintenance.csv | grep -v mold_cleaning; echo; grep -c . maintenance.csv

python3 -c "
import pandas as pd, numpy as np
df = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
print('after dedupe', len(df), df.batch_id.nunique())
d = df.copy()
d['mt']=pd.to_numeric(d.mold_temp); d['hum']=pd.to_numeric(d.humidity_pct, errors='coerce')
d['date']=pd.to_datetime(d.production_date)
print('mold zeros:', (d.mt==0).sum(), d[d.mt==0].line.value_counts().to_dict(), d[d.mt==0].production_date.agg(['min','max']).tolist())
print('defect>units', (pd.to_numeric(d.defective_units)>pd.to_numeric(d.units_produced)).sum())
print('dup batch ids after dedupe:', d.batch_id.duplicated().sum())
dd=d[d.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(dd.head(6).to_string())
# F rows
d['F']=d.mt>300
print('F rows by line', d[d.F].line.value_counts().to_dict(), 'F rows by month', d[d.F].date.dt.month.value_counts().sort_index().to_dict())
print('F date range', d[d.F].date.min(), d[d.F].date.max())
print(d[d.F].mt.describe())
print('C rows by line & month median'); c=d[(d.mt>100)&(d.mt<300)]
print(c.groupby([c.line, c.date.dt.month]).mt.median().unstack().round(1))
"

python3 -c "
import pandas as pd, numpy as np
d = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
d['mt']=pd.to_numeric(d.mold_temp); d['date']=pd.to_datetime(d.production_date)
l3=d[d.line=='L3']
print('L3 non-F values:', sorted(l3[(l3.mt<300)].mt.round(1).tolist())[:60])
print('L3 F min:', l3[l3.mt>300].mt.min())
# L1 vs others, weekly medians, excluding zeros and F
c=d[(d.mt>100)&(d.mt<300)].copy()
c['w']=c.date.dt.to_period('W').dt.start_time
t=c.groupby(['w','line']).mt.median().unstack()
print(t.loc['2025-03-01':'2025-05-15'].round(1).to_string())
print(t.loc['2025-08-15':].round(1).to_string())
"

SP=/tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p $SP && mv /tmp/edabench_claude_ech1qe1c/clean.py $SP/clean.py && cd $SP && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd
df,mnt=load()
print('unique batches', df.batch_id.nunique(), len(df))
print('humidity invalid (blank or -1):', (~df.humidity_valid).sum())
print('shift', df['shift'].value_counts(dropna=False).to_dict())
print('supplier', df.supplier_name.value_counts(dropna=False).to_dict())
print('A3 overall defect rate', df.defective_units.sum()/df.units_produced.sum())
print('A4 median mold temp', df.mold_temp.median(), df.mold_temp.notna().sum())
print(df.mold_temp.describe())
print('mold by line', df.groupby('line').mold_temp.median().round(2).to_dict())
"

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
df,_=load()
import statsmodels.api as sm
print('statsmodels ok')
print(df[['defect_rate','defective_units','units_produced','qc_inspection_min','rework_cost_eur','cycle_time_s','mold_temp','humidity_pct','ambient_temp_c','machine_age_years']].corr().round(3).to_string())
r=df.rework_cost_eur/df.defective_units
print('rework per defect describe', r.describe().round(3).to_dict())
print('qc vs defects corr', df[['qc_inspection_min','defective_units','defect_rate']].corr().round(3).to_string())
" 2>&1 | tail -40

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
print('n', len(d))
m=smf.wls('defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)', data=d, weights=d.units_produced).fit()
print(m.summary().tables[1])
" 2>&1 | tail -50

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
print(d.operator_id.nunique(), d.shift.unique(), d.supplier_name.unique(), d.line.unique())
X=pd.get_dummies(d[['operator_id','shift','supplier_name','line']], drop_first=True).astype(float)
X['const']=1
print('rank', np.linalg.matrix_rank(X.values), X.shape)
# check collinear pairs in dummies
print(d.groupby(['line','supplier_name']).size().unstack())
print(d.groupby(['line','shift']).size().unstack())
" 2>&1 | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
X=pd.get_dummies(d[['operator_id','shift','supplier_name','line']], drop_first=True).astype(float)
X['const']=1
print('rank', np.linalg.matrix_rank(X.values), X.shape)
print(d.groupby(['line','supplier_name']).size().unstack())
print(d.groupby(['line','shift']).size().unstack())
print(d.groupby(['operator_id']).size().to_dict())
" 2>&1 | tail -30

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
from scipy import stats
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
base='defect_rate ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + C(line)'
m0=smf.wls(base, d, weights=d.units_produced).fit()
m1=smf.wls(base+' + C(operator_id)', d, weights=d.units_produced).fit()
m2=smf.wls(base+' + machine_age_years', d, weights=d.units_produced).fit()
print('operator F-test p:', stats.f.sf(((m0.ssr-m1.ssr)/(m1.df_model-m0.df_model))/(m1.ssr/m1.df_resid), m1.df_model-m0.df_model, m1.df_resid))
print('machine age added p', m2.pvalues['machine_age_years'])
# residual over time by line, rolling by month
d['res']=m0.resid
d['month']=d.production_date.dt.to_period('M')
print(d.groupby(['month','line']).res.mean().unstack().round(4).to_string())
" 2>&1 | tail -60

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
base='defect_rate ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + C(line)'
m0=smf.wls(base, d, weights=d.units_produced).fit()
d['res']=m0.resid
print('resid sd', d.res.std().round(4))
out=[]
for ln,g in d.groupby('line'):
    g=g.sort_values('production_date')
    dates=sorted(g.production_date.unique())
    best=None
    for dt in dates[10:-10]:
        a=g[g.production_date<dt].res; b=g[g.production_date>=dt].res
        t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(t)>abs(best[1]): best=(dt,t,b.mean()-a.mean(),len(a),len(b))
    out.append((ln,)+best)
for o in out: print(o[0], pd.Timestamp(o[1]).date(), 't=%.2f'%o[2], 'diff=%.4f'%o[3], o[4], o[5])
" 2>&1 | grep -v Warn | tail -20

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && grep -E "L1|L2" /tmp/edabench_claude_ech1qe1c/maintenance.csv | sort -t, -k1,1 && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
base='defect_rate ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + C(line)'
m0=smf.wls(base, d, weights=d.units_produced).fit()
d['res']=m0.resid
d['w']=d.production_date.dt.to_period('W').dt.start_time
t=d[d.line.isin(['L1','L2'])].groupby(['w','line']).res.mean().unstack()
print(t.loc['2025-01-01':'2025-03-31'].round(4).to_string())
print(t.loc['2025-05-26':'2025-07-14'].round(4).to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
base='defect_rate ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + C(line)'
m0=smf.wls(base, d, weights=d.units_produced).fit()
d['res']=m0.resid
g=d[d.line=='L2'].sort_values('production_date')
w=g[(g.production_date>='2025-06-05')&(g.production_date<='2025-06-24')]
print(w[['batch_id','production_date','shift','supplier_name','mold_temp','humidity_pct','cycle_time_s','ambient_temp_c','defect_rate','res']].round(4).to_string())
# all-line daily count check: does a batch exist on 06-14..06-16 for L2
print(g.groupby('production_date').size().loc['2025-06-10':'2025-06-20'])
# finer: compare mean residual for the date windows around the break
for dt in ['2025-06-13','2025-06-14','2025-06-15','2025-06-16','2025-06-17']:
    a=g[g.production_date<dt].res; b=g[g.production_date>=dt].res
    print(dt, round(b.mean()-a.mean(),4), len(a), len(b))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
f='defect_rate ~ mold_temp + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + C(line) + humidity_pct'
m=smf.wls(f, d, weights=d.units_produced).fit(); print(m.params[['mold_temp','cycle_time_s','ambient_temp_c','humidity_pct']].round(5).to_dict(), m.pvalues[['humidity_pct','ambient_temp_c']].round(4).to_dict())
for s in ['Alpha','Beta','Gamma']:
    g=d[d.supplier_name==s]
    mm=smf.wls('defect_rate ~ mold_temp + cycle_time_s + ambient_temp_c + C(shift) + C(line) + humidity_pct', g, weights=g.units_produced).fit()
    print(s, len(g), 'hum', round(mm.params.humidity_pct,6), round(mm.pvalues.humidity_pct,4), 'amb', round(mm.params.ambient_temp_c,5), round(mm.pvalues.ambient_temp_c,4))
# ambient per line
for ln in ['L1','L2','L3','L4']:
    g=d[d.line==ln]
    mm=smf.wls('defect_rate ~ mold_temp + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + humidity_pct', g, weights=g.units_produced).fit()
    print(ln, 'amb', round(mm.params.ambient_temp_c,5), round(mm.pvalues.ambient_temp_c,4), 'mold', round(mm.params.mold_temp,5), 'cyc', round(mm.params.cycle_time_s,5))
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['l2shift']=((d.line=='L2')&(d.production_date>='2025-06-15')).astype(int)
f='defect_rate ~ mold_temp + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + C(line) + humidity_pct + l2shift'
m=smf.wls(f, d, weights=d.units_produced).fit()
print('with L2 step: amb', round(m.params.ambient_temp_c,5), round(m.pvalues.ambient_temp_c,4), 'l2shift', round(m.params.l2shift,4), 'hum', round(m.params.humidity_pct,5), round(m.pvalues.humidity_pct,4))
# check humidity shape for Alpha: quadratic
a=d[d.supplier_name=='Alpha'].copy()
for ff in ['defect_rate ~ mold_temp + cycle_time_s + ambient_temp_c + C(shift) + C(line) + humidity_pct + I(humidity_pct**2)+ l2shift']:
    mm=smf.wls(ff, a, weights=a.units_produced).fit()
    print('Alpha quad', mm.params.round(6).to_dict()); print(mm.pvalues[['humidity_pct','I(humidity_pct ** 2)']].round(4).to_dict())
b=d[d.supplier_name!='Alpha'].copy()
mm=smf.wls('defect_rate ~ mold_temp + cycle_time_s + ambient_temp_c + C(shift) + C(line) + C(supplier_name) + humidity_pct + I(humidity_pct**2)+ l2shift', b, weights=b.units_produced).fit()
print('nonAlpha quad', mm.params[['humidity_pct','I(humidity_pct ** 2)']].round(6).to_dict(), mm.pvalues[['humidity_pct','I(humidity_pct ** 2)']].round(4).to_dict())
# binned humidity mean defect for Alpha
a['hb']=pd.cut(a.humidity_pct,[0,15,20,25,30,35,40,45,50,55,60,75])
print(a.groupby('hb', observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['l2shift']=((d.line=='L2')&(d.production_date>='2025-06-15')).astype(int)
d['alpha']=(d.supplier_name=='Alpha').astype(int)
base='C(shift) + C(supplier_name) + C(line) + l2shift + humidity_pct + I(humidity_pct**2) + cycle_time_s + mold_temp'
for name,f in {
 'lin': 'defect_rate ~ '+base+' + ambient_temp_c',
 'mold quad': 'defect_rate ~ '+base.replace('mold_temp','mold_temp + I(mold_temp**2)')+' + ambient_temp_c',
 'mold quad + cyc quad': 'defect_rate ~ '+base.replace('mold_temp','mold_temp + I(mold_temp**2)').replace('cycle_time_s','cycle_time_s + I(cycle_time_s**2)')+' + ambient_temp_c',
 'no ambient': 'defect_rate ~ '+base.replace('mold_temp','mold_temp + I(mold_temp**2)').replace('cycle_time_s','cycle_time_s + I(cycle_time_s**2)'),
}.items():
    m=smf.wls(f, d, weights=d.units_produced).fit()
    keys=[k for k in m.params.index if 'ambient' in k or 'mold' in k]
    print(name, 'R2', round(m.rsquared,4), 'AIC', round(m.aic,1), {k:(round(m.params[k],6), round(m.pvalues[k],4)) for k in keys})
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,_=load()
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['l2shift']=((d.line=='L2')&(d.production_date>='2025-06-15')).astype(int)
d['hq']=d.humidity_pct
base='defect_rate ~ C(shift) + C(supplier_name) + C(line) + l2shift + humidity_pct + I(humidity_pct**2) + cycle_time_s + mold_temp + I(mold_temp**2) + ambient_temp_c'
def run(name, g, f=base):
    m=smf.wls(f, g, weights=g.units_produced).fit()
    print(f'{name:28s} n={len(g):5d} amb={m.params.ambient_temp_c:.5f} p={m.pvalues.ambient_temp_c:.4f}')
run('all', d)
run('excl L3', d[d.line!='L3'])
run('excl L1 post-Apr14', d[~((d.line=='L1')&(d.production_date>='2025-04-14'))])
run('L1 pre-Apr only', d[(d.line=='L1')&(d.production_date<'2025-04-14')])
run('excl L2 step', d[~((d.line=='L2')&(d.production_date>='2025-06-15'))])
# mold x line interaction
f2=base+' + C(line):mold_temp'
m=smf.wls(f2, d, weights=d.units_produced).fit(); print('mold x line p', m.compare_f_test(smf.wls(base,d,weights=d.units_produced).fit())[1])
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,mnt=load()
cl=mnt[mnt.event=='mold_cleaning'].copy(); cl['date']=pd.to_datetime(cl.date)
print('cleanings per line', cl.groupby('line').size().to_dict())
# gaps between consecutive cleanings per line within period (plus the one before period)
for ln,g in cl.sort_values('date').groupby('line'):
    dd=g.date.diff().dt.days.dropna()
    print(ln, 'max gap', dd.max(), 'gaps>14:', (dd>14).sum(), 'first', g.date.min().date())
def days_since(row_line, row_date):
    g=cl[(cl.line==row_line)&(cl.date<=row_date)]
    return (row_date-g.date.max()).days if len(g) else np.nan
df['days_since']=[days_since(l,dt) for l,dt in zip(df.line, df.production_date)]
print(df.days_since.describe().round(2).to_dict(), df.days_since.isna().sum())
print(df.groupby(pd.cut(df.days_since,[-1,0,3,7,10,14,21,28,40])).defect_rate.agg(['mean','size']).round(4))
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['l2shift']=((d.line=='L2')&(d.production_date>='2025-06-15')).astype(int)
base='defect_rate ~ C(shift) + C(supplier_name) + C(line) + l2shift + humidity_pct + I(humidity_pct**2) + cycle_time_s + mold_temp + I(mold_temp**2) + ambient_temp_c'
m0=smf.wls(base,d,weights=d.units_produced).fit()
m1=smf.wls(base+' + days_since',d,weights=d.units_produced).fit()
print('days_since coef', m1.params.days_since, m1.pvalues.days_since)
m2=smf.wls(base+' + days_since + I(days_since**2)',d,weights=d.units_produced).fit()
print('quad', m2.params[['days_since','I(days_since ** 2)']].to_dict(), m2.pvalues[['days_since','I(days_since ** 2)']].round(5).to_dict())
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import sys; sys.path.insert(0,'.')
from clean import load
import pandas as pd, numpy as np
import statsmodels.formula.api as smf
df,mnt=load()
cl=mnt[mnt.event=='mold_cleaning'].copy(); cl['date']=pd.to_datetime(cl.date)
def ds(l,dt):
    g=cl[(cl.line==l)&(cl.date<=dt)]; return (dt-g.date.max()).days
df['days_since']=[ds(l,dt) for l,dt in zip(df.line, df.production_date)]
df['over14']=(df.days_since>14).astype(int)
df['hinge']=np.maximum(df.days_since-14,0)
d=df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['l2shift']=((d.line=='L2')&(d.production_date>='2025-06-15')).astype(int)
base='defect_rate ~ C(shift) + C(supplier_name) + C(line) + l2shift + humidity_pct + I(humidity_pct**2) + cycle_time_s + mold_temp + I(mold_temp**2) + ambient_temp_c'
res={}
for name,add in {'linear':' + days_since','step14':' + over14','hinge14':' + hinge','linear+step14':' + days_since + over14'}.items():
    m=smf.wls(base+add,d,weights=d.units_produced).fit(); res[name]=m
    print(f'{name:14s} AIC={m.aic:.1f} R2={m.rsquared:.4f}', {k:round(v,6) for k,v in m.params.items() if k in ['days_since','over14','hinge']})
" 2>&1 | grep -v -i warn

cd /tmp/claude-0/-tmp-edabench-claude-ech1qe1c/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 answers.py 2>&1 | tail -30
