ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && cat maintenance.csv && echo && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('---',c,'nunique',df[c].nunique())
    print(vc.head(12).to_dict() if df[c].nunique()<60 else df[c].sample(8,random_state=1).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df['shift'].value_counts().to_dict())
print(df['supplier_code'].value_counts().to_dict())
print(df['line'].value_counts().to_dict())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    s=df[c]
    num=pd.to_numeric(s,errors='coerce')
    bad=s[num.isna()].value_counts().head(15).to_dict()
    print('==',c,'non-numeric:',bad, 'empty:',(s.str.strip()=='').sum())
    print(num.describe().round(2).to_dict())
# duplicates
d=df[df.duplicated('batch_id',keep=False)].sort_values('batch_id')
print('dup rows',len(d), 'dup full-row', df.duplicated().sum())
print(d.head(10).to_string())
"

python3 -c "
import pandas as pd, numpy as np, re
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
mt=pd.to_numeric(df.mold_temp)
print(np.histogram(mt,bins=[0,1,50,100,150,180,200,220,240,260,280,300,320,340,360,380,400,420,440,470]))
print('mold_temp==0 rows:'); print(df[mt==0].to_string())
print('mold_temp>300 sample:', sorted(mt[mt>300].round(1).tolist())[:60])
hum=pd.to_numeric(df.humidity_pct,errors='coerce')
print('humidity <0 or >100:', (hum<0).sum(), (hum>100).sum(), 'values <0:', sorted(hum[hum<=5].dropna().tolist()))
# date formats
ds=df.production_date
fmt=np.where(ds.str.match(r'^\d{4}-\d{2}-\d{2}$'),'iso',np.where(ds.str.match(r'^\d{2}/\d{2}/\d{4}$'),'slash','other'))
print(pd.Series(fmt).value_counts().to_dict())
sl=ds[fmt=='slash']
a=sl.str.slice(0,2).astype(int); b=sl.str.slice(3,5).astype(int)
print('slash first>12:',(a>12).sum(),' second>12:',(b>12).sum(),' both<=12:',((a<=12)&(b<=12)).sum())
print('other examples', ds[fmt=='other'].unique()[:20])
# exact duplicates
dups=df[df.duplicated('batch_id',keep=False)]
print('batch ids with differing dup rows:', (dups.groupby('batch_id').apply(lambda g: g.drop_duplicates().shape[0])>1).sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ds=df.production_date
iso=pd.to_datetime(ds.where(ds.str.contains('-')),format='%Y-%m-%d',errors='coerce')
# unambiguous slash
sl=ds[ds.str.contains('/')]
a=sl.str.slice(0,2).astype(int); b=sl.str.slice(3,5).astype(int)
print('ISO range', iso.min(), iso.max(), 'ISO monotone in row order?', (iso.dropna().diff().dt.days.fillna(0)>=0).mean())
# rows index of ISO rows: check monotonicity of ISO subsequence
idx=iso.dropna().index
s=iso.dropna()
print('fraction of consecutive ISO pairs non-decreasing:', (s.diff().dt.days.dropna()>=0).mean())
print(s.head(20).tolist())
print(s.tail(10).tolist())
print(ds.head(30).tolist())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ds=df.production_date
iso=pd.to_datetime(ds.where(ds.str.contains('-')),format='%Y-%m-%d',errors='coerce')
s=iso.dropna()
d=s.diff().dt.days
bad=d[d<0]
print(len(bad), bad.value_counts().head(10).to_dict())
for i in bad.index[:8]:
    p=s.index.get_loc(i)
    print(df.loc[s.index[p-2:p+2],['production_date','line','batch_id']].to_string())
    print()
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ds=df.production_date
df['iso']=pd.to_datetime(ds.where(ds.str.contains('-')),format='%Y-%m-%d',errors='coerce')
for L,g in df.groupby('line'):
    s=g['iso'].dropna()
    d=s.diff().dt.days
    print(L, 'backward steps:', (d<0).sum(), 'min/max', s.min().date(), s.max().date(), 'n', len(s))
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
ds=df.production_date
df['fmt']=np.where(ds.str.contains('-'),'iso',np.where(ds.str.contains('/'),'slash','other'))
print(pd.crosstab(df.line,df.fmt))
sl=df[df.fmt=='slash'].copy()
sl['a']=sl.production_date.str.slice(0,2).astype(int); sl['b']=sl.production_date.str.slice(3,5).astype(int)
print(pd.crosstab(sl.line,[sl.a>12, sl.b>12]))
print(sl.groupby('line').apply(lambda g: g.production_date.head(12).tolist()))
"

mkdir -p "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py" <<'EOF'
import pandas as pd, numpy as np

DIR = '/tmp/edabench_claude_j9ytxn_t/'

def load_raw():
    return pd.read_csv(DIR + 'batches.csv', dtype=str, keep_default_na=False)

def clean():
    raw = load_raw()
    n_raw = len(raw)
    df = raw.drop_duplicates().copy()           # 60 exact duplicate rows
    for c in df.columns:
        df[c] = df[c].str.strip()
    # production_date: line-specific formats (L1 mm/dd/yyyy, L4 dd/mm/yyyy, L2/L3 ISO)
    def parse_date(row):
        s = row.production_date
        if row.line == 'L1':
            return pd.to_datetime(s, format='%m/%d/%Y')
        if row.line == 'L4':
            return pd.to_datetime(s, format='%d/%m/%Y')
        return pd.to_datetime(s, format='%Y-%m-%d')
    df['date'] = df.apply(parse_date, axis=1)
    df['shift'] = df['shift'].str.upper().str[0].map({'D': 'Day', 'N': 'Night'})
    df['supplier_code'] = df['supplier_code'].str.upper()
    for c in ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct',
              'cycle_time_s', 'units_produced', 'defective_units',
              'qc_inspection_min', 'rework_cost_eur']:
        df[c] = pd.to_numeric(df[c].replace('', np.nan), errors='coerce')
    # mold_temp: 0.0 is a sentinel; readings above 300 are Fahrenheit
    df.loc[df.mold_temp == 0, 'mold_temp'] = np.nan
    f = df.mold_temp > 300
    df.loc[f, 'mold_temp'] = (df.loc[f, 'mold_temp'] - 32) * 5 / 9
    df['mold_f'] = f
    # humidity: blank or -1.0 sentinel is invalid
    df.loc[df.humidity_pct < 0, 'humidity_pct'] = np.nan
    df = df.drop(columns=['production_date'])
    return raw, df
EOF
cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean
raw, df = clean()
print('raw',len(raw),'after dedup',len(df),'unique ids',df.batch_id.nunique())
print('dup ids remaining', df.batch_id.duplicated().sum())
print(df.groupby(['line','mold_f']).size().unstack(fill_value=0))
f=df[df.mold_f]
print('F rows date range', f.date.min(), f.date.max())
print(f.groupby('line').date.agg(['min','max','count']))
print(df.groupby('line').mold_temp.describe().round(1))
print('defective>units', (df.defective_units>df.units_produced).sum())
print(df.shift.value_counts(dropna=False).to_dict(), df.supplier_code.value_counts().to_dict())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, load_raw
raw, df = clean()
print(df[(df.line=='L3')&(~df.mold_f)][['batch_id','date','shift','mold_temp','humidity_pct','supplier_code']].to_string())
print(df[(df.line=='L3')&(df.mold_f)].mold_temp.describe().round(2).to_dict())
print(df[(df.line!='L3')].mold_temp.describe().round(2).to_dict())
print(df['shift'].value_counts(dropna=False).to_dict(), df.supplier_code.value_counts().to_dict())
print('missing mold', df.mold_temp.isna().sum(), 'missing hum', df.humidity_pct.isna().sum())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean
raw, df = clean()
print('A1 unique batches', df.batch_id.nunique())
print('A2 humidity missing/invalid', df.humidity_pct.isna().sum())
print('A3 defect rate', df.defective_units.sum()/df.units_produced.sum(), df.defective_units.sum(), df.units_produced.sum())
print('A4 median mold C', df.mold_temp.median(), df.mold_temp.notna().sum())
# L1 sensor replacement check
l1=df[df.line=='L1'].copy()
l1['post']=l1.date>=pd.Timestamp('2025-04-14')
print(l1.groupby('post').mold_temp.describe().round(2))
print(df.groupby('line').apply(lambda g: pd.Series({'rate':g.defective_units.sum()/g.units_produced.sum(),'n':len(g)})).round(4))
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean
raw, df = clean()
df['rate']=df.defective_units/df.units_produced
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','qc_inspection_min','rework_cost_eur','rate']
print(df[num].corr(method='spearman')['rate'].round(3))
print(df.groupby('shift').rate.agg(['mean','count']).round(4))
print(df.groupby('operator_id').rate.mean().round(4).sort_values().to_string())
print(df.groupby('supplier_code').rate.agg(['mean','count']).round(4))
print(df.groupby('line').rate.agg(['mean','count']).round(4))
print('pearson qc vs defect', np.corrcoef(df.qc_inspection_min, df.defective_units)[0,1], np.corrcoef(df.rework_cost_eur, df.defective_units)[0,1])
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import statsmodels, scipy, sklearn; print('ok', statsmodels.__version__)
" ; python3 -c "
import pandas as pd, numpy as np
from clean import clean
raw, df = clean()
print(pd.crosstab(df.operator_id, df.line).to_string())
print(df.groupby('line').machine_age_years.describe().round(2).to_string())
print(df.groupby('line').cycle_time_s.describe().round(2).to_string())
print(pd.crosstab(df.line, df.supplier_code))
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import importlib
for m in ['numpy','pandas','scipy','statsmodels']:
    try:
        mod=importlib.import_module(m); print(m, getattr(mod,'__version__','?'))
    except Exception as e: print(m, 'MISSING', e)
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean
raw, df = clean()
df['rate']=df.defective_units/df.units_produced
def binned(col, bins):
    g=df.groupby(pd.cut(df[col],bins),observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()}))
    print(col); print(g.round(4).to_string())
binned('mold_temp', [180,195,200,205,210,215,220,225,230,240])
binned('humidity_pct', [0,10,15,20,25,30,35,40,45,50,60,75])
binned('cycle_time_s', [17,22,25,27,28,29,30,31,32,33,35,38,46])
binned('ambient_temp_c', [10,15,18,20,22,24,26,28,31])
binned('machine_age_years', [0,3,5,6,7,8,10,12,14,16,18,22])
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > fit1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from clean import clean
raw, df = clean()
d = df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['fail'] = d.units_produced - d.defective_units
d['ok'] = d.defective_units
d['ct_dev'] = d.cycle_time_s
f = ('defective_units + fail ~ mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2)'
     ' + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code)')
y = np.column_stack([d.defective_units, d.fail])
import patsy
yy, X = patsy.dmatrices('defective_units + fail ~ mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code)', d, return_type='dataframe')
m = sm.GLM(yy, X, family=sm.families.Binomial()).fit(scale='X2')
print(m.summary2().tables[1].round(4).to_string())
print('n', len(d), 'dispersion', round(m.scale,3))
EOF
python3 fit1.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat >> clean.py <<'EOF'

def load_maint():
    m = pd.read_csv(DIR + 'maintenance.csv', parse_dates=['date'])
    return m

def add_days_since_clean(df):
    m = load_maint()
    cl = m[m.event == 'mold_cleaning']
    out = np.full(len(df), np.nan)
    for L in df.line.unique():
        dates = np.sort(cl[cl.line == L].date.values)
        idx = np.where(df.line.values == L)[0]
        bd = df.date.values[idx]
        pos = np.searchsorted(dates, bd, side='right') - 1   # last cleaning on or before the batch date
        ok = pos >= 0
        res = np.full(len(idx), np.nan)
        res[ok] = (bd[ok] - dates[pos[ok]]) / np.timedelta64(1, 'D')
        out[idx] = res
    df = df.copy()
    df['days_since_clean'] = out
    return df
EOF
python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
print(df.days_since_clean.describe().round(2).to_dict())
print('missing days', df.days_since_clean.isna().sum())
df['rate']=df.defective_units/df.units_produced
print(df.groupby(pd.cut(df.days_since_clean,[-1,0,2,4,6,8,10,12,14,16,20]),observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
print(df.groupby('line').days_since_clean.max())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > fit2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
recipe = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}
df['recipe_ct'] = df.supplier_code.map(recipe)
df['ct_dev'] = df.cycle_time_s - df.recipe_ct
df['fail'] = df.units_produced - df.defective_units
d = df.dropna(subset=['mold_temp','humidity_pct']).copy()
d['supp'] = d.supplier_code
def fit(rhs, label):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    print(f'{label:55s} dev={m.deviance:12.2f} k={X.shape[1]} aic={m.aic:12.1f}')
    return m
base = 'mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2) + cycle_time_s + I(cycle_time_s**2)'
rest = 'machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code)'
fit(base, 'process only')
fit(base + ' + ' + rest, 'process + all candidates')
fit(base + ' + ' + rest + ' + days_since_clean', '... + days_since_clean')
fit(base + ' + ' + rest + ' + days_since_clean + ct_dev', '... + ct_dev(instead of raw ct)')
EOF
python3 fit2.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > chk.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
d = df.dropna(subset=['mold_temp','humidity_pct']).copy()
yy, X = patsy.dmatrices('defective_units + fail ~ mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code) + days_since_clean', d, return_type='dataframe')
print(yy.head(3)); print(yy.shape, X.shape)
m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
print('deviance', m.deviance, 'pearson chi2', m.pearson_chi2, 'df', m.df_resid, 'n', len(d))
p = m.predict(X)
rate = d.defective_units/d.units_produced
print('sd rate resid', np.std(rate-p), 'binomial sd mean', np.mean(np.sqrt(p*(1-p)/d.units_produced)))
EOF
python3 chk.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > resid.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
d = df.dropna(subset=['mold_temp','humidity_pct']).copy()
rhs = 'mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code) + days_since_clean'
yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
d['pred'] = m.predict(X)
d['rate'] = d.defective_units / d.units_produced
d['res'] = d.rate - d.pred
d['m'] = d.date.dt.to_period('M')
print(d.pivot_table(index='m', columns='line', values='res', aggfunc='mean').round(4).to_string())
print(d.pivot_table(index='m', columns='line', values='res', aggfunc='count').to_string())
d[['batch_id','line','date','rate','pred','res','mold_temp','humidity_pct','cycle_time_s','operator_id','supplier_code','days_since_clean','shift','ambient_temp_c','machine_age_years']].to_pickle('resid.pkl')
EOF
python3 resid.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > scan.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
rhs = 'mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code) + days_since_clean'
yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
base = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
print('base dev', round(base.deviance,1))
# residual-based scan: for each line, cumulative mean residual test per candidate date
d['pred'] = base.predict(X)
d['res'] = d.defective_units/d.units_produced - d.pred
res_out=[]
for L in ['L1','L2','L3','L4']:
    g = d[d.line==L].sort_values('date')
    dates = sorted(g.date.unique())
    best=None
    for t in dates[5:-5]:
        pre = g[g.date<t].res; post = g[g.date>=t].res
        tstat = (post.mean()-pre.mean())/np.sqrt(pre.var()/len(pre)+post.var()/len(post))
        if best is None or abs(tstat)>abs(best[1]): best=(pd.Timestamp(t).date(), tstat, post.mean()-pre.mean(), len(pre), len(post))
    print(L, 'best break', best)
EOF
python3 scan.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > scan2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
rhs = 'mold_temp + I(mold_temp**2) + humidity_pct + I(humidity_pct**2) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(supplier_code) + days_since_clean'
def dev_with_step(L, t):
    dd = d.copy()
    dd['step'] = ((dd.line==L)&(dd.date>=t)).astype(float)
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs + ' + step', dd, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    return m.deviance, m.params['step']
for L, center in [('L1','2025-04-14'),('L2','2025-06-16'),('L3','2025-07-21')]:
    c = pd.Timestamp(center)
    res=[]
    for k in range(-20,21):
        t = c + pd.Timedelta(days=k)
        dv, b = dev_with_step(L,t)
        res.append((t.date(), round(dv,1), round(b,4)))
    res = sorted(res, key=lambda r: r[1])
    print(L, 'best 5:', res[:5])
EOF
python3 scan2.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['rate']=df.defective_units/df.units_produced
brk={'L1':'2025-04-12','L2':'2025-06-16','L3':'2025-07-21'}
for L,t in brk.items():
    g=df[df.line==L].copy(); g['post']=g.date>=pd.Timestamp(t)
    print('=====',L,t)
    print(g.groupby('post').agg(n=('batch_id','size'), rate=('defective_units','sum'), units=('units_produced','sum'), mold=('mold_temp','mean'), hum=('humidity_pct','mean'), ct=('cycle_time_s','mean'), amb=('ambient_temp_c','mean'), age=('machine_age_years','mean'), dsc=('days_since_clean','mean'), units_per=('units_produced','mean')).round(3).to_string())
    g2=g.groupby('post').apply(lambda x: x.defective_units.sum()/x.units_produced.sum())
    print('pooled rate pre/post', g2.round(4).to_dict())
    print(pd.crosstab(g.post, g.supplier_code, normalize='index').round(3).to_string())
    print(pd.crosstab(g.post, g['shift'], normalize='index').round(3).to_string())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > flex.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
df['dsc_bin'] = pd.cut(df.days_since_clean, [-1,4,8,12,16,40], labels=False).astype(str)
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
d['L2post'] = ((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(float)
d['L3post'] = ((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
d['L1post'] = ((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-12'))).astype(float)
def run(rhs, label):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    print(f'{label:45s} dev={m.deviance:9.1f} k={X.shape[1]}', {k: round(m.params[k],3) for k in m.params.index if 'post' in k})
    return m
core = 'cr(mold_temp, df=4) + cr(humidity_pct, df=4) + cr(cycle_time_s, df=4) + cr(ambient_temp_c, df=3) + machine_age_years + C(shift) + C(operator_id) + C(line) + C(supplier_code)'
run(core + ' + C(dsc_bin)', 'flexible, no break')
run(core + ' + C(dsc_bin) + L1post + L2post + L3post', 'flexible + 3 breaks')
run(core + ' + C(dsc_bin) + L2post', 'flexible + L2 break only')
run(core + ' + C(dsc_bin) + L3post', 'flexible + L3 break only')
EOF
python3 flex.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
r=pd.read_pickle('resid.pkl')
r['rate_res']=r.res
g=r.groupby(['line','date'])
within=g.res.transform(lambda x: x-x.mean())
print('total var',r.res.var().round(6),'within line-day var', within.var().round(6), 'ICC approx', (1-within.var()/r.res.var()).round(3))
# lag-1 autocorrelation within line in row order by date
for L,gg in r.sort_values('date').groupby('line'):
    x=gg.res.values
    print(L,'lag1 autocorr', np.corrcoef(x[:-1],x[1:])[0,1].round(3), 'n',len(x))
# residual variance by rate level
r['pbin']=pd.qcut(r.pred,5)
print(r.groupby('pbin',observed=True).res.agg(['std','mean','count']).round(4))
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['wk']=df.date.dt.to_period('W').dt.start_time.dt.strftime('%m-%d')
t=df.groupby(['wk','line']).apply(lambda g: pd.Series({'rate':g.defective_units.sum()/g.units_produced.sum(),'mold':g.mold_temp.mean(),'amb':g.ambient_temp_c.mean(),'dsc':g.days_since_clean.mean(),'n':len(g)})).round(3)
print(t.unstack('line')['rate'].to_string())
print(t.unstack('line')['n'].to_string())
" 

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['post_L3']=(df.line=='L3')&(df.date>=pd.Timestamp('2025-07-21'))
df['post_L2']=(df.line=='L2')&(df.date>=pd.Timestamp('2025-06-16'))
for col,flag in [('L3','post_L3'),('L2','post_L2')]:
    g=df[df.line==col].copy()
    g['post']=g[flag]
    print('===',col)
    print(g.groupby('post').apply(lambda x: pd.Series({'n':len(x),'qc_min':x.qc_inspection_min.mean(),'rework_per_def':x.rework_cost_eur.sum()/x.defective_units.sum(),'rework_per_batch':x.rework_cost_eur.mean(),'defect_per_batch':x.defective_units.mean(),'units':x.units_produced.mean(),'ct':x.cycle_time_s.mean(),'hum':x.humidity_pct.mean(),'mold':x.mold_temp.mean(),'amb':x.ambient_temp_c.mean(),'dsc':x.days_since_clean.mean()})).round(3).to_string())
# mold temp per unit: is L3 post F-conversion shifted? show raw F values pre/post
raw2=raw.copy()
raw2['mt']=pd.to_numeric(raw2.mold_temp,errors='coerce')
raw2['L']=raw2.line
print(raw2[raw2.L=='L3'].assign(postJ=lambda x: x.batch_id.isin(df[df.post_L3].batch_id)).groupby('postJ').mt.describe().round(1).to_string())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
g=df[df.line=='L3'].sort_values(['date']).copy()
print(g[(g.date>='2025-07-10')&(g.date<='2025-08-01')][['date','batch_id','shift','defective_units','units_produced','qc_inspection_min','rework_cost_eur','mold_temp','days_since_clean']].assign(rate=lambda x: (x.defective_units/x.units_produced).round(4)).to_string())
" | head -80

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > flex2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
df['dsc_bin'] = pd.cut(df.days_since_clean, [-1,4,8,12,16,40], labels=False).astype(str)
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
t0 = {'L1': pd.Timestamp('2025-04-12'), 'L2': pd.Timestamp('2025-06-16'), 'L3': pd.Timestamp('2025-07-21')}
d['L2post'] = ((d.line=='L2')&(d.date>=t0['L2'])).astype(float)
d['L3post'] = ((d.line=='L3')&(d.date>=t0['L3'])).astype(float)
d['L2ramp'] = np.where(d.line=='L2', np.clip((d.date-pd.Timestamp('2025-05-01')).dt.days,0,None), 0)
d['L3ramp'] = np.where(d.line=='L3', np.clip((d.date-pd.Timestamp('2025-05-01')).dt.days,0,None), 0)
def run(rhs, label):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    keep={k: round(m.params[k],3) for k in m.params.index if any(s in k for s in ['post','ramp','days'])}
    print(f'{label:50s} dev={m.deviance:9.1f} k={X.shape[1]}', keep)
core = 'cr(mold_temp, df=4) + cr(humidity_pct, df=4) + cr(cycle_time_s, df=4) + cr(ambient_temp_c, df=3) + machine_age_years + C(shift) + C(operator_id) + C(line) + C(supplier_code)'
run(core + ' + C(dsc_bin)', 'flex no break')
run(core + ' + C(dsc_bin) + C(line):days_since_clean', 'flex + line-specific days slope')
run(core + ' + C(dsc_bin) + C(line):days_since_clean + L2post', '... + L2 step')
run(core + ' + C(dsc_bin) + L2ramp', 'flex + L2 linear ramp from May 1')
run(core + ' + C(dsc_bin) + L3post', 'flex + L3 step')
run(core + ' + C(dsc_bin) + L3post + L2ramp', 'flex + L3 step + L2 ramp')
EOF
python3 flex2.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > flex3.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
df['dsc_bin'] = pd.cut(df.days_since_clean, [-1,4,8,12,16,40], labels=False).astype(str)
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
d['L2post'] = ((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(float)
d['L3post'] = ((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
def run(rhs, label):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    keep={k: round(m.params[k],3) for k in m.params.index if any(s in k for s in ['post'])}
    print(f'{label:45s} dev={m.deviance:9.1f} k={X.shape[1]}', keep)
    return m
core = 'mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(dsc_bin)'
run(core, 'supplier x humidity, no break')
run(core + ' + L2post + L3post', 'with L2 and L3 steps')
run(core + ' + L2post', 'with L2 step only')
run(core + ' + L3post', 'with L3 step only')
EOF
python3 flex3.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
d=df.dropna(subset=['humidity_pct']).copy()
bins=[0,15,20,25,30,35,40,45,50,55,80]
d['hb']=pd.cut(d.humidity_pct,bins)
t=d.groupby(['hb','supplier_code'],observed=True).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack().round(4)
n=d.groupby(['hb','supplier_code'],observed=True).size().unstack()
print(t.to_string()); print(n.to_string())
d['recipe']=d.supplier_code.map({'SP-01':30,'SP-02':30,'SP-03':36})
d['ctd']=d.cycle_time_s-d.recipe
dd=d.dropna(subset=['mold_temp'])
print(dd.groupby(pd.cut(dd.ctd,[-20,-8,-4,-2,0,2,4,8,20]),observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
print(dd.groupby(['supplier_code']).cycle_time_s.describe().round(2).to_string())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
for L,t in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=df[df.line==L].copy(); g['post']=g.date>=pd.Timestamp(t)
    print('===',L)
    ct=pd.crosstab(g.operator_id,g.post)
    ct['rate_pre']=g[~g.post].groupby('operator_id').apply(lambda x:x.defective_units.sum()/x.units_produced.sum()).round(4)
    ct['rate_post']=g[g.post].groupby('operator_id').apply(lambda x:x.defective_units.sum()/x.units_produced.sum()).round(4)
    print(ct.to_string())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > slopes.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
df['dsc_bin'] = pd.cut(df.days_since_clean, [-1,4,8,12,16,40], labels=False).astype(str)
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
d['L2post'] = ((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(float)
d['L3post'] = ((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
base = 'mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(dsc_bin)'
def run(rhs,label):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    print(f'{label:40s} dev={m.deviance:9.1f} k={X.shape[1]}')
    return m
run(base + ' + L2post + L3post', 'steps only')
# slope changes after each line break for each process var (L2 and L3)
for L,flag in [('L2','L2post'),('L3','L3post')]:
    d['pl'] = (d.line==L).astype(float)
    terms = ['mold_temp','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years']
    extra = ' + '.join([f'{flag}:{t}' for t in terms]) + f' + {flag}:I(humidity_pct**2) + {flag}:I(mold_temp**2)'
    run(base + f' + L2post + L3post + {extra}', f'{L} step + slopes changed')
EOF
python3 slopes.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > stepramp.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
df['dsc_bin'] = pd.cut(df.days_since_clean, [-1,4,8,12,16,40], labels=False).astype(str)
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
d['L3post'] = ((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
base = 'mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + C(dsc_bin) + L3post'
def dev(extra_df, rhs):
    dd = d.copy()
    for k,v in extra_df.items(): dd[k]=v
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, dd, return_type='dataframe')
    return sm.GLM(yy, X, family=sm.families.Binomial()).fit().deviance
L2 = (d.line=='L2').values
res=[]
for t in pd.date_range('2025-05-15','2025-07-15'):
    s = ((d.date>=t)&L2).astype(float)
    res.append(('step',t.date(), dev({'s':s}, base+' + s')))
best_step = sorted([r for r in res if r[0]=='step'], key=lambda r:r[2])[:3]
print('L2 best step dates', [(str(r[1]), round(r[2],1)) for r in best_step])
rr=[]
for t in pd.date_range('2025-05-01','2025-07-01',freq='7D'):
    pass
for t0 in pd.date_range('2025-05-01','2025-07-15'):
    for t1 in [t0+pd.Timedelta(days=k) for k in (14,28)]:
        ramp = np.clip((d.date - t0).dt.days / (t1-t0).days, 0, 1).values * L2
        rr.append((str(t0.date()), str(t1.date()), dev({'r':ramp}, base+' + r')))
rr=sorted(rr,key=lambda r:r[2])[:3]
print('L2 best ramp (start,end,dev)', [(a,b,round(c,1)) for a,b,c in rr])
EOF
python3 stepramp.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np, statsmodels.api as sm
from clean import clean
raw, df = clean()
df['rate']=df.defective_units/df.units_produced
df['post_L2']=(df.line=='L2')&(df.date>=pd.Timestamp('2025-06-16'))
df['post_L3']=(df.line=='L3')&(df.date>=pd.Timestamp('2025-07-21'))
for L,flag in [('L2','post_L2'),('L3','post_L3')]:
    for post in [False,True]:
        g=df[(df.line==L)&(df[flag]==post)]
        X=sm.add_constant(np.column_stack([g.defective_units, g.units_produced]))
        b=np.linalg.lstsq(X, g.qc_inspection_min.values, rcond=None)[0]
        print(L,'post' if post else 'pre', 'n',len(g),'corr(qc,defects)',round(np.corrcoef(g.qc_inspection_min,g.defective_units)[0,1],3),'corr(qc,rate)',round(np.corrcoef(g.qc_inspection_min,g.rate)[0,1],3),'qc mean',round(g.qc_inspection_min.mean(),2), 'coef on defects/units', b.round(4))
# rework per defect overall
df['rw_per_def']=df.rework_cost_eur/df.defective_units
print(df.groupby(['line']).rw_per_def.describe().round(2).to_string())
print(df.groupby(['line',df.post_L2|df.post_L3]).rw_per_def.median().round(2).to_string())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
bins=[-1,4,8,12,16,40]
for L,t in [('L2','2025-06-16'),('L3','2025-07-21'),('L1','2025-04-12'),('L4','2025-09-23')]:
    g=df[df.line==L].copy(); g['post']=g.date>=pd.Timestamp(t); g['db']=pd.cut(g.days_since_clean,bins)
    r=g.groupby(['db','post'],observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':round(x.defective_units.sum()/x.units_produced.sum(),4)})).unstack('post')
    print(L, t); print(r.to_string())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
for L,t in [('L2','2025-06-16'),('L3','2025-07-21')]:
    g=df[(df.line==L)].copy(); g['post']=g.date>=pd.Timestamp(t)
    for col,bins in [('mold_temp',[190,205,212,218,225,240]),('humidity_pct',[0,20,30,40,50,80]),('ambient_temp_c',[10,18,22,25,31]),('cycle_time_s',[17,28,32,36,46])]:
        g['b']=pd.cut(g[col],bins)
        r=g.groupby(['b','post'],observed=True).apply(lambda x: pd.Series({'n':len(x),'rate':round(x.defective_units.sum()/x.units_produced.sum(),4) if len(x) else np.nan})).unstack('post')
        print(L,col); print(r.to_string())
" 2>&1 | head -120

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean, add_days_since_clean
raw, df = clean()
g=df[df.line=='L2'].copy()
g['rate']=g.defective_units/g.units_produced
d=g[(g.date>='2025-05-20')&(g.date<='2025-07-05')].groupby('date').apply(lambda x: pd.Series({'n':len(x),'defects':x.defective_units.sum(),'units':x.units_produced.sum(),'rate':round(x.defective_units.sum()/x.units_produced.sum(),4)}))
print(d.to_string())
" | head -60

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 -c "
import pandas as pd, numpy as np
from clean import clean
raw, df = clean()
df['per_def']=df.rework_cost_eur/df.defective_units
k=df[df.line.isin(['L1','L2','L4'])].per_def.median()
print('pooled cost per defect (L1,L2,L4 median):', round(k,3))
df['impl_def']=df.rework_cost_eur/k
brk={'L2':'2025-06-16','L3':'2025-07-21','L1':'2025-04-12'}
for L,t in brk.items():
    g=df[df.line==L].copy(); g['post']=g.date>=pd.Timestamp(t)
    r=g.groupby('post').apply(lambda x: pd.Series({'n':len(x),'recorded_rate':x.defective_units.sum()/x.units_produced.sum(),'implied_rate':x.impl_def.sum()/x.units_produced.sum(),'impl_over_rec':x.impl_def.sum()/x.defective_units.sum()}))
    print(L); print(r.round(4).to_string())
g=df.copy(); g['post']=False
for L,t in brk.items(): pass
print(df.groupby('line').apply(lambda x: x.impl_def.sum()/x.defective_units.sum()).round(3).to_dict())
"

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > final.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from clean import clean, add_days_since_clean
raw, df = clean()
df = add_days_since_clean(df)
df['fail'] = df.units_produced - df.defective_units
d = df.dropna(subset=['mold_temp','humidity_pct']).copy().reset_index(drop=True)
d['recipe'] = d.supplier_code.map({'SP-01':30,'SP-02':30,'SP-03':36})
d['ct_dev'] = d.cycle_time_s - d.recipe
d['L1post'] = ((d.line=='L1')&(d.date>=pd.Timestamp('2025-04-14'))).astype(float)
d['L2post'] = ((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(float)
d['L3post'] = ((d.line=='L3')&(d.date>=pd.Timestamp('2025-07-21'))).astype(float)
REG = ' + L1post + L2post + L3post'
CORE = ('mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code)'
        ' + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id) + C(line) + days_since_clean')
def fit(rhs, label, data=d):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, data, return_type='dataframe')
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    pear = m.pearson_chi2 / m.df_resid
    print(f'{label:30s} dev={m.deviance:10.2f} k={X.shape[1]} pearson/df={pear:.3f}')
    return m, pear
full, phi = fit(CORE + REG, 'full')
print('dispersion phi', round(phi,3))
print(full.params.round(4).to_string())
EOF
python3 final.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat >> final.py <<'EOF'

from scipy import stats
def drop(term_str, label, dfdrop):
    rhs = CORE.replace(term_str, '1', 1) if False else None
    return None
terms = {
 'mold_temp': ['mold_temp + I(mold_temp**2)'],
 'humidity_pct': ['humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code)'],
 'cycle_time_s': ['cycle_time_s + I(cycle_time_s**2)'],
 'machine_age_years': ['machine_age_years'],
 'ambient_temp_c': ['ambient_temp_c'],
 'operator_id': ['C(operator_id)'],
 'shift': ['C(shift)'],
}
base_rhs = CORE + REG
# build reduced formulas by removing term strings
for name, parts in terms.items():
    red = base_rhs
    for p in parts:
        red = red.replace(' + ' + p, '').replace(p + ' + ', '')
    # special-case: humidity terms appear in CORE as two chunks
    if name=='humidity_pct':
        red = base_rhs.replace('humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + ','').replace(' + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code)','')
    if name=='mold_temp':
        red = base_rhs.replace('mold_temp + I(mold_temp**2) + ','')
    if name=='cycle_time_s':
        red = base_rhs.replace(' + cycle_time_s + I(cycle_time_s**2)','')
    if name=='machine_age_years':
        red = base_rhs.replace(' + machine_age_years','')
    if name=='ambient_temp_c':
        red = base_rhs.replace(' + ambient_temp_c','')
    if name=='operator_id':
        red = base_rhs.replace(' + C(operator_id)','')
    if name=='shift':
        red = base_rhs.replace(' + C(shift)','')
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + red, d, return_type='dataframe')
    m0 = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    ddev = m0.deviance - full.deviance
    k = full.df_model - m0.df_model
    F = (ddev/k)/phi
    p = stats.f.sf(F, k, full.df_resid)
    print(f'{name:20s} df={int(k):2d} ddev={ddev:9.2f} F={F:8.2f} p={p:.3g}')
EOF
python3 final.py 2>&1 | tail -10

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > oper.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from scipy import stats
exec(open('final.py').read().split("full, phi = fit")[0])
print(pd.crosstab(d.operator_id, d['shift']).T.to_string())
full, phi = fit(CORE + REG, 'full')
# operator test with L2 as ramp instead of step, and no regime terms
def test(rhs_full, rhs_red, label):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs_full, d, return_type='dataframe')
    mf = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    ph = mf.pearson_chi2/mf.df_resid
    yy, X2 = patsy.dmatrices('defective_units + fail ~ ' + rhs_red, d, return_type='dataframe')
    mr = sm.GLM(yy, X2, family=sm.families.Binomial()).fit()
    k = mf.df_model - mr.df_model
    F = ((mr.deviance-mf.deviance)/k)/ph
    print(f'{label:45s} F={F:6.2f} p={stats.f.sf(F,k,mf.df_resid):.4g} phi={ph:.2f}')
ops = 'C(operator_id)'
rest = 'mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + cycle_time_s + I(cycle_time_s**2) + C(shift) + C(line) + days_since_clean'
test(rest + ' + ' + ops + REG + ' + machine_age_years', rest + REG + ' + machine_age_years', 'operator, with regimes')
test(rest + ' + ' + ops + ' + machine_age_years', rest + ' + machine_age_years', 'operator, no regimes')
EOF
python3 oper.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > amb.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from scipy import stats
exec(open('final.py').read().split("full, phi = fit")[0])
def coef_test(data, label, rhs_full, drop_term):
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs_full, data, return_type='dataframe')
    mf = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    ph = mf.pearson_chi2/mf.df_resid
    cols=[c for c in X.columns if c==drop_term]
    b=mf.params[drop_term]; se=mf.bse[drop_term]*np.sqrt(ph)
    print(f'{label:40s} coef={b:8.4f} se(q)={se:.4f} z={b/se:6.2f} phi={ph:.2f}')
rest = 'mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + cycle_time_s + I(cycle_time_s**2) + C(shift) + C(operator_id) + days_since_clean'
noL2 = d[d.line!='L2'].copy()
noL4 = d[d.line!='L4'].copy()
coef_test(noL2, 'ambient, no L2 (L1,L3,L4)', rest + ' + C(line) + ambient_temp_c + machine_age_years + L1post + L3post', 'ambient_temp_c')
coef_test(noL2, 'machine_age, no L2', rest + ' + C(line) + ambient_temp_c + machine_age_years + L1post + L3post', 'machine_age_years')
coef_test(noL4, 'ambient, no L4 (L1,L2,L3)', rest + ' + C(line) + ambient_temp_c + machine_age_years + L1post + L2post + L3post', 'ambient_temp_c')
coef_test(d, 'ambient, all lines, L2 step', rest + ' + C(line) + ambient_temp_c + machine_age_years + L1post + L2post + L3post', 'ambient_temp_c')
coef_test(d, 'machine_age, all lines, L2 step', rest + ' + C(line) + ambient_temp_c + machine_age_years + L1post + L2post + L3post', 'machine_age_years')
EOF
python3 amb.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > oper2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
from scipy import stats
exec(open('final.py').read().split("full, phi = fit")[0])
rest = 'mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code) + cycle_time_s + I(cycle_time_s**2) + days_since_clean + L1post + L2post + L3post'
for L in ['L1','L2','L3','L4']:
    s = d[d.line==L].copy()
    s = s.assign(operator_id=s.operator_id.astype(str), shift=s['shift'].astype(str))
    rf = rest + ' + C(operator_id) + C(shift)'
    rr = rest + ' + C(shift)'
    yy, X = patsy.dmatrices('defective_units + fail ~ ' + rf, s, return_type='dataframe')
    mf = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
    yy, X2 = patsy.dmatrices('defective_units + fail ~ ' + rr, s, return_type='dataframe')
    mr = sm.GLM(yy, X2, family=sm.families.Binomial()).fit()
    ph = mf.pearson_chi2/mf.df_resid
    k = mf.df_model - mr.df_model
    F = ((mr.deviance-mf.deviance)/k)/ph
    # shift test within line
    rr2 = rest + ' + C(operator_id)'
    yy, X3 = patsy.dmatrices('defective_units + fail ~ ' + rr2, s, return_type='dataframe')
    m3 = sm.GLM(yy, X3, family=sm.families.Binomial()).fit()
    Fs = ((m3.deviance-mf.deviance)/1)/ph
    print(f'{L}: operator F={F:6.2f} p={stats.f.sf(F,k,mf.df_resid):.3g} (k={k})   shift F={Fs:7.2f} p={stats.f.sf(Fs,1,mf.df_resid):.3g}   n={len(s)}')
EOF
python3 oper2.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > c2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
exec(open('final.py').read().split("full, phi = fit")[0])
# spline humidity interacting with supplier
rhs_sp = ('mold_temp + I(mold_temp**2) + cr(humidity_pct, df=5):C(supplier_code) + cycle_time_s + I(cycle_time_s**2)'
          ' + C(supplier_code) + C(shift) + C(operator_id) + C(line) + days_since_clean + L1post + L2post + L3post')
yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs_sp, d, return_type='dataframe', NA_action='drop')
m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
print('spline model dev', round(m.deviance,1), 'pearson/df', round(m.pearson_chi2/m.df_resid,3))
# predicted rate for SP-01 along humidity grid, others at their observed mean-like values
grid = np.arange(5, 71, 1.0)
base = d.copy()
best=None; res=[]
for h in grid:
    s = base[base.supplier_code=='SP-01'].copy()
    s['humidity_pct'] = h
    Xp = patsy.build_design_matrices([X.design_info], s, return_type='dataframe')[0]
    p = m.predict(Xp)
    res.append((h, (p*s.units_produced).sum()/s.units_produced.sum()))
res = pd.DataFrame(res, columns=['h','rate'])
print(res.iloc[::5].round(5).to_string())
print('argmin', res.loc[res.rate.idxmin()].round(5).to_dict())
# quadratic-logit vertex check from linear model without spline
EOF
python3 c2.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > cf.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
exec(open('final.py').read().split("full, phi = fit")[0])
RECIPE = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}   # grade-level recipe (PP-H350 -> 30, PP-H420 -> 36)
rhs = ('mold_temp + I(mold_temp**2) + humidity_pct*C(supplier_code) + I(humidity_pct**2)*C(supplier_code)'
       ' + cycle_time_s + I(cycle_time_s**2) + C(supplier_code) + C(shift) + C(operator_id) + C(line) + days_since_clean + L1post + L2post + L3post')
yy, X = patsy.dmatrices('defective_units + fail ~ ' + rhs, d, return_type='dataframe')
m = sm.GLM(yy, X, family=sm.families.Binomial()).fit()
print('model dev', round(m.deviance,1), 'phi', round(m.pearson_chi2/m.df_resid,3))
def rate_cf(data, mod, info):
    Xp = patsy.build_design_matrices([info], data, return_type='dataframe')[0]
    p = mod.predict(Xp)
    return (p*data.units_produced).sum()/data.units_produced.sum(), p
print('C1: observed-model baseline rate', round(rate_cf(d, m, X.design_info)[0],5), 'actual', round(d.defective_units.sum()/d.units_produced.sum(),5))
for s in ['SP-01','SP-02','SP-03']:
    cf = d.copy(); cf['supplier_code']=s; cf['cycle_time_s']=RECIPE[s]
    r,_ = rate_cf(cf, m, X.design_info)
    print('  supplier', s, round(r,5))
# C3: additional cleanings whenever 14 days passed since last cleaning (per line)
from clean import load_maint
mt = load_maint(); cl = mt[mt.event=='mold_cleaning']
start = pd.Timestamp('2024-12-01'); end = pd.Timestamp('2025-09-30')
days = pd.date_range(start, end, freq='D')
new_days = {}
for L in ['L1','L2','L3','L4']:
    logged = set(cl[cl.line==L].date)
    last = None; table={}
    for t in days:
        if t in logged: last=t
        elif last is None or (t-last).days>=14:
            last=t   # extra cleaning
        table[t]=last
    new_days[L]=table
def days_new(row):
    t=row.date; last=new_days[row.line][t]
    return (t-last).days
d['days_new'] = d.apply(days_new, axis=1)
print('days old mean', round(d.days_since_clean.mean(),3), 'new mean', round(d.days_new.mean(),3), 'max new', d.days_new.max())
cf = d.copy(); cf['days_since_clean']=cf.days_new
base_r = rate_cf(d, m, X.design_info)[0]
new_r = rate_cf(cf, m, X.design_info)[0]
print('C3 model-based: baseline', round(base_r,5), 'with extra cleaning', round(new_r,5))
# full-plant recorded rate uses all batches; apply model to complete cases only -> also ratio approach
ratio = new_r/base_r
print('ratio', round(ratio,5), 'applied to actual A3 rate', round(ratio*0.0550318,5))
EOF
python3 cf.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && cat > cf3.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy, warnings
warnings.filterwarnings('ignore')
exec(open('cf.py').read().split("print('model dev'")[0])
# days as spline and as bins
for label, dayterm in [('linear', 'days_since_clean'), ('bins', 'C(dbin)'), ('spline', 'cr(days_since_clean, df=4)')]:
    dd = d.copy()
    dd['dbin'] = pd.cut(dd.days_since_clean, [-1,4,8,12,16,40], labels=False).astype(str)
    rhs2 = rhs.replace('days_since_clean', dayterm)
    yy, X2 = patsy.dmatrices('defective_units + fail ~ ' + rhs2, dd, return_type='dataframe')
    mm = sm.GLM(yy, X2, family=sm.families.Binomial()).fit()
    base = (mm.predict(X2)*dd.units_produced).sum()/dd.units_produced.sum()
    cf = dd.copy(); cf['days_since_clean']=cf.days_new
    if label=='bins': cf['dbin']=pd.cut(cf.days_since_clean,[-1,4,8,12,16,40],labels=False).astype(str)
    Xc = patsy.build_design_matrices([X2.design_info], cf, return_type='dataframe')[0]
    new = (mm.predict(Xc)*cf.units_produced).sum()/cf.units_produced.sum()
    print(f'{label:8s} dev={mm.deviance:9.1f} baseline={base:.5f} with_cleaning={new:.5f}')
EOF
python3 cf3.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 - <<'EOF'
import re
src = open('cf.py').read()
block = src.split("# C3: additional cleanings")[1].split("print('days old mean'")[0]
pre = open('cf3.py').read().split("# days as spline")[0]
body = open('cf3.py').read().split("# days as spline and as bins")[1]
code = pre + "# C3 block" + block + "\n" + body
open('cf3_full.py','w').write(code)
EOF
python3 cf3_full.py

cd "/tmp/claude-0/-tmp-edabench-claude-j9ytxn-t/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad" && python3 - <<'EOF'
import warnings; warnings.filterwarnings('ignore')
import numpy as np, pandas as pd, statsmodels.api as sm, patsy
exec(open('final.py').read().split("full, phi = fit")[0])
full, phi = fit(CORE + REG, 'full')
p = full.params
b1 = p['humidity_pct']; b2 = p['I(humidity_pct ** 2)']
print('SP-01 humidity linear', b1, 'quad', b2, 'vertex', -b1/(2*b2))
# Alpha curve from full quadratic, grid
h = np.arange(0.5, 72, 0.01)
print('grid argmin (SP-01, quadratic logit)', h[np.argmin(b1*h + b2*h**2)])
from clean import clean
raw, df0 = clean()
print('A2 check: humidity missing/invalid in unique batches =', df0.humidity_pct.isna().sum(), ' min valid humidity', df0.humidity_pct.min())
print('A4 check median mold C', round(df0.mold_temp.median(),3), 'A3', df0.defective_units.sum()/df0.units_produced.sum())
EOF
