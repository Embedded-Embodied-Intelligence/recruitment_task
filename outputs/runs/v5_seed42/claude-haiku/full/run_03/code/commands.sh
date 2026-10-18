ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc=b[c].value_counts()
    print('---',c,'nunique',b[c].nunique(),'empty',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_dict())
    else: print(b[c].head(3).tolist(), 'sample non-numeric:', b[c][pd.to_numeric(b[c],errors='coerce').isna()].value_counts().head(10).to_dict())
"
echo; cat suppliers.csv; echo; cat maintenance.csv | head -80

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d),'ids',d.batch_id.nunique())
print('exact-dup rows', b.duplicated().sum())
print(d.head(12).to_string())
# which dup pairs differ
g=d.groupby('batch_id').nunique()
print((g>1).sum())
"


python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
x=b.drop_duplicates()
print('after exact dedupe',len(x))
print('dup batch_id with differing content: lines per id')
dd=x[x.batch_id.duplicated(keep=False)]
print(dd.groupby('batch_id').line.apply(lambda s: tuple(sorted(s))).value_counts().head(10))
print('within-line dup ids', x.duplicated(['batch_id','line']).sum())
# dates
import re
pats=x.production_date.apply(lambda s: 'iso' if re.fullmatch(r'\d{4}-\d{2}-\d{2}',s) else ('slash' if re.fullmatch(r'\d{2}/\d{2}/\d{4}',s) else 'other:'+s))
print(pats.value_counts().head())
sl=x.production_date[pats=='slash'].str.split('/',expand=True).astype(int)
print('first>12',(sl[0]>12).sum(),'second>12',(sl[1]>12).sum(),'both<=12',((sl[0]<=12)&(sl[1]<=12)).sum())
print(x.production_date[pats!='iso'].str[:2].value_counts().head(3))
"


python3 -c "
import pandas as pd, re
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
x=b.drop_duplicates().reset_index(drop=True)
x['fmt']=x.production_date.apply(lambda s: 'iso' if '-' in s else ('dmy' if int(s[:2])>12 else ('mdy' if int(s[3:5])>12 else 'amb')))
print(x.fmt.value_counts())
print(pd.crosstab(x.line,x.fmt))
# position in file
x['pos']=x.index//500
print(pd.crosstab(x.pos,x.fmt))
" 


mkdir -p $TMPDIR/an && cd /tmp/edabench_claude__dp4myvn && cat > $TMPDIR/an/load.py <<'EOF'
import pandas as pd
def load():
    b = pd.read_csv('/tmp/edabench_claude__dp4myvn/batches.csv', dtype=str, keep_default_na=False)
    b = b.drop_duplicates().reset_index(drop=True)
    def pdate(s, line):
        if '-' in s:
            return pd.Timestamp(s)
        a, c, y = s.split('/')
        if line == 'L1':   # MM/DD/YYYY
            return pd.Timestamp(int(y), int(a), int(c))
        if line == 'L4':   # DD/MM/YYYY
            return pd.Timestamp(int(y), int(c), int(a))
        raise ValueError(s)
    b['date'] = [pdate(s, l) for s, l in zip(b.production_date, b.line)]
    b['shift'] = b['shift'].str.strip().str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
    b['supplier_code'] = b['supplier_code'].str.strip().str.upper()
    for c in ['machine_age_years','ambient_temp_c','mold_temp','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        b[c] = pd.to_numeric(b[c], errors='coerce')
    b['humidity_pct'] = pd.to_numeric(b['humidity_pct'].replace('', None), errors='coerce')
    return b
EOF
cd $TMPDIR/an && python3 -c "
from load import load
import pandas as pd
b=load()
print(b.date.min(), b.date.max(), b.shift.isna().sum(), b.supplier_code.value_counts().to_dict())
print(b[['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']].describe().T.to_string())
print('mold_temp >300:', (b.mold_temp>300).sum(), ' <150:', (b.mold_temp<150).sum())
print('humidity <0', (b.humidity_pct<0).sum(), ' >100', (b.humidity_pct>100).sum(), ' NaN', b.humidity_pct.isna().sum())
print('defect>units', (b.defective_units>b.units_produced).sum(), 'units<=0', (b.units_produced<=0).sum(), 'def<0',(b.defective_units<0).sum())
print('date out of window', ((b.date<'2025-01-06')|(b.date>'2025-09-30')).sum())
"


cd $TMPDIR/an && python3 -c "
from load import load
import pandas as pd
b=load()
print(b.date.min(), b.date.max(), b['shift'].isna().sum(), b.supplier_code.value_counts().to_dict())
print(b[['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']].describe().T.to_string())
print('mold_temp >300:', (b.mold_temp>300).sum(), ' <150:', (b.mold_temp<150).sum())
print('humidity <0', (b.humidity_pct<0).sum(), ' >100', (b.humidity_pct>100).sum(), ' NaN', b.humidity_pct.isna().sum())
print('defect>units', (b.defective_units>b.units_produced).sum(), 'units<=0', (b.units_produced<=0).sum(), 'def<0',(b.defective_units<0).sum())
print('date out of window', ((b.date<'2025-01-06')|(b.date>'2025-09-30')).sum())
"


cd $TMPDIR/an && python3 -c "
from load import load
import pandas as pd, numpy as np
b=load()
print('humidity value counts <=5:', b.loc[b.humidity_pct<=5,'humidity_pct'].value_counts().sort_index().to_dict())
print('mold_temp <150 values:', sorted(b.loc[b.mold_temp<150,'mold_temp'].round(1).tolist())[:60])
print(np.histogram(b.mold_temp, bins=[0,50,100,150,180,200,250,300,350,400,450,500]))
b['hot']=b.mold_temp>300
print(pd.crosstab(b.line,b.hot))
print(b.groupby(b.date.dt.month).hot.mean().round(3).to_dict())
print(b.groupby('line').mold_temp.describe().round(1).to_string())
"


cd $TMPDIR/an && python3 -c "
from load import load
import pandas as pd, numpy as np
b=load()
print('zeros by line', b[b.mold_temp==0].line.value_counts().to_dict())
print('humidity -1 by line', b[b.humidity_pct==-1].line.value_counts().to_dict(), 'NaN by line', b[b.humidity_pct.isna()].line.value_counts().to_dict())
l1=b[b.line=='L1'].copy()
l1['post']=l1.date>='2025-04-14'
print(l1[l1.mold_temp>0].groupby('post').mold_temp.describe().round(2).to_string())
l3=b[(b.line=='L3')&(b.mold_temp>0)]
print('L3 F->C range', ((l3.mold_temp-32)*5/9).describe().round(2).to_string())
print('L3 zeros dates', b[(b.line=='L3')&(b.mold_temp==0)].date.dt.date.tolist())
"


cd $TMPDIR/an && python3 -c "
from load import load
import pandas as pd, numpy as np
b=load()
b['rate']=b.defective_units/b.units_produced
v=b[(b.mold_temp>0)&(b.line!='L3')].copy()
v['hum']=v.humidity_pct.where(v.humidity_pct>=0)
print('overall rate', b.defective_units.sum()/b.units_produced.sum())
for c in ['mold_temp','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','units_produced']:
    print(c, round(v[[c,'rate']].corr(method='spearman').iloc[0,1],3))
print(b.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print(b.groupby('supplier_code').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print(b.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print(b.groupby('operator_id').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).sort_values().to_dict())
"


cd $TMPDIR/an && python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)" 2>&1; python3 -c "import statsmodels; print(statsmodels.__version__)" 2>&1 | tail -1

cd $TMPDIR/an && cat > glm1.py <<'EOF'
from load import load
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['fail'] = b.defective_units
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
print('rows used', len(d))
f = 'fail + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)'
m = smf.glm('fail + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)',
            data=d, family=sm.families.Binomial()).fit(scale='X2')
print(m.summary2().tables[1].round(4).to_string())
EOF
python3 glm1.py

cd $TMPDIR/an && cat > glm2.py <<'EOF'
from load import load
import pandas as pd, numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['rate'] = b.defective_units / b.units_produced
d = b.dropna(subset=['mold_c', 'hum']).copy()
print('rows used', len(d))
m = smf.glm('rate ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)',
            data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit(scale='X2')
print('pearson scale', round(m.scale, 3))
print(m.summary2().tables[1].round(4).to_string())
EOF
python3 glm2.py

cd $TMPDIR/an && cat > glm3.py <<'EOF'
from load import load
import pandas as pd, numpy as np, statsmodels.api as sm
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
d = b.dropna(subset=['mold_c', 'hum']).copy()
d['ok'] = d.units_produced - d.defective_units
X = dmatrix('mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)', d, return_type='dataframe')
print('shape', X.shape, 'rank', np.linalg.matrix_rank(X.values))
y = np.column_stack([d.defective_units, d.ok])
m = sm.GLM(y, X, family=sm.families.Binomial()).fit()
print('pearson chi2/df', round(m.pearson_chi2 / m.df_resid, 3))
print(m.summary2().tables[1].round(4).to_string())
EOF
python3 glm3.py 2>&1 | tail -60

cd $TMPDIR/an && python3 -c "
from load import load
import numpy as np
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
d = b.dropna(subset=['mold_c','hum']).copy()
X = dmatrix('mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)', d, return_type='dataframe')
print(X.columns.tolist()[:3])
u,s,vt=np.linalg.svd(X.values, full_matrices=False)
print('small sv', s[-5:])
for i in range(1,4):
    idx=np.argsort(-abs(vt[-i]))[:6]
    print([ (X.columns[j], round(vt[-i][j],3)) for j in idx])
print(d.groupby(['line','supplier_code']).size().unstack())
print(d.groupby(['line','shift']).size().unstack())
"


cd $TMPDIR/an && python3 -c "
from load import load
import numpy as np, pandas as pd
b=load()
print(pd.crosstab(b.operator_id,b.line).to_string())
print(pd.crosstab(b.supplier_code,b.line))
print(b.groupby('line').machine_age_years.mean().round(2).to_dict())
print('mean cycle by supplier', b.groupby('supplier_code').cycle_time_s.mean().round(2).to_dict())
print(b[['mold_temp','humidity_pct','ambient_temp_c','cycle_time_s','machine_age_years']].corr().round(2).to_string())
print('rework/defect ratio sample'); print((b.rework_cost_eur/b.defective_units).describe().round(3).to_string())
print('qc vs defect corr', round(b[['qc_inspection_min','defective_units','units_produced']].corr().iloc[0,1],3), round(b[['qc_inspection_min','defective_units']].corr().iloc[0,1],3))
print('rework vs defect corr', round(b[['rework_cost_eur','defective_units']].corr().iloc[0,1],3))
" 2>&1

cd $TMPDIR/an && cat > glm4.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
def fit(formula, label):
    X = dmatrix(formula, d, return_type='dataframe')
    m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
    print('==', label, 'rank', np.linalg.matrix_rank(X.values), 'k', X.shape[1], 'pearson/df', round(m.pearson_chi2 / m.df_resid, 3), 'deviance', round(m.deviance,1))
    keep = [c for c in ['mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)[T.Night]','l1post','I(hum ** 2)','I(mold_c ** 2)','I(cycle_time_s ** 2)','ambient_temp_c:cycle_time_s'] if c in m.params.index]
    print(pd.DataFrame({'coef': m.params[keep], 'se': m.bse[keep], 'z': m.tvalues[keep]}).round(4).to_string())
    return m
base = 'C(operator_id) + C(shift) + C(supplier_code)'
fit(f'mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + {base}', 'base')
fit(f'mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + l1post + {base}', '+l1post')
fit(f'mold_c + hum + I(hum**2) + cycle_time_s + machine_age_years + ambient_temp_c + {base}', '+hum2')
fit(f'mold_c + I(mold_c**2) + hum + I(hum**2) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + {base}', '+quad')
EOF
python3 glm4.py 2>&1 | grep -v Warning | grep -v wls_results

cd $TMPDIR/an && cat > glm5.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
def fit(formula, label, show):
    X = dmatrix(formula, d, return_type='dataframe')
    m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
    print('==', label, 'rank', np.linalg.matrix_rank(X.values), 'k', X.shape[1], 'pearson/df', round(m.pearson_chi2 / m.df_resid, 3), 'deviance', round(m.deviance,1))
    keep = [c for c in m.params.index if any(s in c for s in show)]
    print(pd.DataFrame({'coef': m.params[keep], 'se': m.bse[keep], 'z': m.tvalues[keep]}).round(5).to_string())
    return m
base = 'mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post'
show = ['hum','mold_c','l1post','cycle','ambient']
fit(f'{base} + C(supplier_code)*(hum + I(hum**2))', 'supplier-specific hum quad', show)
fit(f'{base} + C(supplier_code)*(hum + I(hum**2)) + C(supplier_code)*mold_c', 'supplier-specific + mold', show)
EOF
python3 glm5.py 2>&1 | grep -v Warning | grep -v wls_results

cd $TMPDIR/an && cat > bins.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
# model without humidity, get partial residual-ish: observed minus expected from other covariates
X = dmatrix('mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code)', d, return_type='dataframe')
m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
d['exp'] = m.fittedvalues * d.units_produced
d['obs'] = d.defective_units
d['hb'] = pd.cut(d.hum, bins=np.arange(0, 75, 5))
t = d.groupby(['supplier_code','hb'], observed=True).agg(n=('obs','size'), obs=('obs','sum'), exp=('exp','sum'), u=('units_produced','sum'))
t['O/E'] = (t.obs / t.exp).round(3)
print(t.to_string())
EOF
python3 bins.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > spline.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix, build_design_matrices
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
for df in [4, 6, 8]:
    spec = f'cr(hum, df={df}) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code)'
    X = dmatrix(spec, d, return_type='dataframe')
    m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
    # predict Alpha batches with everything else at their Alpha means, varying humidity
    grid = np.arange(10, 72.01, 0.1)
    g = pd.DataFrame({'hum': grid})
    ref = d[d.supplier_code == 'SP-01']
    for c in ['mold_c','cycle_time_s','machine_age_years','ambient_temp_c','l1post']:
        g[c] = ref[c].mean()
    g['operator_id'] = ref.operator_id.mode()[0]
    g['shift'] = 'Day'
    g['supplier_code'] = 'SP-01'
    Xg = build_design_matrices([X.design_info], g, return_type='dataframe')[0]
    p = m.predict(Xg)
    i = np.argmin(p)
    print(f'df={df} pearson/df={m.pearson_chi2/m.df_resid:.2f} argmin hum={grid[i]:.1f} rate={p[i]:.5f}  rate@20={p[np.argmin(abs(grid-20))]:.5f} rate@30={p[np.argmin(abs(grid-30))]:.5f}')
EOF
python3 spline.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > alpha.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix, build_design_matrices
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
a = d[d.supplier_code == 'SP-01'].copy()
print('alpha rows', len(a))
for spec_h in ['hum + I(hum**2)', 'cr(hum, df=4)', 'cr(hum, df=6)', 'cr(hum, df=8)']:
    spec = f'{spec_h} + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post'
    X = dmatrix(spec, a, return_type='dataframe')
    m = sm.GLM(np.column_stack([a.defective_units, a.ok]), X, family=sm.families.Binomial()).fit()
    grid = np.arange(10, 72.01, 0.1)
    g = pd.DataFrame({'hum': grid})
    for c in ['mold_c','cycle_time_s','machine_age_years','ambient_temp_c','l1post']:
        g[c] = a[c].mean()
    g['operator_id'] = a.operator_id.mode()[0]; g['shift'] = 'Day'
    Xg = build_design_matrices([X.design_info], g, return_type='dataframe')[0]
    p = m.predict(Xg)
    i = np.argmin(p)
    print(f'{spec_h:18s} pearson/df={m.pearson_chi2/m.df_resid:.2f} argmin={grid[i]:.1f} min_rate={p[i]:.5f} rate@20={p[np.argmin(abs(grid-20))]:.5f} rate@40={p[np.argmin(abs(grid-40))]:.5f}')
    if spec_h.startswith('hum +'):
        print('  quad coefs', m.params[['hum','I(hum ** 2)']].round(5).to_dict())
EOF
python3 alpha.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > diag.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
recipe = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}
b['cyc_dev'] = b.cycle_time_s - b.supplier_code.map(recipe)
b['t'] = (b.date - pd.Timestamp('2025-01-06')).dt.days
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
specs = {
 'base': 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code)',
 'cyc_dev': 'hum + I(hum**2) + mold_c + cyc_dev + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code)',
 'cyc_dev+cycle': 'hum + I(hum**2) + mold_c + cycle_time_s + cyc_dev + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code)',
 '+t': 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code) + t',
 '+units': 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + l1post + C(supplier_code) + np.log(units_produced)',
}
for k, s in specs.items():
    X = dmatrix(s, d, return_type='dataframe')
    m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
    show = ['cyc_dev','cycle_time_s','t','np.log(units_produced)','machine_age_years','ambient_temp_c','mold_c','l1post']
    sel = {c: round(m.params[c],4) for c in m.params.index if c in show}
    print(f'{k:14s} pearson/df={m.pearson_chi2/m.df_resid:.3f} dev={m.deviance:.1f} aic={m.aic:.1f}', sel)
EOF
python3 diag.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > resid_time.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
b = load()
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['ok'] = b.units_produced - b.defective_units
d = b.dropna(subset=['mold_c', 'hum']).copy()
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)'
X = dmatrix(spec, d, return_type='dataframe')
m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
d['exp'] = m.fittedvalues * d.units_produced
d['m'] = d.date.dt.to_period('M')
t = d.groupby(['line', 'm']).agg(obs=('defective_units', 'sum'), exp=('exp', 'sum'), u=('units_produced', 'sum'), n=('batch_id' if 'batch_id' in d else 'defective_units', 'size'))
t['O/E'] = (t.obs / t.exp).round(2)
print(t['O/E'].unstack(0).to_string())
print(t.groupby(level=0).apply(lambda g: round(g.obs.sum()/g.exp.sum(),3)))
EOF
python3 resid_time.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > clean.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
b = load()
mt = pd.read_csv('/tmp/edabench_claude__dp4myvn/maintenance.csv', parse_dates=['date'])
cl = mt[mt.event == 'mold_cleaning']
def days_since(row):
    c = cl[(cl.line == row.line) & (cl.date <= row.date)].date
    return (row.date - c.max()).days if len(c) else np.nan
b['dsc'] = b.apply(days_since, axis=1)
print('no prior cleaning rows', b.dsc.isna().sum(), ' by line', b[b.dsc.isna()].line.value_counts().to_dict())
print(b.dsc.describe().round(1).to_dict())
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['ok'] = b.units_produced - b.defective_units
b['l1post'] = ((b.line == 'L1') & (b.date >= '2025-04-14')).astype(int)
d = b.dropna(subset=['mold_c', 'hum', 'dsc']).copy()
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code)'
for extra in ['', ' + dsc', ' + dsc + l1post']:
    X = dmatrix(spec + extra, d, return_type='dataframe')
    m = sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
    print(repr(extra), 'pearson/df', round(m.pearson_chi2/m.df_resid,3), 'dev', round(m.deviance,1), {k: round(m.params[k],5) for k in ['dsc','l1post','mold_c','ambient_temp_c','machine_age_years'] if k in m.params.index})
d['exp'] = m.fittedvalues * d.units_produced
d['bucket'] = pd.cut(d.dsc, [-1, 0, 3, 7, 10, 14, 21, 28, 60])
t = d.groupby('bucket', observed=True).agg(n=('dsc', 'size'), obs=('defective_units', 'sum'), exp=('exp', 'sum'), u=('units_produced', 'sum'))
t['O/E'] = (t.obs / t.exp).round(3); t['rate'] = (t.obs / t.u).round(4)
print(t.to_string())
EOF
python3 clean.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > prep.py <<'EOF'
from load import load
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
def prepare(offset=0.0, dsc_on=True):
    b = load()
    mt = pd.read_csv('/tmp/edabench_claude__dp4myvn/maintenance.csv', parse_dates=['date'])
    cl = mt[mt.event == 'mold_cleaning']
    def dsc(row):
        c = cl[(cl.line == row.line) & (cl.date <= row.date)].date
        return (row.date - c.max()).days
    b['dsc'] = b.apply(dsc, axis=1)
    b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
    b['mold_c'] = np.where(b.line == 'L3', (b.mold_temp - 32) * 5 / 9, b.mold_temp)
    post = (b.line == 'L1') & (b.date >= '2025-04-14')
    b.loc[post, 'mold_c'] = b.loc[post, 'mold_c'] - offset
    b['hum'] = b.humidity_pct.where(b.humidity_pct >= 0)
    b['ok'] = b.units_produced - b.defective_units
    b['l1post'] = post.astype(int)
    return b.dropna(subset=['mold_c', 'hum']).copy()
def fit(d, spec):
    X = dmatrix(spec, d, return_type='dataframe')
    return sm.GLM(np.column_stack([d.defective_units, d.ok]), X, family=sm.families.Binomial()).fit()
EOF
cat > offset.py <<'EOF'
from prep import prepare, fit
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + dsc + l1post'
for off in [0, 8, 10, 11, 12, 13, 13.7, 14, 15, 16]:
    d = prepare(off)
    m = fit(d, spec)
    print(f'offset {off:5.1f} dev {m.deviance:9.1f} dummy {m.params["l1post"]:+.4f} mold {m.params["mold_c"]:.4f} pearson/df {m.pearson_chi2/m.df_resid:.3f}')
EOF
python3 offset.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > offset2.py <<'EOF'
from prep import prepare
import numpy as np, pandas as pd, statsmodels.formula.api as smf
d = prepare(0.0)
d = d[d.mold_c > 0].copy() if 'mold_c' in d else d
d['post'] = d.l1post
d['mon'] = d.date.dt.month
d['L1post'] = d.l1post
# OLS: mold_c on line-level and covariates, using L2 and L4 as reference
r = smf.ols('mold_c ~ C(line) + L1post + C(mon) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + C(operator_id)', data=d).fit()
print('L1post effect (OLS)', round(r.params['L1post'], 3), '+-', round(r.bse['L1post'], 3))
for ln in ['L1', 'L2', 'L4']:
    s = d[d.line == ln]
    print(ln, 'pre', round(s[~s.l1post.astype(bool)].mold_c.mean(), 2), 'post', round(s[s.l1post.astype(bool)].mold_c.mean(), 2) if s.l1post.any() else '-')
print('L2/L4 mean by month', d[d.line.isin(['L2','L4'])].groupby('mon').mold_c.mean().round(1).to_dict())
print('L1 mean by month', d[d.line=='L1'].groupby('mon').mold_c.mean().round(1).to_dict())
EOF
python3 offset2.py 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > offset3.py <<'EOF'
from prep import prepare
import numpy as np, pandas as pd, statsmodels.formula.api as smf
d = prepare(0.0)
d = d[d.mold_c > 0].copy()
d['mon'] = d.date.dt.month
d['L1post'] = d.l1post
for form in ['mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + C(mon)',
              'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + C(mon) + C(supplier_code) + hum',
              'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + C(mon) + C(supplier_code) + hum + C(operator_id)']:
    tr = d[d.L1post == 0]
    r = smf.ols(form, data=tr).fit()
    post = d[d.L1post == 1]
    res = post.mold_c - r.predict(post)
    print(f'{form[-45:]:45s} R2={r.rsquared:.3f} sd={np.sqrt(r.scale):.2f} offset est mean={res.mean():.2f} median={res.median():.2f} n={len(post)}')
    print('   coefs', {k: round(v,3) for k,v in r.params.items() if 'ambient' in k or 'machine' in k or 'cycle' in k})
EOF
python3 offset3.py 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > scan.py <<'EOF'
from prep import prepare, fit
import numpy as np, pandas as pd
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + dsc'
import sys
off = float(sys.argv[1])
d = prepare(off)
base = fit(d, spec)
scale = base.pearson_chi2 / base.df_resid
print(f'offset {off}: base dev {base.deviance:.1f} scale {scale:.3f}')
best = []
dates = pd.date_range('2025-02-01', '2025-08-31', freq='7D')
for ln in ['L1', 'L2', 'L3', 'L4']:
    for dt in dates:
        d['step'] = ((d.line == ln) & (d.date >= dt)).astype(int)
        m = fit(d, spec + ' + step')
        chi = (base.deviance - m.deviance) / scale
        best.append((round(chi, 1), ln, dt.date(), round(m.params['step'], 3)))
best.sort(reverse=True)
for r in best[:6]:
    print(r)
EOF
for o in 0 6.2 12; do python3 scan.py $o 2>&1 | grep -v Warn | grep -v wls; done

cd $TMPDIR/an && cat > check_steps.py <<'EOF'
from prep import prepare
import numpy as np, pandas as pd
d = prepare(6.2)
d['wk'] = d.date.dt.to_period('W')
d['mon'] = d.date.dt.to_period('M')
print('L2 supplier mix by month'); print(pd.crosstab([d[d.line=='L2'].mon], d[d.line=='L2'].supplier_code, normalize='index').round(2).to_string())
print('L3 supplier mix by month'); print(pd.crosstab([d[d.line=='L3'].mon], d[d.line=='L3'].supplier_code, normalize='index').round(2).to_string())
print('L3 mold_c by month', d[d.line=='L3'].groupby('mon').mold_c.mean().round(1).to_dict())
print('L2 mold_c by month', d[d.line=='L2'].groupby('mon').mold_c.mean().round(1).to_dict())
raw = d.groupby(['line','mon']).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).unstack(0).round(4)
print(raw.to_string())
EOF
python3 check_steps.py 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > weekly.py <<'EOF'
from prep import prepare, fit
import numpy as np, pandas as pd
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + dsc'
d = prepare(6.2)
m = fit(d, spec)
d['exp'] = m.fittedvalues * d.units_produced
d['w'] = d.date.dt.to_period('W-SUN').dt.start_time
t = d[d.date >= '2025-04-14'].groupby(['w', 'line']).agg(o=('defective_units', 'sum'), e=('exp', 'sum'), n=('exp', 'size'))
t['OE'] = (t.o / t.e).round(2)
print(t.OE.unstack(1).to_string())
EOF
python3 weekly.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > onset.py <<'EOF'
from prep import prepare, fit
import numpy as np, pandas as pd
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + dsc'
d = prepare(6.2)
base = fit(d, spec); scale = base.pearson_chi2 / base.df_resid
res = []
for ln, rng in [('L2', pd.date_range('2025-06-08', '2025-06-24')), ('L3', pd.date_range('2025-07-12', '2025-07-28'))]:
    for dt in rng:
        d['step'] = ((d.line == ln) & (d.date >= dt)).astype(int)
        m = fit(d, spec + ' + step')
        res.append((ln, dt.date(), round((base.deviance - m.deviance) / scale, 1), round(m.params['step'], 3)))
for r in res: print(r)
# L3 raw mold values before/after 2025-07-19 vs ambient
l3 = d[d.line == 'L3'].copy()
l3['after'] = l3.date >= '2025-07-19'
print(l3.groupby('after').apply(lambda g: pd.Series({'n': len(g), 'raw_mold_mean': g.mold_temp.mean(), 'raw_min': g.mold_temp.min(), 'amb_mean': g.ambient_temp_c.mean(), 'cyc': g.cycle_time_s.mean(), 'mach': g.machine_age_years.mean()})).round(2).to_string())
EOF
python3 onset.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > rework.py <<'EOF'
from load import load
import numpy as np, pandas as pd
b = load()
b['rw_per_def'] = b.rework_cost_eur / b.defective_units
b['qc_per_def'] = b.qc_inspection_min / b.defective_units
b['per'] = np.where(b.date >= '2025-06-16', 'post', 'pre')
b['mon'] = b.date.dt.to_period('M')
print('rework per defect, by line and month (median)')
print(b.groupby(['line','mon']).rw_per_def.median().round(2).unstack(0).to_string())
print('corr rework vs defective by line:', b.groupby('line').apply(lambda g: round(g[['rework_cost_eur','defective_units']].corr().iloc[0,1],3)).to_dict())
print('corr qc vs defective by line:', b.groupby('line').apply(lambda g: round(g[['qc_inspection_min','defective_units']].corr().iloc[0,1],3)).to_dict())
print('corr qc vs units by line:', b.groupby('line').apply(lambda g: round(g[['qc_inspection_min','units_produced']].corr().iloc[0,1],3)).to_dict())
print('corr rework vs units by line:', b.groupby('line').apply(lambda g: round(g[['rework_cost_eur','units_produced']].corr().iloc[0,1],3)).to_dict())
EOF
python3 rework.py 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > offset4.py <<'EOF'
from prep import prepare
import numpy as np, pandas as pd, statsmodels.formula.api as smf
d = prepare(0.0)
d = d[d.mold_c > 0].copy()
d['mon'] = d.date.dt.month
ref = d[(d.l1post == 0) & (d.line != 'L3')]
r = smf.ols('mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + hum', data=ref).fit()
print('ref R2', round(r.rsquared, 3), 'sd', round(np.sqrt(r.scale), 2), {k: round(v, 3) for k, v in r.params.items() if k in ['ambient_temp_c', 'machine_age_years', 'cycle_time_s', 'hum']})
l1 = d[(d.line == 'L1') & (d.l1post == 1)].copy()
l1['pred'] = r.predict(l1)
l1['res'] = l1.mold_c - l1.pred
l1['ambb'] = pd.cut(l1.ambient_temp_c, [0, 17, 20, 23, 26, 40])
print(l1.groupby('ambb', observed=True).agg(n=('res', 'size'), res_mean=('res', 'mean'), res_sd=('res', 'std')).round(2).to_string())
print('overall mean resid', round(l1.res.mean(), 2), 'se', round(l1.res.std() / np.sqrt(len(l1)), 2))
# same check on the pre period of L1 as a sanity check
l1pre = d[(d.line == 'L1') & (d.l1post == 0)].copy()
print('L1 pre residual mean (should be ~0):', round((l1pre.mold_c - r.predict(l1pre)).mean(), 2))
# does L2/L4 behave the same in the same post window?
for ln in ['L2', 'L4']:
    s = d[(d.line == ln) & (d.date >= '2025-04-14')].copy()
    print(ln, 'post-window residual mean (sanity)', round((s.mold_c - r.predict(s)).mean(), 2))
EOF
python3 offset4.py 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > offset5.py <<'EOF'
from prep import prepare
import numpy as np, pandas as pd, statsmodels.formula.api as smf
d = prepare(0.0)
d = d[d.mold_c > 0].copy()
d['mon'] = d.date.dt.month
forms = {
 'ref': 'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + hum',
 '+dsc': 'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + hum + dsc',
 '+dsc+sup': 'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + hum + dsc + C(supplier_code)',
 '+dsc+sup+mon': 'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + hum + dsc + C(supplier_code) + C(mon)',
 '+dsc+sup+mon+op': 'mold_c ~ C(line) + ambient_temp_c + machine_age_years + cycle_time_s + C(shift) + hum + dsc + C(supplier_code) + C(mon) + C(operator_id)',
}
for k, f in forms.items():
    tr = d[d.l1post == 0]
    r = smf.ols(f, data=tr).fit()
    post = d[d.l1post == 1]
    res = post.mold_c - r.predict(post)
    print(f'{k:18s} R2={r.rsquared:.3f} sd={np.sqrt(r.scale):.2f} offset(mean)={res.mean():.2f} se={res.std()/np.sqrt(len(res)):.2f} median={res.median():.2f} dsc_coef={r.params.get("dsc", np.nan):.3f}')
EOF
python3 offset5.py 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > l1test.py <<'EOF'
from prep import prepare, fit
import numpy as np, pandas as pd
spec = 'hum + I(hum**2) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_code) + dsc'
for off in [6.2, 7.6, 12.0]:
    d = prepare(off)
    base = fit(d, spec); scale = base.pearson_chi2 / base.df_resid
    out = []
    for dt in ['2025-04-14', '2025-04-21', '2025-05-01']:
        d['step'] = ((d.line == 'L1') & (d.date >= dt)).astype(int)
        m = fit(d, spec + ' + step')
        out.append((dt, round((base.deviance - m.deviance) / scale, 1), round(m.params['step'], 3)))
    print('offset', off, out)
EOF
python3 l1test.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && python3 -c "
from load import load
import numpy as np, pandas as pd
b = load()
b = b[b.mold_temp != 0].copy()
print('valid mold rows', len(b), 'L1 post', ((b.line=='L1')&(b.date>='2025-04-14')).sum())
c = np.where(b.line=='L3', (b.mold_temp-32)*5/9, b.mold_temp)
post = ((b.line=='L1')&(b.date>='2025-04-14')).values
for off in [0, 6.2, 7.0, 7.6, 12.0]:
    x = c - np.where(post, off, 0)
    print(f'offset {off:5.1f}: median {np.median(x):.3f}  mean {x.mean():.3f}')
print('L3 F->C check: median raw F', np.median(b.mold_temp[b.line=='L3']), '-> C', round(np.median((b.mold_temp[b.line=='L3']-32)*5/9),3))
" 2>&1

cd $TMPDIR/an && cat > final.py <<'EOF'
from prep import prepare
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix
OFF = 6.2
d = prepare(OFF)
d['l2step'] = ((d.line == 'L2') & (d.date >= '2025-06-16')).astype(int)
d['l3step'] = ((d.line == 'L3') & (d.date >= '2025-07-21')).astype(int)
d['rate'] = d.defective_units / d.units_produced
def fit(spec, data=d):
    X = dmatrix(spec, data, return_type='dataframe')
    m = sm.GLM(np.column_stack([data.defective_units, data.ok]), X, family=sm.families.Binomial()).fit()
    return m
FULL = ('C(supplier_code)*(hum + I(hum**2)) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c'
        ' + C(operator_id) + C(shift) + dsc + l1post + l2step + l3step')
m = fit(FULL)
scale = m.pearson_chi2 / m.df_resid
print('rank', np.linalg.matrix_rank(m.model.exog), 'k', m.model.exog.shape[1], 'pearson/df', round(scale, 3), 'n', len(d))
print(pd.DataFrame({'coef': m.params, 'z': m.tvalues, 'p': m.pvalues}).round(5).loc[lambda x: ~x.index.str.contains('operator')].to_string())
# drop-one tests on scaled deviance
tests = {
 'mold_temp (mold_c)': FULL.replace(' + mold_c', ''),
 'humidity (all terms)': FULL.replace('C(supplier_code)*(hum + I(hum**2))', 'C(supplier_code)'),
 'cycle_time_s': FULL.replace(' + cycle_time_s', ''),
 'machine_age_years': FULL.replace(' + machine_age_years', ''),
 'ambient_temp_c': FULL.replace(' + ambient_temp_c', ''),
 'operator_id': FULL.replace(' + C(operator_id)', ''),
 'shift': FULL.replace(' + C(shift)', ''),
}
for k, s in tests.items():
    mr = fit(s)
    chi = (mr.deviance - m.deviance) / scale
    df = m.df_resid - mr.df_resid
    print(f'{k:22s} scaled chi2={chi:9.1f} df={df:.0f}')
EOF
python3 final.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > ambient.py <<'EOF'
from final import *
base = FULL
variants = {
 'full': base,
 'no-ambient': base.replace(' + ambient_temp_c', ''),
}
def chi(spec, data=d):
    mm = fit(spec, data)
    return mm
print('--- mold nonlinearity and line-specific mold slope')
nl = base + ' + I(mold_c**2)'
ls = base + ' + C(line):mold_c'
for lab, s in [('mold quad', nl), ('mold x line', ls)]:
    a = fit(s); b_ = fit(s.replace(' + ambient_temp_c', ''))
    print(f'{lab:12s} ambient coef {a.params["ambient_temp_c"]:.5f} scaled chi2 {(b_.deviance - a.deviance) / (a.pearson_chi2/a.df_resid):.1f}')
print('--- drop L3')
dd = d[d.line != 'L3']
a = fit(base, dd); b_ = fit(base.replace(' + ambient_temp_c', ''), dd)
print(f'no-L3 ambient coef {a.params["ambient_temp_c"]:.5f} scaled chi2 {(b_.deviance - a.deviance) / (a.pearson_chi2/a.df_resid):.1f}')
print('--- seasonal: month FE')
s = base + ' + C(date.dt.month)'
a = fit(s); b_ = fit(s.replace(' + ambient_temp_c', ''))
print(f'month FE ambient coef {a.params["ambient_temp_c"]:.5f} scaled chi2 {(b_.deviance - a.deviance) / (a.pearson_chi2/a.df_resid):.1f}')
print('--- mold on ambient correlation, and mold residual vs ambient check')
print(np.corrcoef(d.mold_c, d.ambient_temp_c)[0,1].round(3))
EOF
python3 ambient.py 2>&1 | grep -v Warn | grep -v wls | tail -20

cd $TMPDIR/an && python3 -c "
from load import load
import numpy as np, statsmodels.formula.api as smf
b = load()
for y in ['qc_inspection_min','rework_cost_eur']:
    r = smf.ols(f'{y} ~ defective_units + units_produced + C(line) + machine_age_years + cycle_time_s + C(shift)', data=b).fit()
    print(y, 'R2', round(r.rsquared,3), {k: (round(r.params[k],4), round(r.tvalues[k],1)) for k in ['defective_units','units_produced','machine_age_years','cycle_time_s']})
r = smf.ols('qc_inspection_min ~ units_produced + C(line) + machine_age_years + cycle_time_s + C(shift)', data=b).fit()
print('qc without defects R2', round(r.rsquared,3))
import pandas as pd
r2 = smf.ols('qc_inspection_min ~ defective_units + C(line)', data=b).fit(); print('qc~defect only R2', round(r2.rsquared,3), round(r2.params['defective_units'],4))
" 2>&1 | grep -v Warn

cd $TMPDIR/an && cat > dsc_shape.py <<'EOF'
from final import d, fit, FULL, np, pd
import statsmodels.api as sm
base = fit(FULL)
scale = base.pearson_chi2 / base.df_resid
spl = FULL.replace(' + dsc', ' + cr(dsc, df=4)')
s = fit(spl)
print('dsc linear dev', round(base.deviance,1), 'spline dev', round(s.deviance,1), 'scaled chi2 gain', round((base.deviance - s.deviance)/scale,1), 'df gain 3')
# binned O/E by dsc under final model
d['exp'] = base.fittedvalues * d.units_produced
d['bk'] = pd.cut(d.dsc, [-1,0,3,7,10,14,21,28,60])
t = d.groupby('bk', observed=True).agg(o=('defective_units','sum'), e=('exp','sum'))
print((t.o/t.e).round(3).to_dict())
# onset check under final model
for dt in ['2025-06-15','2025-06-16','2025-06-17']:
    dd = d.copy(); dd['l2s'] = ((dd.line=='L2') & (dd.date >= dt)).astype(int)
    f2 = FULL.replace(' + l2step', '') + ' + l2s'
    mm = fit(f2, dd)
    print('L2 onset', dt, 'chi2', round((mm.deviance - base.deviance)/scale,1))
EOF
python3 dsc_shape.py 2>&1 | grep -v Warn | grep -v wls | tail -8

cd $TMPDIR/an && cat > answers.py <<'EOF'
from final import d, fit, FULL, np, pd, dmatrix, build_design_matrices
from load import load
import statsmodels.api as sm
from prep import prepare

raw = load()
raw_all = pd.read_csv('/tmp/edabench_claude__dp4myvn/batches.csv', dtype=str, keep_default_na=False)
print('raw rows', len(raw_all), 'exact-dedup', len(raw_all.drop_duplicates()), 'unique (line,batch_id)', len(raw_all.drop_duplicates().drop_duplicates(['line','batch_id'])), 'unique batch_id only', raw_all.batch_id.nunique())

u = raw
A1 = len(u)
A2 = int((u.humidity_pct.isna() | (u.humidity_pct < 0)).sum())
A3 = u.defective_units.sum() / u.units_produced.sum()
v = u[u.mold_temp != 0]
c = np.where(v.line == 'L3', (v.mold_temp - 32) * 5 / 9, v.mold_temp)
post = ((v.line == 'L1') & (v.date >= '2025-04-14')).values
A4 = np.median(c - np.where(post, 6.2, 0))
print('A1', A1, 'A2', A2, 'A3', round(A3, 6), 'A4', round(A4, 3))

# ---- C models use the final spec
base = fit(FULL)
scale = base.pearson_chi2 / base.df_resid
def predict_rate(model, data, spec_info):
    X = build_design_matrices([spec_info], data, return_type='dataframe')[0]
    return model.predict(X).values
info = base.model.data.design_info
p_old = base.fittedvalues.values
recipe = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}
out = {}
for sup in ['SP-01', 'SP-02', 'SP-03']:
    g = d.copy()
    g['supplier_code'] = sup
    g['cycle_time_s'] = recipe[sup]
    p_new = predict_rate(base, g, info)
    defects_new = d.defective_units.values * p_new / p_old
    out[sup] = defects_new.sum() / d.units_produced.sum()
print('C1 counterfactual overall rates', {k: round(v, 6) for k, v in out.items()})
EOF
python3 answers.py 2>&1 | grep -v Warn | grep -v wls | tail -6

cd $TMPDIR/an && sed -i 's/^from final import d, fit, FULL, np, pd, dmatrix, build_design_matrices/from final import d, fit, FULL, np, pd\nfrom patsy import build_design_matrices/' answers.py && python3 answers.py 2>&1 | grep -v Warn | grep -v wls | tail -6

cd $TMPDIR/an && cat > answers2.py <<'EOF'
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix, build_design_matrices
from prep import prepare
from load import load

OFF = 6.2
d = prepare(OFF)
d['l2step'] = ((d.line == 'L2') & (d.date >= '2025-06-16')).astype(int)
d['l3step'] = ((d.line == 'L3') & (d.date >= '2025-07-21')).astype(int)
FULL = ('C(supplier_code)*(hum + I(hum**2)) + mold_c + cycle_time_s + machine_age_years + ambient_temp_c'
        ' + C(operator_id) + C(shift) + dsc + l1post + l2step + l3step')
X = dmatrix(FULL, d, return_type='dataframe')
info = X.design_info
y = np.column_stack([d.defective_units, d.ok])
m = sm.GLM(y, X, family=sm.families.Binomial()).fit()
scale = m.pearson_chi2 / m.df_resid
print('pearson/df', round(scale, 3), 'deviance', round(m.deviance, 1))

def p_of(data, mdl=m, spec_info=info):
    Xn = build_design_matrices([spec_info], data, return_type='dataframe')[0]
    return mdl.predict(Xn).values
p_old = m.fittedvalues.values
units = d.units_produced.values
rec = d.defective_units.values
total_units = units.sum()

# A-series from raw (deduplicated) data
raw = load()
A1 = len(raw)
A2 = int((raw.humidity_pct.isna() | (raw.humidity_pct < 0)).sum())
A3 = raw.defective_units.sum() / raw.units_produced.sum()
v = raw[raw.mold_temp != 0]
c = np.where(v.line == 'L3', (v.mold_temp - 32) * 5 / 9, v.mold_temp)
post = ((v.line == 'L1') & (v.date >= '2025-04-14')).values
A4 = float(np.median(c - np.where(post, OFF, 0)))
print(f'A1={A1} A2={A2} A3={A3:.6f} A4={A4:.3f}')

# B3: steps
print('B3 steps: l2step coef', round(m.params['l2step'], 3), 'l3step', round(m.params['l3step'], 3))

# C1: supplier counterfactual
recipe = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}
c1 = {}
for sup in ['SP-01', 'SP-02', 'SP-03']:
    g = d.copy(); g['supplier_code'] = sup; g['cycle_time_s'] = recipe[sup]
    p_new = p_of(g)
    c1[sup] = float((rec * p_new / p_old).sum() / total_units)
print('C1', {k: round(v, 6) for k, v in c1.items()}, 'best', min(c1, key=c1.get))

# C2: Alpha humidity minimum (quadratic, others at Alpha means)
b1 = m.params['hum']; b2 = m.params['I(hum ** 2)']
hopt = -b1 / (2 * b2)
print('C2 quadratic argmin Alpha', round(hopt, 2), 'hum coef', round(b1, 5), 'hum2', round(b2, 6), 'hum2 SE', round(m.bse['I(hum ** 2)'], 6))
print('observed hum range (valid)', round(d.hum.min(), 1), round(d.hum.max(), 1))
EOF
python3 answers2.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat > c3.py <<'EOF'
import numpy as np, pandas as pd, statsmodels.api as sm
from patsy import dmatrix, build_design_matrices
from prep import prepare
exec(open('answers2.py').read().split('# A-series')[0].replace("print('pearson/df'", "_=('pearson/df'"))
# spline model for dsc
SPL = FULL.replace(' + dsc', ' + cr(dsc, df=4)')
Xs = dmatrix(SPL, d, return_type='dataframe'); info_s = Xs.design_info
ms = sm.GLM(y, Xs, family=sm.families.Binomial()).fit()
print('spline pearson/df', round(ms.pearson_chi2 / ms.df_resid, 3), 'dev', round(ms.deviance, 1), 'linear dev', round(m.deviance, 1))
p_old_s = ms.fittedvalues.values

mt = pd.read_csv('/tmp/edabench_claude__dp4myvn/maintenance.csv', parse_dates=['date'])
cl = mt[mt.event == 'mold_cleaning']
days = pd.date_range('2025-01-06', '2025-09-30')
newdsc = {}
for ln in ['L1', 'L2', 'L3', 'L4']:
    actual = set(cl[cl.line == ln].date)
    prior = cl[(cl.line == ln) & (cl.date < '2025-01-06')].date
    last = prior.max()
    for dt in days:
        if dt in actual:
            last = dt
        elif (dt - last).days >= 14:
            last = dt  # hypothetical extra cleaning
        newdsc[(ln, dt)] = (dt - last).days
d['dsc_new'] = [newdsc[(l, dt)] for l, dt in zip(d.line, d.date)]
print('dsc actual mean', round(d.dsc.mean(), 2), 'new mean', round(d.dsc_new.mean(), 2), 'new max', d.dsc_new.max(), 'hyp cleanings per line', {ln: sum(1 for (l, dt) in newdsc if l == ln and newdsc[(l, dt)] == 0 and dt not in set(cl[cl.line == ln].date)) for ln in ['L1','L2','L3','L4']})
g = d.copy(); g['dsc'] = g.dsc_new
p_new_s = build_design_matrices([info_s], g, return_type='dataframe')[0]
p_new_s = ms.predict(p_new_s).values
ratio = p_new_s / p_old_s
c3 = float((rec * ratio).sum() / total_units)
print('C3 spline (recorded-calibrated) rate', round(c3, 6))
# linear dsc for comparison
p_new_l = p_of(g)
print('C3 linear (recorded-calibrated) rate', round(float((rec * p_new_l / p_old).sum() / total_units), 6))
print('baseline recorded rate', round(rec.sum() / total_units, 6))
# also fully predicted (not ratio) with spline
print('C3 fully predicted spline rate', round(float((units * p_new_s).sum() / total_units), 6))
EOF
python3 c3.py 2>&1 | grep -v Warn | grep -v wls

cd $TMPDIR/an && cat >> c3.py <<'EOF'
full = load()
tot_units_all = full.units_produced.sum(); tot_def_all = full.defective_units.sum()
cov_def = rec.sum(); cov_new = (rec * ratio).sum()
print('covered batches', len(d), 'of', len(full), 'covered recorded defects', cov_def, 'of', tot_def_all)
print('(a) uncovered unchanged:', round((tot_def_all - cov_def + cov_new) / tot_units_all, 6))
print('(b) covered ratio applied to all:', round(tot_def_all * cov_new / cov_def / tot_units_all, 6))
EOF
python3 c3.py 2>&1 | grep -v Warn | grep -v wls | tail -3

cd $TMPDIR/an && python3 -c "
from load import load
import numpy as np
b = load()
l3 = b[(b.line=='L3') & (b.date>='2025-07-10') & (b.date<='2025-08-05') & (b.defective_units>0)].copy()
l3['r'] = (l3.rework_cost_eur / l3.defective_units).round(2)
print(l3.groupby('date').r.agg(['median','size']).round(2).to_string())
pre = b[(b.line=='L3')&(b.date<'2025-07-10')]
print('L3 pre-July rework/defect median', round((pre.rework_cost_eur/pre.defective_units).median(),2))
" 2>&1
