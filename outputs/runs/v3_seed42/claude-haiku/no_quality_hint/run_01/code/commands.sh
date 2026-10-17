ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && cat maintenance.csv | head -80 && python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(df.shape)
for c in df.columns:
    vc=df[c].value_counts()
    print('---',c,'nunique',df[c].nunique(),'blank',(df[c].str.strip()=='').sum())
    if df[c].nunique()<40: print(vc.to_dict())
    else: print(df[c].head(3).tolist(), 'sample non-numeric:', df[c][pd.to_numeric(df[c],errors='coerce').isna()].unique()[:20])
print('dup batch rows', df.duplicated().sum(), 'dup batch_id', df.batch_id.duplicated().sum())
"

python3 -c "
import pandas as pd
df=pd.read_csv('batches.csv')
print(df.dtypes)
d=df[df.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('exact dup rows:', df.duplicated().sum(), ' dup ids:', df.batch_id.duplicated().sum())
# are duplicated ids identical rows?
g=d.groupby('batch_id').nunique()
print('dup ids with differing values:', (g>1).any(axis=1).sum())
print(g[(g>1).any(axis=1)].head(20))
print(d.head(6).to_string())
print(df.describe().T.to_string())
print('humidity NaN', df.humidity_pct.isna().sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
print(len(df), df.batch_id.nunique())
print('humidity -1:', (df.humidity_pct<0).sum(), ' zero:', (df.humidity_pct==0).sum(), ' >100:', (df.humidity_pct>100).sum())
print('humidity NaN:', df.humidity_pct.isna().sum())
print(df.humidity_pct.describe())
print(np.histogram(df.mold_temp, bins=[0,1,100,150,180,190,200,210,220,230,240,250,300,350,380,400,420,460]))
print('mold_temp==0:', (df.mold_temp==0).sum())
print(df[df.mold_temp>300].groupby('line').size())
print(df[df.mold_temp>300].production_date.min(), df[df.mold_temp>300].production_date.max())
print(df[df.mold_temp>0].groupby('line').mold_temp.describe())
print(df[df.mold_temp==0].groupby('line').size())
print(df[(df.mold_temp>0)&(df.mold_temp<300)].groupby('line').mold_temp.describe())
print('units<defective', (df.defective_units>df.units_produced).sum())
"

python3 -c "
import pandas as pd, numpy as np
df=pd.read_csv('batches.csv').drop_duplicates()
df['date']=pd.to_datetime(df.production_date)
df['mt']=np.where(df.line=='L3',(df.mold_temp-32)*5/9,df.mold_temp)
df.loc[df.mold_temp==0,'mt']=np.nan
v=df.dropna(subset=['mt'])
print('L3 zeros:', ((df.line=='L3')&(df.mold_temp==0)).sum())
v['m']=v.date.dt.to_period('M')
print(v.pivot_table(index='m',columns='line',values='mt',aggfunc='median').round(1).to_string())
l1=v[v.line=='L1'].sort_values('date')
print(l1[(l1.date>='2025-04-01')&(l1.date<='2025-04-30')][['production_date','mt']].groupby('production_date').mt.median().round(1).to_string())
"

mkdir -p "$TMPDIR" && cd /tmp/edabench_claude_r8fx24wo && cat > "$TMPDIR/clean.py" <<'EOF'
import pandas as pd, numpy as np

raw = pd.read_csv('/tmp/edabench_claude_r8fx24wo/batches.csv')
dup_rows = raw.duplicated().sum()
df = raw.drop_duplicates().copy()
df['date'] = pd.to_datetime(df.production_date)

# shift normalisation
s = df['shift'].str.strip().str.lower()
df['shift'] = np.select([s.isin(['day', 'd']), s.isin(['night', 'n'])], ['Day', 'Night'], default=None)

# supplier code normalisation
df['supplier_code'] = df.supplier_code.str.strip().str.upper()

# humidity: -1 is a sentinel, blank is missing
df['humidity_invalid'] = df.humidity_pct.isna() | (df.humidity_pct < 0)
df.loc[df.humidity_invalid, 'humidity_pct'] = np.nan

# mold temperature: L3 logged in Fahrenheit, 0 = missing
df['mold_raw'] = df.mold_temp
df.loc[df.mold_raw == 0, 'mold_temp'] = np.nan
f = df.line.eq('L3')
df.loc[f, 'mold_temp'] = (df.loc[f, 'mold_temp'] - 32) * 5 / 9

# L1 sensor replaced 2025-04-14, reads 8.0 C high (calibration check 2025-09-22)
bias = df.line.eq('L1') & (df.date >= '2025-04-14')
df['mold_temp_true'] = df.mold_temp - np.where(bias, 8.0, 0.0)

df['defect_rate'] = df.defective_units / df.units_produced
EOF
cd "$TMPDIR" && python3 -c "
import pandas as pd, numpy as np
exec(open('clean.py').read())
print('dup rows', dup_rows, 'unique', df.batch_id.nunique(), len(df))
print(df['shift'].value_counts(dropna=False).to_dict())
print(df.supplier_code.value_counts().to_dict())
print('humid invalid', df.humidity_invalid.sum(), 'NaN', df.humidity_pct.isna().sum())
print('A3', df.defective_units.sum()/df.units_produced.sum())
print('A4 median mold true', df.mold_temp_true.median(), 'n', df.mold_temp_true.notna().sum())
print('A4 median mold raw-with-F-conv no bias', df.mold_temp.median())
print('defect rate by line', df.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print(df.groupby('supplier_code').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
"

cd "$TMPDIR" && python3 -c "
import pandas as pd, numpy as np
exec(open('clean.py').read())
df['m']=df.date.dt.to_period('M')
g=df.groupby(['m','line']).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack().round(4)
print(g.to_string())
df['w']=df.date.dt.to_period('W')
w=df.groupby(['w','line']).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack().round(3)
print(w.to_string())
" 2>/dev/null

cd "$TMPDIR" && python3 -c "import statsmodels, sklearn, scipy; print(statsmodels.__version__, sklearn.__version__, scipy.__version__)" 2>&1; python3 -c "import pandas; print(pandas.__version__)"

cd "$TMPDIR" && python3 -c "import statsmodels, scipy; print(statsmodels.__version__, scipy.__version__)" 2>&1; pip install -q statsmodels scipy 2>&1 | tail -2; python3 -c "import statsmodels, scipy; print(statsmodels.__version__, scipy.__version__)"

cd "$TMPDIR" && cat > glm1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf
import statsmodels.api as sm
exec(open('clean.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['fail'] = d.defective_units
d['ok'] = d.units_produced - d.defective_units
m = smf.glm('defective_units + ok ~ mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)',
            data=d, family=sm.families.Binomial()).fit(scale='X2')
print(m.summary().tables[1])
print('dispersion', m.scale, 'n', len(d))
EOF
python3 glm1.py

cd "$TMPDIR" && cat > glm2.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('clean.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
def fit(rhs, data=d, scale=None):
    y, X = dmatrices('ok + defective_units ~ ' + rhs, data=data, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit(scale=scale)
    return m
m = fit('mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)')
pd.set_option('display.width', 200)
t = pd.DataFrame({'coef': m.params, 'z': m.tvalues, 'p': m.pvalues})
print(t.round(5).to_string())
print('pearson chi2/df', m.pearson_chi2 / m.df_resid, 'n', m.nobs)
EOF
python3 glm2.py

cd "$TMPDIR" && cat > check.py <<'EOF'
import pandas as pd, numpy as np
from patsy import dmatrix
exec(open('clean.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
X = dmatrix('mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)', d, return_type='dataframe')
print('shape', X.shape, 'rank', np.linalg.matrix_rank(X.values))
print(X.columns.tolist()[:5])
print(pd.crosstab(d.operator_id, d.line).to_string())
print(pd.crosstab(d['shift'], d.line))
print(pd.crosstab(d.supplier_code, d.line))
EOF
python3 check.py

cd "$TMPDIR" && cat > glm3.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('clean.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
def fit(rhs, data=d):
    y, X = dmatrices('ok + defective_units ~ ' + rhs, data=data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(), X
pd.set_option('display.width', 200)
for rhs in ['C(line) + C(shift) + C(supplier_code) + mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c',
            'C(operator_id) + C(shift) + C(supplier_code) + mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c']:
    m, X = fit(rhs)
    print('rank', np.linalg.matrix_rank(X.values), X.shape[1])
    print('Pearson disp', round(m.pearson_chi2 / m.df_resid, 3), 'deviance', round(m.deviance,1), 'AIC', round(m.aic,1))
    keep = [c for c in m.params.index if not c.startswith('C(operator')]
    print(pd.DataFrame({'coef': m.params[keep], 'z': m.tvalues[keep], 'p': m.pvalues[keep]}).round(5).to_string())
    print()
EOF
python3 glm3.py

cd "$TMPDIR" && cat > feat.py <<'EOF'
import pandas as pd, numpy as np
exec(open('clean.py').read())
mt = pd.read_csv('/tmp/edabench_claude_r8fx24wo/maintenance.csv', parse_dates=['date'])
cl = mt[mt.event == 'mold_cleaning'][['date', 'line']]
def days_since(row_date, line):
    prev = cl[(cl.line == line) & (cl.date <= row_date)].date
    return (row_date - prev.max()).days if len(prev) else np.nan
# batch on cleaning day is after cleaning (cleaning before first shift)
df['days_since_clean'] = [days_since(r, l) for r, l in zip(df.date, df.line)]
EOF
cat > glm4.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
print(df.days_since_clean.describe())
print(df.groupby('line').days_since_clean.agg(['min','max','mean']))
print('nan', df.days_since_clean.isna().sum())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
def fit(rhs, data=d):
    y, X = dmatrices('ok + defective_units ~ ' + rhs, data=data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(), X
pd.set_option('display.width', 200)
m, X = fit('C(operator_id) + C(shift) + C(supplier_code) + mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean')
print('Pearson disp', round(m.pearson_chi2 / m.df_resid, 3), 'AIC', round(m.aic,1))
keep = [c for c in m.params.index if not c.startswith('C(operator')]
print(pd.DataFrame({'coef': m.params[keep], 'z': m.tvalues[keep], 'p': m.pvalues[keep]}).round(5).to_string())
EOF
python3 glm4.py

cd "$TMPDIR" && cat > explore.py <<'EOF'
import pandas as pd, numpy as np
exec(open('feat.py').read())
df['dsc_bin'] = pd.cut(df.days_since_clean, [-1,2,4,6,8,10,13,16,20,40])
def rate(g): return pd.Series({'n': len(g), 'rate': g.defective_units.sum()/g.units_produced.sum(), 'mold': g.mold_temp_true.mean(), 'hum': g.humidity_pct.mean(), 'cyc': g.cycle_time_s.mean()})
print(df.groupby('dsc_bin').apply(rate).round(4).to_string())
print(df.groupby(['line','dsc_bin']).apply(rate).round(3).unstack(0)['rate'].to_string())
print(df.groupby('line').apply(rate).round(3))
EOF
python3 explore.py 2>/dev/null

cd "$TMPDIR" && cat > glm5.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
pd.set_option('display.width', 200)
def fit(rhs, data=d):
    y, X = dmatrices('defective_units + ok ~ ' + rhs, data=data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(), X
base = 'C(line) + C(shift) + C(supplier_code) + mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
m, X = fit(base)
print('BASE disp', round(m.pearson_chi2/m.df_resid,3), 'dev', round(m.deviance,1), 'AIC', round(m.aic,1))
print(pd.DataFrame({'coef': m.params, 'z': m.tvalues, 'p': m.pvalues}).round(5).to_string())
for name, rhs in [('op_within_line', 'C(operator_id) + C(shift) + C(supplier_code) + mold_temp_true + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'),
                  ('mold_quad', base + ' + I(mold_temp_true**2)'),
                  ('hum_quad', base + ' + I(humidity_pct**2)'),
                  ('hum_x_supp', base + ' + humidity_pct:C(supplier_code)'),
                  ('shift_x_line', base + ' + C(shift):C(line)'),
                  ('amb_quad', base + ' + I(ambient_temp_c**2)'),
                  ('cyc_quad', base + ' + I(cycle_time_s**2)'),
                  ('dsc_quad', base + ' + I(days_since_clean**2)'),
                  ('age_quad', base + ' + I(machine_age_years**2)')]:
    mm, XX = fit(rhs)
    print(f'{name:15s} disp', round(mm.pearson_chi2/mm.df_resid,3), 'dev', round(mm.deviance,1), 'dAIC', round(mm.aic - m.aic,1), 'k', XX.shape[1])
EOF
python3 glm5.py 2>/dev/null

cd "$TMPDIR" && cat > hum.py <<'EOF'
import pandas as pd, numpy as np
exec(open('feat.py').read())
d = df.dropna(subset=['humidity_pct']).copy()
d['hbin'] = pd.cut(d.humidity_pct, np.arange(0, 80, 5))
def rate(g): return pd.Series({'n': len(g), 'rate': g.defective_units.sum()/g.units_produced.sum()})
print(d.groupby('hbin').apply(rate).round(4).to_string())
print(d.groupby(['hbin','supplier_code']).apply(rate).round(4).unstack()['rate'].to_string())
print(d.groupby(['hbin','supplier_code']).apply(rate).unstack()['n'].to_string())
EOF
python3 hum.py 2>/dev/null

cd "$TMPDIR" && cat > full.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
pd.set_option('display.width', 200)
def fit(rhs, data=d):
    y, X = dmatrices('defective_units + ok ~ ' + rhs, data=data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(), X
ctrl = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
for name, rhs in [
    ('hum_quad_x_supp', ctrl + ' + C(supplier_code)*(humidity_pct + I(humidity_pct**2))'),
    ('hum_bs4_x_supp', ctrl + ' + C(supplier_code)*bs(humidity_pct, df=4)'),
    ('hum_bs6_x_supp', ctrl + ' + C(supplier_code)*bs(humidity_pct, df=6)'),
    ('hum_bs6_x_supp+op', ctrl + ' + C(operator_id) + C(supplier_code)*bs(humidity_pct, df=6)'),
]:
    m, X = fit(rhs)
    print(f'{name:20s} disp {m.pearson_chi2/m.df_resid:.3f} AIC {m.aic:.1f} k {X.shape[1]}')
m, X = fit(ctrl + ' + C(supplier_code)*(humidity_pct + I(humidity_pct**2))')
print(pd.DataFrame({'coef': m.params, 'z': m.tvalues, 'p': m.pvalues}).round(5).to_string())
EOF
python3 full.py 2>/dev/null

cd "$TMPDIR" && cat > resid.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
ctrl = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
rhs = ctrl + ' + C(supplier_code)*bs(humidity_pct, df=6)'
y, X = dmatrices('defective_units + ok ~ ' + rhs, data=d, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
d['p_hat'] = m.predict(X) * 0 + m.fittedvalues  # placeholder
d['exp_def'] = d.units_produced * m.fittedvalues
d['O_minus_E'] = d.defective_units - d.exp_def
d['pearson'] = d.O_minus_E / np.sqrt(d.exp_def * (1 - m.fittedvalues))
d['m'] = d.date.dt.to_period('M')
print(d.groupby(['m','line']).apply(lambda g: g.O_minus_E.sum()/g.exp_def.sum()).unstack().round(3).to_string())
d.to_pickle('resid.pkl')
EOF
python3 resid.py 2>/dev/null

cd "$TMPDIR" && cat > cp.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
ctrl = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
rhs = ctrl + ' + C(supplier_code)*bs(humidity_pct, df=6)'
y, X0 = dmatrices('defective_units + ok ~ ' + rhs, data=d, return_type='dataframe')
base = sm.GLM(y.values, X0, family=sm.families.Binomial()).fit()
print('base dev', round(base.deviance,1))
res = []
dates = sorted(d.date.unique())
for line in ['L1','L2','L3','L4']:
    best = None
    for dt in dates[10:-10]:
        ind = ((d.line == line) & (d.date >= dt)).astype(float).values
        Xd = np.column_stack([X0.values, ind])
        mm = sm.GLM(y.values, Xd, family=sm.families.Binomial()).fit()
        if best is None or mm.deviance < best[1]:
            best = (pd.Timestamp(dt).date(), mm.deviance, mm.params[-1], mm.tvalues[-1])
    print(line, 'best step date', best[0], 'dev drop', round(base.deviance - best[1], 1), 'coef', round(best[2],3), 't', round(best[3],2))
EOF
python3 cp.py 2>/dev/null

cd "$TMPDIR" && cat > l2.py <<'EOF'
import pandas as pd, numpy as np
d = pd.read_pickle('resid.pkl')
l2 = d[(d.line=='L2') & (d.date>='2025-05-25') & (d.date<='2025-06-30')].sort_values(['date'])
print(l2[['production_date','shift','supplier_code','mold_temp_true','humidity_pct','cycle_time_s','units_produced','defective_units','exp_def','O_minus_E']].round(2).to_string())
EOF
python3 l2.py

cd "$TMPDIR" && cat > bias.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d0 = df.dropna(subset=['mold_temp','humidity_pct']).copy()
d0['ok'] = d0.units_produced - d0.defective_units
ctrl = 'C(line) + C(shift) + mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean'
rhs = ctrl + ' + C(supplier_code)*bs(humidity_pct, df=6)'
def dev(data, col):
    data = data.copy()
    data['mt'] = data[col]
    y, X = dmatrices('defective_units + ok ~ ' + rhs.replace('mold_temp', 'mt'), data=data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit().deviance
for off in [0, 4, 6, 8, 10]:
    for bd in ['2025-04-01', '2025-04-14', '2025-04-15', '2025-05-01']:
        d = d0.copy()
        d['mt'] = d.mold_temp - np.where(d.line.eq('L1') & (d.date >= bd), off, 0.0)
        d = d.dropna(subset=['mt'])
        y, X = dmatrices('defective_units + ok ~ ' + rhs.replace('mold_temp', 'mt'), data=d, return_type='dataframe')
        m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
        print(off, bd, round(m.deviance,2))
EOF
python3 bias.py 2>/dev/null

cd "$TMPDIR" && cat > b1.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
pd.set_option('display.width', 200)
print('corr mold vs ambient', round(d[['mold_temp_true','ambient_temp_c']].corr().iloc[0,1],3))
print(d.groupby('line')[['mold_temp_true','ambient_temp_c','machine_age_years','cycle_time_s']].mean().round(2))
rhs = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + C(supplier_code)*bs(humidity_pct, df=6)'
y, X = dmatrices('defective_units + ok ~ ' + rhs, data=d, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit(scale='X2')
keep = [c for c in X.columns if not c.startswith('C(supplier') and 'bs(' not in c]
print('scale', round(m.scale,3))
print(pd.DataFrame({'coef': m.params[keep], 'z': m.tvalues[keep], 'p': m.pvalues[keep]}).round(4).to_string())
# operator within line, quasi F-type via deviance ratio
base = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
rhs2 = rhs.replace('C(line) + ', 'C(operator_id) + ')
y2, X2 = dmatrices('defective_units + ok ~ ' + rhs2, data=d, return_type='dataframe')
m2 = sm.GLM(y2.values, X2, family=sm.families.Binomial()).fit()
print('operator-within-line: dev drop', round(base.deviance - m2.deviance,1), 'extra df', X2.shape[1]-X.shape[1] + 0, 'scale', round(m.scale,2))
# shift test
rhs3 = rhs.replace('C(shift) + ', '')
y3, X3 = dmatrices('defective_units + ok ~ ' + rhs3, data=d, return_type='dataframe')
m3 = sm.GLM(y3.values, X3, family=sm.families.Binomial()).fit()
print('shift: dev drop', round(m3.deviance - base.deviance,1), 'df 1 scale', round(m.scale,2))
EOF
python3 b1.py 2>/dev/null

cd "$TMPDIR" && cat > dbg.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
rhs = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + C(supplier_code)*bs(humidity_pct, df=6)'
y, X = dmatrices('defective_units + ok ~ ' + rhs, data=d, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
print('pearson/df', m.pearson_chi2/m.df_resid, 'scale', m.scale, 'df_resid', m.df_resid, 'nobs', m.nobs)
print('y first rows', y.values[:3], 'units', (y.values.sum(1))[:3], d.units_produced.values[:3])
print('cols', list(X.columns)[:6])
EOF
python3 dbg.py 2>/dev/null

cd "$TMPDIR" && cat > b1.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from scipy import stats
from patsy import dmatrices
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
pd.set_option('display.width', 200)
def fit(rhs):
    y, X = dmatrices('defective_units + ok ~ ' + rhs, data=d, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    return m, X
rhs = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + machine_age_years + ambient_temp_c + days_since_clean + C(supplier_code)*bs(humidity_pct, df=6)'
m, X = fit(rhs)
disp = m.pearson_chi2 / m.df_resid
print('dispersion', round(disp, 3))
se = m.bse * np.sqrt(disp)
z = m.params / se
p = 2 * stats.norm.sf(np.abs(z))
keep = [c for c in X.columns if not c.startswith('C(supplier') and 'bs(' not in c]
print(pd.DataFrame({'coef': m.params[keep], 'z_adj': z[keep], 'p_adj': p[keep]}).round(4).to_string())
# supplier-by-humidity block
def dev_test(rhs_red, label):
    mr, _ = fit(rhs_red)
    ddev = mr.deviance - m.deviance
    dfd = m.df_model - mr.df_model
    F = ddev / dfd / disp
    print(f'{label}: dev change {ddev:.1f}, df {dfd:.0f}, F {F:.2f}, p {stats.f.sf(F, dfd, m.df_resid):.4g}')
dev_test(rhs.replace('C(shift) + ', ''), 'shift')
dev_test(rhs.replace(' + ambient_temp_c', ''), 'ambient')
dev_test(rhs.replace(' + machine_age_years', ''), 'machine_age')
dev_test(rhs.replace(' + cycle_time_s', ''), 'cycle_time')
dev_test(rhs.replace(' + mold_temp_true', ''), 'mold_temp')
dev_test(rhs.replace(' + C(supplier_code)*bs(humidity_pct, df=6)', ''), 'humidity+supplier')
dev_test(rhs.replace('C(line) + ', 'C(operator_id) + '), 'operator (vs line)')
print('operator added to line model:')
rhs_op = rhs + ' + C(operator_id)'
mo, Xo = fit(rhs_op)
print('extra df', mo.df_model - m.df_model)
EOF
python3 b1.py 2>/dev/null

cd "$TMPDIR" && python3 b1.py 2>&1 | grep -v Warning | tail -30

cd "$TMPDIR" && sed -i 's/^se = m.bse \* np.sqrt(disp)$/se = pd.Series(np.asarray(m.bse) * np.sqrt(disp), index=X.columns)/; s/^z = m.params \/ se$/z = pd.Series(np.asarray(m.params), index=X.columns) \/ se/; s/^p = 2 \* stats.norm.sf(np.abs(z))$/p = pd.Series(2 * stats.norm.sf(np.abs(z.values)), index=X.columns)/; s/pd.DataFrame({.coef.: m.params\[keep\], .z_adj.: z\[keep\], .p_adj.: p\[keep\]})/pd.DataFrame({"coef": pd.Series(np.asarray(m.params), index=X.columns)[keep], "z_adj": z[keep], "p_adj": p[keep]})/' b1.py && python3 b1.py 2>&1 | grep -v Warning | tail -40

cd "$TMPDIR" && cat > b2.py <<'EOF'
import pandas as pd, numpy as np
from scipy import stats
exec(open('feat.py').read())
import statsmodels.api as sm
pd.set_option('display.width', 200)
d = df.copy()
d['rate'] = d.defect_rate
print(d[['defective_units','units_produced','rework_cost_eur','qc_inspection_min','rate']].corr().round(3).to_string())
print('rework per defect', (d.rework_cost_eur / d.defective_units).describe().round(3).to_dict())
print('rework per unit', (d.rework_cost_eur / d.units_produced).describe().round(4).to_dict())
r = sm.OLS(d.rework_cost_eur, sm.add_constant(d[['defective_units']])).fit()
print('rework ~ defective R2', round(r.rsquared,4), r.params.round(3).to_dict())
r2 = sm.OLS(d.rework_cost_eur, sm.add_constant(d[['defective_units','units_produced']])).fit()
print('rework ~ defective+units R2', round(r2.rsquared,4), 'resid sd', round(np.sqrt(r2.mse_resid),4))
print('qc ~ rate R2', round(sm.OLS(d.qc_inspection_min, sm.add_constant(d[['rate']])).fit().rsquared,4))
print('qc ~ defective R2', round(sm.OLS(d.qc_inspection_min, sm.add_constant(d[['defective_units']])).fit().rsquared,4))
print('qc ~ units R2', round(sm.OLS(d.qc_inspection_min, sm.add_constant(d[['units_produced']])).fit().rsquared,4))
print('qc ~ line,shift,op, supplier R2?')
print(d.groupby('line').qc_inspection_min.mean().round(2).to_dict())
print(d.groupby('shift').qc_inspection_min.mean().round(2).to_dict())
print(np.corrcoef(d.qc_inspection_min, d.defective_units)[0,1])
EOF
python3 b2.py 2>/dev/null

cd "$TMPDIR" && cat > step_ramp.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
from scipy import stats
exec(open('feat.py').read())
d = df.dropna(subset=['mold_temp_true','humidity_pct']).copy()
d['ok'] = d.units_produced - d.defective_units
rhs = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + days_since_clean + C(supplier_code)*bs(humidity_pct, df=6)'
y, X0 = dmatrices('defective_units + ok ~ ' + rhs, data=d, return_type='dataframe')
base = sm.GLM(y.values, X0, family=sm.families.Binomial()).fit()
print('base dev', round(base.deviance,1), 'AIC', round(base.aic,1))
l2 = (d.line == 'L2').values
dates = sorted(d.date[l2].unique())
best_step = best_ramp = None
for dt in dates[5:-5]:
    t = pd.Timestamp(dt)
    s = (l2 & (d.date >= t).values).astype(float)
    mm = sm.GLM(y.values, np.column_stack([X0.values, s]), family=sm.families.Binomial()).fit()
    if best_step is None or mm.deviance < best_step[1]: best_step = (t.date(), mm.deviance)
    r = (l2 * np.clip((d.date - t).dt.days.values, 0, None)).astype(float)
    mr = sm.GLM(y.values, np.column_stack([X0.values, r]), family=sm.families.Binomial()).fit()
    if best_ramp is None or mr.deviance < best_ramp[1]: best_ramp = (t.date(), mr.deviance)
print('best step', best_step[0], 'dev', round(best_step[1],1))
print('best ramp start', best_ramp[0], 'dev', round(best_ramp[1],1))
# humidity independence check
print(d[['humidity_pct','ambient_temp_c','mold_temp_true','cycle_time_s','days_since_clean']].corr().round(3).iloc[0].to_dict())
print(d.groupby('line').humidity_pct.mean().round(2).to_dict(), d.groupby('shift').humidity_pct.mean().round(2).to_dict())
print(d.groupby('supplier_code').humidity_pct.mean().round(2).to_dict())
EOF
python3 step_ramp.py 2>/dev/null

cd "$TMPDIR" && cat > final.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices, dmatrix
exec(open('feat.py').read())
df['step_L2'] = ((df.line == 'L2') & (df.date >= '2025-06-15')).astype(float)
df['ok'] = df.units_produced - df.defective_units
pd.set_option('display.width', 200)
valid = df.humidity_pct.notna()
tr = df[valid].copy()
def fit_rhs(K):
    rhs = f'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + days_since_clean + step_L2 + C(supplier_code)*bs(humidity_pct, df={K})'
    y, X = dmatrices('defective_units + ok ~ ' + rhs, data=tr, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    return m, X, rhs
for K in [4, 5, 6, 8, 10]:
    m, X, rhs = fit_rhs(K)
    print('K', K, 'AIC', round(m.aic,1), 'disp', round(m.pearson_chi2/m.df_resid,3))
EOF
python3 final.py 2>/dev/null

cd "$TMPDIR" && cat > cf.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices, dmatrix
exec(open('final.py').read().split("for K in")[0])

def make(K):
    m, X, rhs = fit_rhs(K)
    info = X.design_info
    grid = np.quantile(tr.humidity_pct, np.linspace(0.005, 0.995, 200))
    def expected(frame, supplier=None, days=None):
        f = frame.copy()
        if supplier is not None: f['supplier_code'] = supplier
        if days is not None: f['days_since_clean'] = days
        miss = f.humidity_pct.isna()
        out = np.zeros(len(f))
        ok_rows = f[~miss]
        Xo = dmatrix(info, ok_rows, return_type='matrix')
        out[~miss.values] = m.predict(np.asarray(Xo))
        if miss.any():
            fm = f[miss].copy()
            reps = []
            for h in grid:
                t = fm.copy(); t['humidity_pct'] = h; reps.append(t)
            big = pd.concat(reps)
            pr = m.predict(np.asarray(dmatrix(info, big, return_type='matrix'))).reshape(len(grid), -1)
            out[miss.values] = pr.mean(0)
        return out
    return m, expected, grid

K = 8
m, expected, grid = make(K)
p0 = expected(df)
print('model predicted plant rate', round((p0*df.units_produced).sum()/df.units_produced.sum(),5), 'actual', round(df.defective_units.sum()/df.units_produced.sum(),5))
# C1 supplier counterfactual
for code, name in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    p = expected(df, supplier=code)
    print('C1', name, round((p*df.units_produced).sum()/df.units_produced.sum(),5))
# C2 argmin humidity for Alpha over observed range
hgrid = np.arange(np.floor(tr.humidity_pct.min()), np.ceil(tr.humidity_pct.max()), 0.05)
base = df[df.humidity_pct.notna()].iloc[[0]].copy()
rows = pd.concat([base.assign(humidity_pct=h) for h in hgrid])
rows['supplier_code'] = 'SP-01'
pr = m.predict(np.asarray(dmatrix(m_info := m and None or None, rows)) if False else None) if False else None
info = dmatrix  # placeholder
EOF
echo written

cd "$TMPDIR" && cat > cf.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices, dmatrix
exec(open('final.py').read().split("for K in")[0])

def build(K):
    m, X, rhs = fit_rhs(K)
    info = X.design_info
    grid = np.quantile(tr.humidity_pct, np.linspace(0.005, 0.995, 200))
    def expected(frame, supplier=None, days=None):
        f = frame.copy()
        if supplier is not None:
            f['supplier_code'] = supplier
        if days is not None:
            f['days_since_clean'] = days
        miss = f.humidity_pct.isna().values
        out = np.zeros(len(f))
        if (~miss).any():
            out[~miss] = m.predict(np.asarray(dmatrix(info, f[~miss], return_type='matrix')))
        if miss.any():
            fm = f[miss]
            big = pd.concat([fm.assign(humidity_pct=h) for h in grid])
            pr = m.predict(np.asarray(dmatrix(info, big, return_type='matrix')))
            out[miss] = pr.reshape(len(grid), -1).mean(0)
        return out
    return m, info, expected, grid

def plant_rate(p):
    return (p * df.units_produced).sum() / df.units_produced.sum()

K = 8
m, info, expected, grid = build(K)
print('AIC', round(m.aic,1))
p0 = expected(df)
print('model plant rate (all 3000)', round(plant_rate(p0),5), ' actual', round(df.defective_units.sum()/df.units_produced.sum(),5))

# C1: all resin from one supplier
for code, name in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    print('C1', name, round(plant_rate(expected(df, supplier=code)),5))

# C2: Alpha humidity minimising expected rate (other covariates held at a typical row)
hg = np.round(np.arange(np.floor(tr.humidity_pct.min()), np.ceil(tr.humidity_pct.max())+0.001, 0.05), 2)
ref = tr.iloc[[0]].copy()
rows = pd.concat([ref.assign(humidity_pct=h, supplier_code='SP-01') for h in hg])
pa = m.predict(np.asarray(dmatrix(info, rows, return_type='matrix')))
i = np.argmin(pa)
print('C2 Alpha argmin humidity', round(hg[i],2), 'rate', round(pa[i],5), 'range', hg.min(), hg.max())
for K2 in [6, 10]:
    m2, info2, _, _ = build(K2)
    pa2 = m2.predict(np.asarray(dmatrix(info2, rows, return_type='matrix')))
    print('  sensitivity K', K2, 'argmin', round(hg[np.argmin(pa2)],2))

# C3: forced cleaning every 14 days
mt = pd.read_csv('/tmp/edabench_claude_r8fx24wo/maintenance.csv', parse_dates=['date'])
cl = mt[mt.event == 'mold_cleaning']
days_all = pd.date_range('2024-12-01', '2025-09-30')
newdays = np.full(len(df), np.nan)
for line in ['L1','L2','L3','L4']:
    actual = set(cl[cl.line == line].date)
    last = max(x for x in actual if x < pd.Timestamp('2025-01-06'))
    dd = {}
    for day in days_all:
        if day in actual:
            last = day
        elif (day - last).days >= 14:
            last = day
        dd[day] = (day - last).days
    msk = (df.line == line).values
    newdays[msk] = [dd[x] for x in df.date[msk]]
df['days_cf'] = newdays
print('days_since old mean', round(df.days_since_clean.mean(),2), 'max', df.days_since_clean.max(), '| cf mean', round(df.days_cf.mean(),2), 'max', df.days_cf.max())
p3 = expected(df, days=df.days_cf.values)
print('C3 rate with 14-day cleaning', round(plant_rate(p3),5), '| baseline model', round(plant_rate(p0),5))
EOF
python3 cf.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && python3 - <<'EOF'
import re
s = open('cf.py').read()
s = s.replace("K = 8\nm, info, expected, grid = build(K)",
"df['mold_temp_true'] = df.mold_temp_true.fillna(df.groupby('line').mold_temp_true.transform('median'))\nK = 8\nm, info, expected, grid = build(K)")
open('cf.py','w').write(s)
EOF
python3 cf.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && sed -i 's/^hg = np.round(np.arange(np.floor(tr.humidity_pct.min()), np.ceil(tr.humidity_pct.max())+0.001, 0.05), 2)/hg = np.round(np.arange(tr.humidity_pct.min(), tr.humidity_pct.max()+0.001, 0.05), 2)/' cf.py && python3 cf.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && cat > c2.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices, dmatrix
exec(open('final.py').read().split("for K in")[0])
hg = np.round(np.arange(tr.humidity_pct.min(), tr.humidity_pct.max()+0.001, 0.05), 2)
ref = tr.iloc[[0]].copy()
rows = pd.concat([ref.assign(humidity_pct=h, supplier_code='SP-01') for h in hg])
def argmin_for(rhs, data):
    y, X = dmatrices('defective_units + ok ~ ' + rhs, data=data, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    Xr = dmatrix(X.design_info, rows, return_type='matrix')
    pa = m.predict(np.asarray(Xr))
    return hg[np.argmin(pa)], m.aic
ctrl = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + days_since_clean + step_L2'
for name, h in [('quad', 'humidity_pct + I(humidity_pct**2)'), ('cubic', 'humidity_pct + I(humidity_pct**2) + I(humidity_pct**3)')]:
    rhs = ctrl + ' + C(supplier_code)*(' + h + ')'
    print(name, argmin_for(rhs, tr))
for K in [4,5,6,7,8,9,10,12]:
    print('bs', K, argmin_for(ctrl + f' + C(supplier_code)*bs(humidity_pct, df={K})', tr))
EOF
python3 c2.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && cat > c2b.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices, dmatrix
exec(open('final.py').read().split("for K in")[0])
ref = tr.iloc[[0]].copy()
hs = np.arange(12, 50.1, 1.0)
rows = pd.concat([ref.assign(humidity_pct=h, supplier_code='SP-01') for h in hs])
out = {}
ctrl = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + days_since_clean + step_L2'
for K in [6, 8, 10, 12]:
    y, X = dmatrices('defective_units + ok ~ ' + ctrl + f' + C(supplier_code)*bs(humidity_pct, df={K})', data=tr, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    out[f'K{K}'] = m.predict(np.asarray(dmatrix(X.design_info, rows, return_type='matrix')))*100
out = pd.DataFrame(out, index=hs).round(3)
print(out.to_string())
# raw Alpha 2-unit bins, unadjusted
a = tr[tr.supplier_code=='SP-01'].copy()
a['b'] = (a.humidity_pct//2*2)
print(a.groupby('b').apply(lambda g: pd.Series({'n': len(g), 'rate%': 100*g.defective_units.sum()/g.units_produced.sum()})).round(2).T.to_string())
EOF
python3 c2b.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && sed -i 's/hs = np.arange(12, 50.1, 1.0)/hs = np.arange(13, 50.1, 1.0)/' c2b.py && python3 c2b.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && cat > c2c.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices, dmatrix
exec(open('final.py').read().split("for K in")[0])
hg = np.round(np.arange(tr.humidity_pct.min(), tr.humidity_pct.max()+0.001, 0.05), 2)
ref = tr.iloc[[0]].copy()
rows = pd.concat([ref.assign(humidity_pct=h, supplier_code='SP-01') for h in hg])
ctrl = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + days_since_clean + step_L2'
for K in [8, 10, 12, 14, 16, 20, 24]:
    y, X = dmatrices('defective_units + ok ~ ' + ctrl + f' + C(supplier_code)*bs(humidity_pct, df={K})', data=tr, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    pa = m.predict(np.asarray(dmatrix(X.design_info, rows, return_type='matrix')))
    print('K', K, 'AIC', round(m.aic,1), 'argmin', round(hg[np.argmin(pa)],2), 'min rate%', round(100*pa.min(),3))
EOF
python3 c2c.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && sed 's/^K = 8$/K = 12/' cf.py > cf12.py && python3 cf12.py 2>&1 | grep -E "C1|C3|plant" ; python3 -c "
import pandas as pd, numpy as np
exec(open('clean.py').read())
for bd in ['2025-04-14','2025-04-15']:
    b = df.line.eq('L1') & (df.date >= bd)
    mt = df.mold_temp - np.where(b, 8.0, 0)
    mt = mt.where(df.mold_temp != 0)
    mt = np.where(df.line.eq('L3'), np.nan, mt)
    x = pd.Series(np.where(df.line.eq('L3'), (df.mold_temp - 32)*5/9 - np.where(b, 8.0, 0), mt)).where(df.mold_raw != 0)
    print(bd, 'median', round(float(x.median()),3), 'n', int(x.notna().sum()))
" 2>/dev/null

cd "$TMPDIR" && for bd in 2025-04-14 2025-04-15; do sed "s/df.date >= '2025-04-14'/df.date >= '$bd'/" clean.py > clean_bd.py && python3 -c "
import pandas as pd, numpy as np
exec(open('clean_bd.py').read())
print('$bd', 'median true mold C', round(float(df.mold_temp_true.median()),3), 'n', int(df.mold_temp_true.notna().sum()))
" ; done

cd "$TMPDIR" && cat > b1f.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from scipy import stats
from patsy import dmatrices
exec(open('final.py').read().split("for K in")[0])
tr2 = tr.dropna(subset=['mold_temp_true']).copy()
full = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + machine_age_years + days_since_clean + step_L2 + C(supplier_code)*bs(humidity_pct, df=8)'
def fit(rhs):
    y, X = dmatrices('defective_units + ok ~ ' + rhs, data=tr2, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
mf = fit(full)
disp = mf.pearson_chi2 / mf.df_resid
print('dispersion', round(disp,3))
tests = {
 'mold_temp': full.replace(' + mold_temp_true',''),
 'humidity (spline x supplier)': full.replace(' + C(supplier_code)*bs(humidity_pct, df=8)',' + C(supplier_code)'),
 'cycle_time': full.replace(' + cycle_time_s',''),
 'ambient_temp': full.replace(' + ambient_temp_c',''),
 'shift': full.replace(' + C(shift)',''),
 'machine_age': full.replace(' + machine_age_years',''),
 'operator (within line)': full + ' + C(operator_id)',
}
for k, rhs in tests.items():
    mr = fit(rhs)
    if k.startswith('operator'):
        ddev = mr.deviance - mf.deviance; dfn = mr.df_model - mf.df_model
        ddev = -ddev
    else:
        ddev = mr.deviance - mf.deviance; dfn = mf.df_model - mr.df_model
    F = ddev / dfn / disp
    print(f'{k:30s} dev {ddev:9.1f} df {dfn:4.0f} F {F:8.2f} p {stats.f.sf(F, dfn, mf.df_resid):.3g}')
EOF
python3 b1f.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && cat > op.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from scipy import stats
from patsy import dmatrices
exec(open('final.py').read().split("for K in")[0])
tr2 = tr.dropna(subset=['mold_temp_true']).copy()
rhs = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + days_since_clean + step_L2 + C(supplier_code)*bs(humidity_pct, df=8)'
y, X = dmatrices('defective_units + ok ~ ' + rhs, data=tr2, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
tr2['exp'] = tr2.units_produced * m.fittedvalues
g = tr2.groupby(['line','operator_id']).agg(O=('defective_units','sum'), E=('exp','sum'), n=('batch_id','size'))
g['O/E'] = (g.O/g.E).round(3)
g['z'] = ((g.O-g.E)/np.sqrt(g.E)).round(2)
print(g.to_string())
disp = m.pearson_chi2/m.df_resid
chi = (((g.O-g.E)**2)/(g.E*disp)).sum()
print('chi2 across operators (dispersion-adjusted)', round(chi,1), 'df', len(g)-4, 'p', round(stats.chi2.sf(chi, len(g)-4),4))
EOF
python3 op.py 2>&1 | grep -v -i warn

cd "$TMPDIR" && cat > cp2.py <<'EOF'
import pandas as pd, numpy as np
import statsmodels.api as sm
from patsy import dmatrices
exec(open('final.py').read().split("for K in")[0])
tr2 = tr.dropna(subset=['mold_temp_true']).copy()
rhs = 'C(line) + C(shift) + mold_temp_true + cycle_time_s + ambient_temp_c + days_since_clean + step_L2 + C(supplier_code)*bs(humidity_pct, df=8)'
y, X0 = dmatrices('defective_units + ok ~ ' + rhs, data=tr2, return_type='dataframe')
base = sm.GLM(y.values, X0, family=sm.families.Binomial()).fit()
print('base dev', round(base.deviance,1))
dates = sorted(tr2.date.unique())
for line in ['L1','L2','L3','L4']:
    best = None
    for dt in dates[10:-10]:
        ind = ((tr2.line == line) & (tr2.date >= dt)).astype(float).values
        mm = sm.GLM(y.values, np.column_stack([X0.values, ind]), family=sm.families.Binomial()).fit()
        if best is None or mm.deviance < best[1]:
            best = (pd.Timestamp(dt).date(), mm.deviance, mm.params[-1])
    print(line, best[0], 'dev drop', round(base.deviance - best[1],1), 'coef', round(best[2],3))
EOF
python3 cp2.py 2>&1 | grep -v -i warn
