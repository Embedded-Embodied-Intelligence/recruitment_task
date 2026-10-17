ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

mkdir -p $TMPDIR/an && cat > $TMPDIR/an/profile.py <<'EOF'
import pandas as pd
pd.set_option('display.width', 200)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape)
print(b.columns.tolist())
for c in b.columns:
    vc = b[c].value_counts()
    print(f"\n## {c}: nunique={b[c].nunique()}, blanks={(b[c].str.strip()=='').sum()}")
    if b[c].nunique() < 40:
        print(vc.to_string())
    else:
        print(vc.head(8).to_string())
        print('...')
        print(vc.tail(8).to_string())
print(open('suppliers.csv').read())
m = pd.read_csv('maintenance.csv', dtype=str, keep_default_na=False)
print(m.shape); print(m.event.value_counts()); print(m.line.value_counts()); print(m.note.value_counts())
EOF
cd /tmp/edabench_claude_cnj0o25w && python3 $TMPDIR/an/profile.py

cat > $TMPDIR/an/dups.py <<'EOF'
import pandas as pd
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 30)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
d = b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print(len(d), d.batch_id.nunique())
print(d.head(12).to_string())
# are duplicates exact?
print('exact dup rows:', b.duplicated().sum())
# which fields differ within dup groups
diffcols = {c: (d.groupby('batch_id')[c].nunique()>1).sum() for c in b.columns}
print(diffcols)
EOF
cd /tmp/edabench_claude_cnj0o25w && python3 $TMPDIR/an/dups.py

cat > $TMPDIR/an/numeric.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 30); pd.set_option('display.max_rows', 200)
b = pd.read_csv('batches.csv').drop_duplicates()
print(b.shape, b.batch_id.nunique())
print(b.describe().T.to_string())
print('humidity -1:', (b.humidity_pct==-1).sum(), 'NaN:', b.humidity_pct.isna().sum())
print('mold_temp==0:', (b.mold_temp==0).sum(), 'NaN', b.mold_temp.isna().sum())
print('defect>units', (b.defective_units>b.units_produced).sum())
print(b.loc[b.mold_temp>300, ['production_date','line','mold_temp']].assign(d=lambda x:x.production_date).groupby('line').size())
hi = b[b.mold_temp>300]
print(hi.production_date.min(), hi.production_date.max(), hi.line.value_counts().to_dict())
print(hi[['production_date','line','mold_temp']].sort_values('production_date').head(20).to_string())
print(hi.groupby('line').production_date.agg(['min','max','count']))
print(b[b.mold_temp>300].mold_temp.describe())
print(b[(b.mold_temp>0)&(b.mold_temp<=300)].mold_temp.describe())
EOF
cd /tmp/edabench_claude_cnj0o25w && python3 $TMPDIR/an/numeric.py

cat > $TMPDIR/an/maint.py <<'EOF'
import pandas as pd
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200)
b = pd.read_csv('batches.csv').drop_duplicates()
print(b.groupby('line').mold_temp.agg(['count','min','median','max']))
print(b[b.line=='L3'].mold_temp.gt(300).mean(), (b[b.line=='L3'].mold_temp==0).sum())
m = pd.read_csv('maintenance.csv')
print(m.to_string())
EOF
cd /tmp/edabench_claude_cnj0o25w && python3 $TMPDIR/an/maint.py

cat > $TMPDIR/an/l1.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = pd.read_csv('batches.csv').drop_duplicates()
b['date'] = pd.to_datetime(b.production_date)
l1 = b[(b.line=='L1') & (b.mold_temp>0)].copy()
l1['m'] = l1.date.dt.to_period('M')
print(l1.groupby('m').mold_temp.agg(['count','median','mean']).to_string())
# compare other lines' mold temp by month for baseline
oth = b[(b.line.isin(['L2','L4'])) & (b.mold_temp>0)].copy()
oth['m']=oth.date.dt.to_period('M')
print(oth.groupby(['m','line']).mold_temp.median().unstack().to_string())
# daily window around 2025-04-14 and 2025-09-22
w = l1[(l1.date>='2025-04-01')&(l1.date<='2025-04-30')].groupby('production_date').mold_temp.mean()
print(w.round(1).to_string())
EOF
cd /tmp/edabench_claude_cnj0o25w && python3 $TMPDIR/an/l1.py

cat > $TMPDIR/an/l1step.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = pd.read_csv('batches.csv').drop_duplicates()
b['date'] = pd.to_datetime(b.production_date)
v = b[(b.mold_temp>0)&(b.line!='L3')]
daily = v.groupby(['date','line']).mold_temp.mean().unstack()
daily['gap'] = daily['L1'] - daily[['L2','L4']].mean(axis=1)
g = daily['gap'].dropna()
# best single changepoint on mean of gap
best=None
for i in range(10,len(g)-10):
    a,bb = g.iloc[:i], g.iloc[i:]
    sse = ((a-a.mean())**2).sum()+((bb-bb.mean())**2).sum()
    if best is None or sse<best[0]: best=(sse,g.index[i],a.mean(),bb.mean())
print('L1 gap changepoint:', best[1].date(), 'mean before %.2f after %.2f'%(best[2],best[3]))
for lo,hi in [('2025-01-01','2025-04-13'),('2025-04-14','2025-09-21'),('2025-09-22','2025-09-30')]:
    s=g[lo:hi]; print(lo,hi,len(s),round(s.mean(),2),round(s.std(),2))
print(g.resample('W').mean().round(2).to_string())
EOF
cd /tmp/edabench_claude_cnj0o25w && python3 $TMPDIR/an/l1step.py

cat > $TMPDIR/an/clean.py <<'EOF'
import pandas as pd, numpy as np

def load():
    raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
    b = raw.drop_duplicates().copy()          # 60 exact duplicate rows
    b['production_date'] = pd.to_datetime(b.production_date)
    # shift: map variants to Day / Night
    s = b['shift'].str.strip().str.lower()
    b['shift'] = np.where(s.isin(['d','day']), 'Day', np.where(s.isin(['n','night']), 'Night', None))
    # supplier code: trim + upper
    b['supplier_code'] = b.supplier_code.str.strip().str.upper()
    for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s',
              'units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        b[c] = pd.to_numeric(b[c].replace('', np.nan))
    # humidity: -1.0 sentinel and blanks are invalid
    b['humidity_valid'] = b.humidity_pct.notna() & (b.humidity_pct >= 0)
    b.loc[~b.humidity_valid, 'humidity_pct'] = np.nan
    # mold temp: 0.0 = missing; L3 logged in Fahrenheit; L1 sensor reads +8.0 C from replacement on 2025-04-14
    b['mold_temp_c'] = b.mold_temp.where(b.mold_temp > 0)
    f = (b.line == 'L3') & b.mold_temp_c.notna()
    b.loc[f, 'mold_temp_c'] = (b.loc[f, 'mold_temp_c'] - 32) * 5 / 9
    l1 = (b.line == 'L1') & (b.production_date >= '2025-04-14') & b.mold_temp_c.notna()
    b.loc[l1, 'mold_temp_c'] = b.loc[l1, 'mold_temp_c'] - 8.0
    b['defect_rate'] = b.defective_units / b.units_produced
    return b

def maint():
    m = pd.read_csv('maintenance.csv', parse_dates=['date'])
    return m
EOF
cat > $TMPDIR/an/checkclean.py <<'EOF'
import sys; sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-cnj0o25w/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/an')
EOF
cd /tmp/edabench_claude_cnj0o25w && cat > $TMPDIR/an/run1.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd
pd.set_option('display.width', 250)
b = load()
print('batches', b.batch_id.nunique(), len(b))
print('shift', b['shift'].value_counts(dropna=False).to_dict())
print('supplier', b.supplier_code.value_counts().to_dict())
print('humidity invalid/missing', (~b.humidity_valid).sum())
print('mold valid', b.mold_temp_c.notna().sum(), 'median C', round(b.mold_temp_c.median(),4))
print('mold C range by line'); print(b.groupby('line').mold_temp_c.agg(['min','median','max']).round(2))
print('overall defect rate', b.defective_units.sum()/b.units_produced.sum())
EOF
python3 $TMPDIR/an/run1.py

cat > $TMPDIR/an/explore.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = load()
b = b.rename(columns={'supplier_code':'sup'})
num = ['machine_age_years','ambient_temp_c','mold_temp_c','humidity_pct','cycle_time_s','units_produced','qc_inspection_min','rework_cost_eur','defective_units']
print(b[num+['defect_rate']].corr(method='spearman')['defect_rate'].round(3).to_string())
for c in ['line','shift','operator_id','sup']:
    g = b.groupby(c).agg(n=('batch_id','size'), dr=('defective_units','sum'), u=('units_produced','sum'))
    g['rate']=g.dr/g.u
    print(g.round(4).to_string())
EOF
python3 $TMPDIR/an/explore.py

python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)" ; cat > $TMPDIR/an/glm1.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
pd.set_option('display.width', 250)
b = load().rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
b['def_rate']=b.defective_units/b.units_produced
b['ops']=b.operator_id
b['rw_per_def']=b.rework_cost_eur/b.defective_units
print('rework per defect', b.rw_per_def.describe().round(3).to_dict())
print(b[['qc_inspection_min','defective_units','units_produced','rework_cost_eur']].corr().round(3))
# leakage check: qc time vs defect rate given other stuff
d = b.dropna(subset=['humidity_pct','mold'])
m = smf.glm('defective_units + I(units_produced-defective_units) ~ mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(ops) + C(shift) + C(line) + C(sup)',
            data=d, family=sm.families.Binomial()).fit()
print(m.summary())
EOF
python3 $TMPDIR/an/glm1.py 2>&1 | head -150

cat > $TMPDIR/an/glm2.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = load().rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
print(pd.crosstab(b.operator_id, b.line).to_string())
print(pd.crosstab(b.sup, b.line))
d = b.dropna(subset=['humidity_pct','mold']).copy()
d['ok'] = d.units_produced - d.defective_units
m = smf.glm('defective_units + ok ~ mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(sup)',
            data=d, family=sm.families.Binomial())
# formula-style two-column response: build manually
X = smf.glm('ok ~ mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(sup)', data=d, family=sm.families.Binomial()).data
y = np.column_stack([d.defective_units.values, d.ok.values])
res = sm.GLM(y, X.exog, family=sm.families.Binomial(), exog_names=None).fit() if False else None
import patsy
ex = patsy.dmatrix('mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(sup)', d, return_type='dataframe')
res = sm.GLM(y, ex, family=sm.families.Binomial()).fit()
print(res.summary())
EOF
python3 $TMPDIR/an/glm2.py 2>&1 | head -200

cat > $TMPDIR/an/leak.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd, numpy as np, statsmodels.formula.api as smf
pd.set_option('display.width', 250)
b = load().rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
b['rate']=b.defective_units/b.units_produced
b['qc']=b.qc_inspection_min
# Does qc time / rework cost track the outcome beyond the process inputs?
base = smf.ols('qc ~ C(line)+C(shift)+C(sup)+mold+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c+np.log(units_produced)', data=b.dropna(subset=['mold','humidity_pct'])).fit()
print('qc R2 without defects', round(base.rsquared,3))
full = smf.ols('qc ~ defective_units + C(line)+C(shift)+C(sup)+mold+humidity_pct+cycle_time_s+machine_age_years+ambient_temp_c+np.log(units_produced)', data=b.dropna(subset=['mold','humidity_pct'])).fit()
print('qc R2 with defects', round(full.rsquared,3), 'coef defects', round(full.params['defective_units'],4), 't', round(full.tvalues['defective_units'],1))
rw = smf.ols('rework_cost_eur ~ defective_units', data=b).fit(); print('rework~defects R2', round(rw.rsquared,4))
rw2 = smf.ols('rework_cost_eur ~ defective_units + units_produced + mold + cycle_time_s', data=b.dropna(subset=['mold'])).fit(); print('rework extra R2', round(rw2.rsquared,4), round(rw2.params['units_produced'],4))
EOF
python3 $TMPDIR/an/leak.py

cat > $TMPDIR/an/fit.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = load().rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
d = b.dropna(subset=['humidity_pct','mold']).copy()
d['ok'] = d.units_produced - d.defective_units
def fit(rhs, data=d):
    import patsy
    y = np.column_stack([data.defective_units.values, data.ok.values])
    X = patsy.dmatrix(rhs, data, return_type='dataframe')
    r = sm.GLM(y, X, family=sm.families.Binomial()).fit(scale='X2')
    return r
base = 'mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup)'
r_line = fit(base + ' + C(line)')
r_op = fit(base + ' + C(operator_id)')
r_none = fit(base)
print('line model dev', round(r_line.deviance,1), 'df', r_line.df_resid, 'scale', round(r_line.scale,2))
print('operator model dev', round(r_op.deviance,1), 'df', r_op.df_resid)
F = ((r_line.deviance-r_op.deviance)/(r_line.df_resid-r_op.df_resid))/(r_op.deviance/r_op.df_resid)
print('F operator-within-line', round(F,2), stats.f.sf(F, r_line.df_resid-r_op.df_resid, r_op.df_resid))
print(r_line.summary())
EOF
python3 $TMPDIR/an/fit.py

cat > $TMPDIR/an/fit2.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = load().rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
d = b.dropna(subset=['humidity_pct','mold']).copy()
d['rate'] = d.defective_units/d.units_produced
def fit(rhs, data=d):
    X = patsy.dmatrix(rhs, data, return_type='dataframe')
    return sm.GLM(data.rate.values, X, family=sm.families.Binomial(), var_weights=data.units_produced.values).fit(scale='X2')
def ftest(m0, m1):
    F = ((m0.deviance-m1.deviance)/(m0.df_resid-m1.df_resid))/(m1.deviance/m1.df_resid)
    return round(F,2), stats.f.sf(F, m0.df_resid-m1.df_resid, m1.df_resid)
base = 'mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup)'
m = fit(base + ' + C(line)')
print('scale', round(m.scale,3))
print(m.summary())
EOF
python3 $TMPDIR/an/fit2.py

cat > $TMPDIR/an/clean_age.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load, maint
import pandas as pd, numpy as np
def add_age(b):
    m = maint(); cl = m[m.event=='mold_cleaning']
    b = b.copy(); b['days_since_clean'] = np.nan
    for line, g in b.groupby('line'):
        cdates = np.sort(cl[cl.line==line].date.values)
        idx = np.searchsorted(cdates, g.production_date.values, side='right') - 1
        assert (idx>=0).all()
        last = cdates[idx]
        b.loc[g.index,'days_since_clean'] = (g.production_date.values - last).astype('timedelta64[D]').astype(int)
    return b
if __name__ == '__main__':
    pd.set_option('display.width', 250)
    b = add_age(load())
    print(b.days_since_clean.describe())
    print(b.groupby('line').days_since_clean.agg(['min','median','max']))
    print(b.days_since_clean.value_counts().sort_index().to_string())
EOF
python3 $TMPDIR/an/clean_age.py

cat > $TMPDIR/an/fit3.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
from clean_age import add_age
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
d = b.dropna(subset=['humidity_pct','mold']).copy()
d['rate'] = d.defective_units/d.units_produced
d['age_gt14'] = (d.days_since_clean>=14).astype(int)
def fit(rhs, data=d):
    X = patsy.dmatrix(rhs, data, return_type='dataframe')
    return sm.GLM(data.rate.values, X, family=sm.families.Binomial(), var_weights=data.units_produced.values).fit(scale='X2')
base = 'mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup) + C(line)'
m0 = fit(base); m1 = fit(base+' + days_since_clean'); m2 = fit(base+' + C(days_since_clean)')
for m in [m0,m1]:
    print(m.summary().tables[1])
print('scale m0 %.2f m1 %.2f' % (m0.scale, m1.scale), 'dev', round(m0.deviance,1), round(m1.deviance,1))
print('dummies-vs-linear dev', round(m2.deviance,1), 'df', m2.df_resid)
print('days coef', round(m1.params['days_since_clean'],5))
print('gt14 check:'); m3 = fit(base+' + age_gt14'); print(m3.params['age_gt14'], m3.bse['age_gt14'], m3.deviance)
print('dsc coef tables:');print(m2.params.filter(like='days').round(3).to_string())
EOF
python3 $TMPDIR/an/fit3.py

cat > $TMPDIR/an/regime.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
from clean_age import add_age
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 400)
b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
d = b.dropna(subset=['humidity_pct','mold']).copy()
d['rate'] = d.defective_units/d.units_produced
rhs = 'mold + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(sup) + C(line) + days_since_clean'
X = patsy.dmatrix(rhs, d, return_type='dataframe')
m = sm.GLM(d.rate.values, X, family=sm.families.Binomial(), var_weights=d.units_produced.values).fit(scale='X2')
d['pred'] = m.predict(X)
d['resid_def'] = d.defective_units - d.pred*d.units_produced   # observed - expected defectives
d['resid_std'] = d.resid_def/np.sqrt(d.pred*(1-d.pred)*d.units_produced)
d.to_pickle(os.path.join(os.environ['TMPDIR'],'an','d.pkl'))
# monthly standardized residual mean by line
d['m'] = d.production_date.dt.to_period('M')
print(d.groupby(['m','line']).resid_std.mean().unstack().round(2).to_string())
# changepoint search per line on cumulative residual trend (standardized)
for line, g in d.groupby('line'):
    g = g.sort_values('production_date')
    z = g.resid_std.values
    best=None
    for i in range(30,len(z)-30):
        a,c = z[:i], z[i:]
        # two-sample t-like stat
        t = (c.mean()-a.mean())/np.sqrt(a.var()/len(a)+c.var()/len(c))
        if best is None or abs(t)>abs(best[0]): best=(t,g.production_date.values[i],a.mean(),c.mean())
    print(line,'max |t| changepoint', round(best[0],2), str(best[1])[:10], round(best[2],3), round(best[3],3))
EOF
python3 $TMPDIR/an/regime.py

cat > $TMPDIR/an/l2date.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 400)
d = pd.read_pickle(os.path.join(os.environ['TMPDIR'],'an','d.pkl'))
g = d[d.line=='L2'].sort_values('production_date')
# scan split date: best split by t-stat on standardized residuals, min 20 batches each side
best=[]
dates = sorted(g.production_date.unique())
for dt in dates:
    a = g[g.production_date<dt].resid_std; c = g[g.production_date>=dt].resid_std
    if len(a)<20 or len(c)<20: continue
    t = (c.mean()-a.mean())/np.sqrt(a.var()/len(a)+c.var()/len(c))
    best.append((abs(t), t, pd.Timestamp(dt).date(), len(a), len(c), round(a.mean(),3), round(c.mean(),3)))
best.sort(reverse=True)
for r in best[:8]: print(r)
w = g[(g.production_date>='2025-06-01')&(g.production_date<='2025-06-30')]
print(w.groupby('production_date').agg(n=('batch_id','size'), resid=('resid_std','mean'), dr=('defect_rate','mean')).round(3).to_string())
EOF
python3 $TMPDIR/an/l2date.py

cat > $TMPDIR/an/refit.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
import clean
from clean import load
from clean_age import add_age
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)

def prep(l1_fix=True, l3_fix=True):
    b = add_age(load()).rename(columns={'supplier_code':'sup'})
    if not l1_fix or not l3_fix:
        raw = b.mold_temp.where(b.mold_temp>0)
        m = raw.copy()
        if l3_fix: m = m.where(b.line!='L3', (raw-32)*5/9)
        if l1_fix: m = m.where(~((b.line=='L1')&(b.production_date>='2025-04-14')), m-8.0)
        b['mold_temp_c'] = m
    b = b.rename(columns={'mold_temp_c':'mold'})
    b['regime_L2'] = ((b.line=='L2')&(b.production_date>='2025-06-15')).astype(int)
    d = b.dropna(subset=['humidity_pct','mold']).copy()
    d['rate'] = d.defective_units/d.units_produced
    return d
def fit(rhs, d):
    X = patsy.dmatrix(rhs, d, return_type='dataframe')
    return sm.GLM(d.rate.values, X, family=sm.families.Binomial(), var_weights=d.units_produced.values).fit(scale='X2')
if __name__ == '__main__':
    base = 'mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
    d = prep()
    m = fit(base, d); print(m.summary().tables[1]); print('scale', round(m.scale,2), 'dev', round(m.deviance,1))
    for nm, kw in [('no L1 fix', dict(l1_fix=False)), ('no L3 fix', dict(l3_fix=False))]:
        dd = prep(**kw); mm = fit(base, dd)
        print(nm, 'dev', round(mm.deviance,1), 'mold coef', round(mm.params['mold'],4), 'n', len(dd))
EOF
python3 $TMPDIR/an/refit.py

cat > $TMPDIR/an/c2.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from refit import prep, fit
import pandas as pd, numpy as np
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
d = prep()
base = 'mold + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
# operator within line
m0 = fit(base, d); m1 = fit(base.replace('C(line)','C(operator_id)'), d)
F = ((m0.deviance-m1.deviance)/(m0.df_resid-m1.df_resid))/(m1.deviance/m1.df_resid)
print('operator F (vs line)', round(F,3), 'p', round(stats.f.sf(F, m0.df_resid-m1.df_resid, m1.df_resid),4), 'df diff', m0.df_resid-m1.df_resid)
# humidity shape
for nm, rhs in [('linear', base),
                ('quad', base+' + I(humidity_pct**2)'),
                ('lin+sup-int', base+' + humidity_pct:C(sup)'),
                ('quad+sup-int', base+' + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)')]:
    mm = fit(rhs, d); print(nm, 'dev', round(mm.deviance,1), 'df', mm.df_resid, 'scale', round(mm.scale,2))
# binned humidity curve by supplier (observed residual shape)
d['hbin'] = pd.cut(d.humidity_pct, [0,10,15,20,25,30,35,40,45,50,60,80])
print(d.groupby(['sup','hbin'], observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).unstack(0).round(4).to_string())
EOF
python3 $TMPDIR/an/c2.py

cat > $TMPDIR/an/final_spec.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from refit import prep, fit
import pandas as pd, numpy as np
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
d = prep()
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
core = f'mold + {H} + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
m = fit(core, d)
print(m.summary().tables[1]); print('scale', round(m.scale,2), 'dev', round(m.deviance,1), 'df', m.df_resid)
# curvature checks for other continuous vars
for extra in ['I(mold**2)','I(cycle_time_s**2)','I(ambient_temp_c**2)','I(machine_age_years**2)','I(days_since_clean**2)','np.log(units_produced)','I(days_since_clean>=14)']:
    mm = fit(core+' + '+extra, d)
    print(extra, 'dev drop', round(m.deviance-mm.deviance,1), 'coef', round(mm.params[extra],5), 'p', round(mm.pvalues[extra],4))
# operator within line, under this spec
m1 = fit(core.replace('C(line)','C(operator_id)'), d)
F = ((m.deviance-m1.deviance)/(m.df_resid-m1.df_resid))/(m1.deviance/m1.df_resid)
print('operator F', round(F,3), 'p', round(stats.f.sf(F, m.df_resid-m1.df_resid, m1.df_resid),4))
# drop each candidate in turn
for v in ['ambient_temp_c','machine_age_years','cycle_time_s','mold','shift']:
    rhs = core
    if v=='shift': rhs = rhs.replace('C(shift) + ','')
    else: rhs = rhs.replace(f'{v} + ','')
    mm = fit(rhs, d)
    F = ((mm.deviance-m.deviance)/(mm.df_resid-m.df_resid))/(m.deviance/m.df_resid)
    print('drop', v, 'F', round(F,2), 'p', round(stats.f.sf(F, mm.df_resid-m.df_resid, m.df_resid),4))
EOF
python3 $TMPDIR/an/final_spec.py

cat > $TMPDIR/an/final_spec.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from refit import prep, fit
import pandas as pd, numpy as np
from scipy import stats
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
d = prep()
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
core = f'mold + {H} + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
m = fit(core, d)
def coef(mm, frag): return {k: round(v,5) for k,v in mm.params.items() if frag in k}
for extra in ['I(mold ** 2)','I(cycle_time_s ** 2)','I(ambient_temp_c ** 2)','I(machine_age_years ** 2)','I(days_since_clean ** 2)']:
    mm = fit(core+' + '+extra, d)
    print(extra, 'dev drop', round(m.deviance-mm.deviance,1), 'coef', coef(mm, extra[:12]))
m1 = fit(core.replace('C(line)','C(operator_id)'), d)
F = ((m.deviance-m1.deviance)/(m.df_resid-m1.df_resid))/(m1.deviance/m1.df_resid)
print('operator-within-line F', round(F,3), 'p', round(stats.f.sf(F, m.df_resid-m1.df_resid, m1.df_resid),4))
for v in ['ambient_temp_c','machine_age_years','cycle_time_s','mold','shift']:
    rhs = core.replace('C(shift) + ','') if v=='shift' else core.replace(f' + {v}', '').replace(f'{v} + ','')
    mm = fit(rhs, d)
    F = ((mm.deviance-m.deviance)/(mm.df_resid-m.df_resid))/(m.deviance/m.df_resid)
    print('drop', v, 'F', round(F,2), 'p', round(stats.f.sf(F, mm.df_resid-m.df_resid, m.df_resid),4))
EOF
python3 $TMPDIR/an/final_spec.py

cat > $TMPDIR/an/ops.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from refit import prep, fit
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
d = prep()
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
core = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + days_since_clean + regime_L2'
m1 = fit(core + ' + C(operator_id)', d)
p = m1.params.filter(like='operator')
se = m1.bse.filter(like='operator')
# operator 'OP-01' is absorbed in intercept? use line-level comparison: operators are nested in line
ops = d.groupby('operator_id').line.first()
t = pd.DataFrame({'line':ops, 'coef':p.rename(lambda s: s.split('[T.')[1].rstrip(']')), 'se':se.rename(lambda s: s.split('[T.')[1].rstrip(']'))})
print(t.round(3).to_string())
# compare with the line mean: average of op coefs within line should be ~0 for a clean test
print('mean coef within line (incl ref=0):')
for ln, g in t.groupby('line'): print(ln, round(g.coef.mean(),3))
EOF
python3 $TMPDIR/an/ops.py

cat > $TMPDIR/an/perm.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from refit import prep, fit
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
d = prep().copy()
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
core = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + days_since_clean + regime_L2'
m0 = fit(core + ' + C(line)', d)
m1 = fit(core + ' + C(operator_id)', d)
obs = m0.deviance - m1.deviance
rng = np.random.default_rng(0)
cnt=0; B=200; stats_=[]
for i in range(B):
    dd = d.copy()
    dd['operator_id'] = dd.groupby('line').operator_id.transform(lambda s: rng.permutation(s.values))
    a = fit(core + ' + C(operator_id)', dd)
    stats_.append(m0.deviance - a.deviance)
stats_ = np.array(stats_)
print('observed drop', round(obs,1), 'perm mean', round(stats_.mean(),1), 'perm 95%', round(np.quantile(stats_,0.95),1))
print('perm p', (np.sum(stats_>=obs)+1)/(B+1))
EOF
timeout 600000 python3 $TMPDIR/an/perm.py

cat > $TMPDIR/an/sup_int.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from refit import prep, fit
import pandas as pd, numpy as np, statsmodels.formula.api as smf
from scipy import stats
pd.set_option('display.width', 250)
d = prep().copy()
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
core = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
m0 = fit(core, d)
for extra in ['C(sup):C(line)','C(sup):mold','C(sup):cycle_time_s','C(sup):C(shift)','C(sup):days_since_clean']:
    m1 = fit(core+' + '+extra, d)
    F = ((m0.deviance-m1.deviance)/(m0.df_resid-m1.df_resid))/(m1.deviance/m1.df_resid)
    print(extra, 'F', round(F,2), 'p', round(stats.f.sf(F, m0.df_resid-m1.df_resid, m1.df_resid),4))
# humidity independence from other covariates (all 3000 batches, humidity missing excluded)
b = prep().copy()
full = pd.read_csv('batches.csv').drop_duplicates()
hm = full.humidity_pct.where(full.humidity_pct>=0)
print('humidity by line', full.assign(h=hm).groupby('line').h.agg(['mean','std']).round(2).to_dict())
print('humidity by shift', full.assign(h=hm).groupby('shift').h.agg(['mean','std']).round(2).to_dict())
print('humidity by sup', full.assign(h=hm).groupby(full.supplier_code.str.upper().str.strip()).h.agg(['mean','std']).round(2).to_dict())
print('humidity ~ ambient corr', hm.corr(full.ambient_temp_c).round(3))
print('humidity ~ month', full.assign(h=hm, m=full.production_date.str[5:7]).groupby('m').h.mean().round(1).to_dict())
EOF
python3 $TMPDIR/an/sup_int.py

cat > $TMPDIR/an/final.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load, maint
from clean_age import add_age
from refit import fit
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
pd.set_option('display.width', 250)

# ---------- full cleaned frame (all 3000 batches) ----------
b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
b['regime_L2'] = ((b.line=='L2')&(b.production_date>='2025-06-15')).astype(int)
b['rate'] = b.defective_units/b.units_produced
d = b.dropna(subset=['humidity_pct','mold']).copy()          # complete cases for fitting
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
rhs = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
m = fit(rhs, d)
print('scale', round(m.scale,3), 'n', len(d))
print(m.params.round(5).to_string())

# ---------- expected-rate function on arbitrary frame ----------
hum_pool = b.humidity_pct.dropna().values
def expected_defects(frame, sup_override=None, days_override=None):
    """Expected defect count per batch; humidity missing -> average over observed humidity pool."""
    f = frame.copy()
    if sup_override is not None: f['sup'] = sup_override
    if days_override is not None: f['days_since_clean'] = days_override
    out = np.zeros(len(f))
    known = f.humidity_pct.notna().values
    # known humidity
    X = patsy.build_design_matrices([m.model.data.design_info], f[known], return_type='dataframe')[0]
    p = m.predict(X)
    out[known] = p * f.units_produced.values[known]
    # unknown humidity: mean prediction over observed humidity pool
    unk = ~known
    if unk.any():
        acc = np.zeros(unk.sum())
        g = f[unk].copy()
        for h in hum_pool:
            g['humidity_pct'] = h
            Xg = patsy.build_design_matrices([m.model.data.design_info], g, return_type='dataframe')[0]
            acc += m.predict(Xg)
        out[unk] = acc/len(hum_pool) * g.units_produced.values
    return out

units = b.units_produced.values
act = expected_defects(b)
print('calibration: observed rate %.5f  model-expected rate %.5f' % (b.defective_units.sum()/units.sum(), act.sum()/units.sum()))

# ---------- C1: single supplier ----------
res = {}
for code, name in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    e = expected_defects(b, sup_override=code)
    res[name] = e.sum()/units.sum()
print('C1 supplier-counterfactual rates:', {k: round(v,5) for k,v in res.items()})

# ---------- C2: Alpha humidity optimum ----------
bh = m.params['humidity_pct']; bh2 = m.params['I(humidity_pct ** 2)']
h_star = -bh/(2*bh2)
print('C2 Alpha optimum humidity', round(h_star,3), 'observed range', round(hum_pool.min(),2), round(hum_pool.max(),2))
grid = np.linspace(hum_pool.min(), hum_pool.max(), 7301)
logit = bh*grid + bh2*grid**2
print('grid argmin', round(grid[np.argmin(logit)],3))

# ---------- C3: cleaning every 14 days ----------
cl = maint(); cl = cl[cl.event=='mold_cleaning']
days_cf = pd.Series(np.nan, index=b.index)
for line in ['L1','L2','L3','L4']:
    actual = set(pd.to_datetime(cl[cl.line==line].date))
    cal = pd.date_range('2024-12-01','2025-09-30')
    last = max(x for x in actual if x < pd.Timestamp('2025-01-01'))
    dayrec = {}
    for dt in cal:
        if dt in actual or (dt-last).days >= 14:
            last = dt
        dayrec[dt] = (dt-last).days
    mask = b.line==line
    days_cf[mask] = b.loc[mask,'production_date'].map(dayrec).values
b['days_cf'] = days_cf
print('days_cf max', b.days_cf.max(), 'mean actual', round(b.days_since_clean.mean(),3), 'mean cf', round(b.days_cf.mean(),3))
e_cf = expected_defects(b, days_override=b.days_cf.values)
print('C3 rate with 14-day cleaning (linear days):', round(e_cf.sum()/units.sum(), 6))
EOF
python3 $TMPDIR/an/final.py

python3 - <<'EOF'
import re,os
p = os.path.join(os.environ['TMPDIR'],'an','final.py')
s = open(p).read()
s = s.replace("m = fit(rhs, d)\n", "m = fit(rhs, d)\nDI = patsy.dmatrix(rhs, d, return_type='dataframe').design_info\n")
s = s.replace("[m.model.data.design_info]", "[DI]")
open(p,'w').write(s)
print(s.count('DI'))
EOF
python3 $TMPDIR/an/final.py 2>&1 | tail -20

cat > $TMPDIR/an/final.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load, maint
from clean_age import add_age
from refit import fit
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
pd.set_option('display.width', 250)

b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
b['regime_L2'] = ((b.line=='L2')&(b.production_date>='2025-06-15')).astype(int)
b['rate'] = b.defective_units/b.units_produced
d = b.dropna(subset=['humidity_pct','mold']).copy()
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
rhs = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
m = fit(rhs, d)
DI = patsy.dmatrix(rhs, d, return_type='dataframe').design_info
hum_pool = b.humidity_pct.dropna().values
mold_pool = {ln: g.mold.dropna().values for ln, g in b.groupby('line')}
rng = np.random.default_rng(42)
K = 400

def expected_defects(frame):
    """Expected defectives per batch. Missing humidity/mold are integrated out by Monte Carlo
    draws from the observed humidity pool / same-line observed mold values (independence assumed)."""
    f = frame.reset_index(drop=True)
    n = len(f)
    miss_h = f.humidity_pct.isna().values; miss_m = f.mold.isna().values
    U = np.where(miss_h | miss_m)[0]
    ok = np.setdiff1d(np.arange(n), U)
    out = np.zeros(n)
    def pred(g):
        X = patsy.build_design_matrices([DI], g, return_type='dataframe')[0]
        return m.predict(X)
    out[ok] = pred(f.iloc[ok]) * f.units_produced.values[ok]
    if len(U):
        rep = f.iloc[np.repeat(U, K)].copy()
        hh = rng.choice(hum_pool, size=len(rep))
        rep['humidity_pct'] = np.where(rep.humidity_pct.isna(), hh, rep.humidity_pct)
        mm = np.empty(len(rep))
        for ln in rep.line.unique():
            idx = (rep.line==ln).values
            mm[idx] = rng.choice(mold_pool[ln], size=idx.sum())
        rep['mold'] = np.where(rep.mold.isna(), mm, rep.mold)
        p = pred(rep) * rep.units_produced.values
        out[U] = p.reshape(len(U), K).mean(axis=1)
    return out

units = b.units_produced.values
print('scale', round(m.scale,3), 'n fit', len(d))
act = expected_defects(b)
print('calibration: observed %.5f | model expected %.5f' % (b.defective_units.sum()/units.sum(), act.sum()/units.sum()))

# C1
res = {}
for code, name in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    bb = b.copy(); bb['sup'] = code
    res[name] = expected_defects(bb).sum()/units.sum()
print('C1 rates by supplier:', {k: round(v,6) for k,v in res.items()})

# C2
bh = m.params['humidity_pct']; bh2 = m.params['I(humidity_pct ** 2)']
print('C2 Alpha optimum humidity: %.3f ; observed range %.2f-%.2f' % (-bh/(2*bh2), hum_pool.min(), hum_pool.max()))

# C3
cl = maint(); cl = cl[cl.event=='mold_cleaning']
days_cf = pd.Series(np.nan, index=b.index)
for line in ['L1','L2','L3','L4']:
    actual = set(pd.to_datetime(cl[cl.line==line].date))
    last = max(x for x in actual if x < pd.Timestamp('2025-01-01'))
    dayrec = {}
    for dt in pd.date_range('2025-01-01','2025-09-30'):
        if dt in actual or (dt-last).days >= 14: last = dt
        dayrec[dt] = (dt-last).days
    mask = (b.line==line).values
    days_cf[mask] = b.loc[mask,'production_date'].map(dayrec).values
bc = b.copy(); bc['days_since_clean'] = days_cf.values
print('days mean actual %.2f cf %.2f max cf %d' % (b.days_since_clean.mean(), days_cf.mean(), days_cf.max()))
print('C3 rate with 14-day cleaning: %.6f' % (expected_defects(bc).sum()/units.sum()))
EOF
python3 $TMPDIR/an/final.py 2>&1 | tail -20

sed -i 's/        p = pred(rep) \* rep.units_produced.values/        p = pred(rep).values * rep.units_produced.values/' $TMPDIR/an/final.py && python3 $TMPDIR/an/final.py 2>&1 | tail -20

python3 - <<'EOF'
import os
p = os.path.join(os.environ['TMPDIR'],'an','final.py')
s = open(p).read()
s = s.replace("last = max(x for x in actual if x < pd.Timestamp('2025-01-01'))", "last = max(x for x in actual if x < pd.Timestamp('2025-01-06'))")
s = s.replace("for dt in pd.date_range('2025-01-01','2025-09-30'):", "for dt in pd.date_range('2025-01-06','2025-09-30'):")
open(p,'w').write(s)
EOF
python3 $TMPDIR/an/final.py 2>&1 | tail -20

sed 's/ + days_since_clean + regime_L2/ + C(days_since_clean) + regime_L2/' $TMPDIR/an/final.py > $TMPDIR/an/final_dummy.py && python3 $TMPDIR/an/final_dummy.py 2>&1 | tail -12

cat > $TMPDIR/an/checkfinal.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
from clean_age import add_age
from refit import fit
import pandas as pd, numpy as np, patsy
b = load()
print('A1', b.batch_id.nunique())
print('A2', (~b.humidity_valid).sum(), 'raw dup-free humidity missing', b.humidity_pct.isna().sum())
print('A3 %.6f' % (b.defective_units.sum()/b.units_produced.sum()))
print('A4 median mold C %.4f  n=%d' % (b.mold_temp_c.median(), b.mold_temp_c.notna().sum()))
# B3 check with final spec residuals
bb = add_age(b).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
bb['regime_L2'] = 0
d = bb.dropna(subset=['humidity_pct','mold']).copy()
d['rate'] = d.defective_units/d.units_produced
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
rhs = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + days_since_clean'
m = fit(rhs, d)
X = patsy.dmatrix(rhs, d, return_type='dataframe')
d['pred'] = m.predict(X)
d['z'] = (d.defective_units - d.pred*d.units_produced)/np.sqrt(d.pred*(1-d.pred)*d.units_produced)
for line, g in d.groupby('line'):
    g = g.sort_values('production_date'); z = g.z.values; best=None
    for i in range(30,len(z)-30):
        a,c = z[:i], z[i:]
        t = (c.mean()-a.mean())/np.sqrt(a.var()/len(a)+c.var()/len(c))
        if best is None or abs(t)>abs(best[0]): best=(t, str(g.production_date.values[i])[:10])
    print(line, 'max|t| split', round(best[0],2), best[1])
EOF
python3 $TMPDIR/an/checkfinal.py

cat > $TMPDIR/an/l2start.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
from clean_age import add_age
from refit import fit
import pandas as pd, numpy as np
b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
for start in ['2025-06-10','2025-06-12','2025-06-13','2025-06-14','2025-06-15','2025-06-16','2025-06-17','2025-06-18','2025-06-20']:
    bb = b.copy(); bb['regime_L2'] = ((bb.line=='L2')&(bb.production_date>=start)).astype(int)
    d = bb.dropna(subset=['humidity_pct','mold']).copy()
    rhs = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + days_since_clean + regime_L2'
    mm = fit(rhs, d)
    print(start, 'deviance', round(mm.deviance,2), 'regime coef', round(mm.params['regime_L2'],4))
EOF
python3 $TMPDIR/an/l2start.py

sed -i "s/    d = bb.dropna(subset=\['humidity_pct','mold'\]).copy()/    d = bb.dropna(subset=['humidity_pct','mold']).copy(); d['rate'] = d.defective_units\/d.units_produced/" $TMPDIR/an/l2start.py && python3 $TMPDIR/an/l2start.py

cat > $TMPDIR/an/edge.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
from clean_age import add_age
from refit import fit
import pandas as pd, numpy as np, patsy
pd.set_option('display.width', 250)
b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
b['regime_L2']=0
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
rhs = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + days_since_clean'
d = b.dropna(subset=['humidity_pct','mold']).copy(); d['rate']=d.defective_units/d.units_produced
m = fit(rhs, d)
d['pred'] = m.predict(patsy.dmatrix(rhs, d, return_type='dataframe'))
d['z'] = (d.defective_units - d.pred*d.units_produced)/np.sqrt(d.pred*(1-d.pred)*d.units_produced)
g = d[(d.line=='L2')&(d.production_date>='2025-06-10')&(d.production_date<='2025-06-20')].sort_values('production_date')
print(g[['batch_id','production_date','shift','units_produced','defective_units','pred','z']].round(3).to_string())
print(d[(d.line=='L2')&(d.production_date<'2025-06-15')].z.mean().round(3), d[(d.line=='L2')&(d.production_date>='2025-06-15')].z.mean().round(3))
EOF
python3 $TMPDIR/an/edge.py

sed -i "s/'2025-06-15'/'2025-06-16'/" $TMPDIR/an/final.py $TMPDIR/an/final_dummy.py && echo LINEAR && python3 $TMPDIR/an/final.py 2>&1 | tail -8 && echo DUMMY && python3 $TMPDIR/an/final_dummy.py 2>&1 | tail -8

cat > $TMPDIR/an/daycmp.py <<'EOF'
import sys, os; sys.path.insert(0, os.path.dirname(__file__))
from clean import load
from clean_age import add_age
from refit import fit
from scipy import stats
import pandas as pd, numpy as np
b = add_age(load()).rename(columns={'supplier_code':'sup','mold_temp_c':'mold'})
b['regime_L2'] = ((b.line=='L2')&(b.production_date>='2025-06-16')).astype(int)
H = 'humidity_pct + I(humidity_pct**2) + humidity_pct:C(sup) + I(humidity_pct**2):C(sup)'
base = f'mold + {H} + cycle_time_s + machine_age_years + C(shift) + C(sup) + C(line) + regime_L2'
d = b.dropna(subset=['humidity_pct','mold']).copy(); d['rate']=d.defective_units/d.units_produced
ml = fit(base+' + days_since_clean', d); mc = fit(base+' + C(days_since_clean)', d)
F = ((ml.deviance-mc.deviance)/(ml.df_resid-mc.df_resid))/(mc.deviance/mc.df_resid)
print('linear dev', round(ml.deviance,1), 'categorical dev', round(mc.deviance,1), 'F', round(F,2), 'p', round(stats.f.sf(F, ml.df_resid-mc.df_resid, mc.df_resid),4))
EOF
python3 $TMPDIR/an/daycmp.py
