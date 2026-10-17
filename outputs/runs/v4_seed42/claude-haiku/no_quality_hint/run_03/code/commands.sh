ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/profile.py <<'EOF'
import pandas as pd
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape)
print(b.columns.tolist())
for c in b.columns:
    vc = b[c].value_counts()
    print('\n##', c, 'nunique=', b[c].nunique(), 'empty=', (b[c].str.strip()=='').sum())
    if b[c].nunique() < 40:
        print(vc.to_string())
    else:
        print(b[c].sample(12, random_state=1).tolist())
print('\nduplicated batch_id rows:', b.batch_id.duplicated().sum())
print('fully duplicated rows:', b.duplicated().sum())
s = pd.read_csv('suppliers.csv', dtype=str)
print(s.to_string())
m = pd.read_csv('maintenance.csv', dtype=str, keep_default_na=False)
print(m.event.value_counts(), m.note.value_counts(), m.line.value_counts())
print(m.date.head(3).tolist(), m.date.tail(3).tolist())
EOF
python3 $TMPDIR/profile.py

cat > $TMPDIR/p2.py <<'EOF'
import pandas as pd, numpy as np
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
b = b.drop_duplicates()
print('unique rows', len(b), b.batch_id.nunique())
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x = pd.to_numeric(b[c], errors='coerce')
    bad = b.loc[x.isna(), c]
    print(f'\n{c}: nonnumeric={len(bad)} {bad.unique()[:10]}  min={x.min()} max={x.max()}')
    print(x.describe().round(2).to_dict())
h = pd.to_numeric(b.humidity_pct, errors='coerce')
print('humidity <0:', (h<0).sum(), ' >100:', (h>100).sum(), ' ==0:', (h==0).sum())
print(np.sort(h.dropna().unique())[:15], np.sort(h.dropna().unique())[-15:])
mt = pd.to_numeric(b.mold_temp, errors='coerce')
print('mold_temp hist:'); print(pd.cut(mt,[0,150,190,200,210,220,230,300,380,400,500,1000]).value_counts().sort_index())
b['d'] = pd.to_datetime(b.production_date, format='mixed', dayfirst=False, errors='coerce')
print('date parse NaN', b.d.isna().sum())
print(b[['production_date']].assign(mt=mt).groupby(b.production_date.str.len()).size())
EOF
python3 $TMPDIR/p2.py

cat > $TMPDIR/p3.py <<'EOF'
import pandas as pd, numpy as np
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
b['d'] = pd.to_datetime(b.production_date, format='mixed', dayfirst=True)
print(b.production_date.str.match(r'^\d{4}-').sum(), 'iso;', b.production_date.str.match(r'^\d{2}/\d{2}/\d{4}$').sum(), 'slash')
# check ambiguity: slash dates where both parts <=12
sl = b[b.production_date.str.contains('/')]
a = sl.production_date.str.split('/', expand=True).astype(int)
print('slash first>12:', (a[0]>12).sum(), ' second>12:', (a[1]>12).sum(), ' both<=12:', ((a[0]<=12)&(a[1]<=12)).sum())
b['d'] = pd.to_datetime(b.production_date.where(~b.production_date.str.contains('/'), None), errors='coerce')
iso = b.production_date.str.contains('-')
b.loc[iso,'d'] = pd.to_datetime(b.loc[iso,'production_date'], format='%Y-%m-%d')
b.loc[~iso,'d'] = pd.to_datetime(b.loc[~iso,'production_date'], format='%d/%m/%Y', errors='coerce')
print('NaT', b.d.isna().sum(), b.d.min(), b.d.max())
mt = pd.to_numeric(b.mold_temp)
b['mt']=mt
b['hot']= mt>300
print(b.groupby('hot').d.agg(['min','max','count']))
print(b[b.hot].groupby('line').d.agg(['min','max','count']))
print(b[(mt>150)&(mt<300)].groupby('line').size())
print(b[b.mt<100][['batch_id','production_date','line','mt']])
print(b[b.mt.between(300,380)][['batch_id','production_date','line','mt']])
m = pd.read_csv('maintenance.csv')
print(m[m.event!='mold_cleaning'])
EOF
python3 $TMPDIR/p3.py

cat > $TMPDIR/p4.py <<'EOF'
import pandas as pd, numpy as np
raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates().reset_index(drop=True)
def cands(s):
    if '-' in s: return [pd.Timestamp(s)]
    a,b_,y = map(int, s.split('/'))
    out=[]
    for m,d in ((b_,a),(a,b_)):  # MM/DD, DD/MM
        try: out.append(pd.Timestamp(year=y,month=m,day=d))
        except: pass
    return sorted(set(out))
raw['c'] = raw.production_date.map(cands)
raw['unamb'] = raw.c.map(len)==1
print(raw.unamb.value_counts())
# file-order check on unambiguous rows per line
for ln, g in raw.groupby('line'):
    u = g[g.unamb]
    dates = u.c.map(lambda x: x[0])
    print(ln, 'rows', len(g), 'monotone violations among unambiguous:', (dates.diff().dt.days<0).sum())
# all-candidate ranges
rng = pd.Timestamp('2025-01-06'), pd.Timestamp('2025-09-30')
raw['inrng'] = raw.c.map(lambda x: [t for t in x if rng[0]<=t<=rng[1]])
print('no valid candidate:', (raw.inrng.map(len)==0).sum(), ' multiple valid:', (raw.inrng.map(len)>1).sum())
print(raw[raw.inrng.map(len)==0][['batch_id','production_date','line']].head(20))
EOF
python3 $TMPDIR/p4.py

cat >> $TMPDIR/p4.py <<'EOF'

print('---- violations detail for L1')
g = raw[raw.line=='L1'].copy()
u = g[g.unamb].copy(); u['d']=u.c.map(lambda x:x[0])
u['prev']=u.d.shift()
print(u[u.d.diff().dt.days<0][['batch_id','production_date','d','prev']].head(10))
print('file-order sample L1 unamb dates:', u.d.head(15).dt.strftime('%m-%d').tolist())
EOF
python3 $TMPDIR/p4.py | tail -20

mkdir -p $TMPDIR/work && cat > $TMPDIR/work/clean.py <<'EOF'
import pandas as pd, numpy as np

DIR = '/tmp/edabench_claude_otizci89/'

def cands(s):
    if '-' in s:
        return [pd.Timestamp(s)]
    a, b_, y = map(int, s.split('/'))
    out = []
    for m, d in ((b_, a), (a, b_)):  # MM/DD and DD/MM readings
        try:
            out.append(pd.Timestamp(year=y, month=m, day=d))
        except ValueError:
            pass
    return sorted(set(out))

def load():
    raw = pd.read_csv(DIR + 'batches.csv', dtype=str, keep_default_na=False)
    raw = raw.drop_duplicates().reset_index(drop=True)  # 60 exact duplicate rows
    raw['c'] = raw.production_date.map(cands)
    raw['amb'] = raw.c.map(len) > 1
    raw['date'] = pd.NaT
    raw.loc[~raw.amb, 'date'] = raw.loc[~raw.amb, 'c'].map(lambda x: x[0])
    # resolve ambiguous dates by nearest unambiguous neighbours in the same line (file is chronological per line)
    for ln, g in raw.groupby('line'):
        idx = g.index
        known = g.loc[~g.amb, 'date']
        for i in g.index[g.amb]:
            pos = raw.index.get_loc(i)
            before = raw.loc[idx[:idx.get_loc(i)], 'date'].dropna()
            after = raw.loc[idx[idx.get_loc(i)+1:], 'date'].dropna()
            ref = []
            if len(before): ref.append(before.iloc[-1])
            if len(after): ref.append(after.iloc[0])
            cs = raw.at[i, 'c']
            raw.at[i, 'date'] = min(cs, key=lambda t: min(abs((t - r).days) for r in ref))
    raw['date'] = pd.to_datetime(raw.date)
    # numeric fields
    for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s',
              'units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        raw[c] = pd.to_numeric(raw[c], errors='coerce')
    return raw
EOF
cat > $TMPDIR/work/check1.py <<'EOF'
import sys; sys.path.insert(0, '/tmp/edabench_claude_otizci89/../../tmp/claude-0/-tmp-edabench-claude-otizci89/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/work')
EOF
python3 -c "
import sys, os
sys.path.insert(0, os.environ['TMPDIR']+'/work')
from clean import load
import pandas as pd
r = load()
print(r.date.min(), r.date.max(), r.date.isna().sum(), len(r))
print(r.groupby(r.date.dt.month).size())
print('hot mold per line/month:')
r['mt']=r.mold_temp
print(r.assign(hot=r.mt>300).groupby(['line']).hot.mean())
"

python3 - <<'EOF'
import os,sys
sys.path.insert(0, os.environ['TMPDIR']+'/work')
import clean, re
src = open(os.environ['TMPDIR']+'/work/clean.py').read()
src = src.replace("cs = raw.at[i, 'c']", "cs = [t for t in raw.at[i, 'c'] if pd.Timestamp('2025-01-06') <= t <= pd.Timestamp('2025-09-30')] or raw.at[i, 'c']")
open(os.environ['TMPDIR']+'/work/clean.py','w').write(src)
EOF
python3 - <<'EOF'
import os,sys
sys.path.insert(0, os.environ['TMPDIR']+'/work')
from clean import load
import pandas as pd
r = load()
print(r.date.min(), r.date.max(), r.date.isna().sum(), len(r))
print(r.groupby(r.date.dt.month).size().to_dict())
l3 = r[r.line=='L3']
print('L3 mold_temp describe:', l3.mold_temp.describe().round(1).to_dict())
print('L3 values <300 and >0:', l3[(l3.mold_temp<300)&(l3.mold_temp>0)][['batch_id','date','mold_temp']])
print('zeros by line:', r[r.mold_temp==0].line.value_counts().to_dict())
print('zeros by month:', r[r.mold_temp==0].date.dt.month.value_counts().sort_index().to_dict())
print('L3 by month:', l3.groupby(l3.date.dt.month).mold_temp.median().round(1).to_dict())
for ln in ['L1','L2','L4']:
    g=r[(r.line==ln)&(r.mold_temp>0)]
    print(ln, g.groupby(g.date.dt.month).mold_temp.median().round(1).to_dict())
EOF

python3 - <<'EOF'
import os,sys
sys.path.insert(0, os.environ['TMPDIR']+'/work')
from clean import load
import pandas as pd, numpy as np
r = load()
print('batches', r.batch_id.nunique(), len(r))
print('humidity NaN:', r.humidity_pct.isna().sum(), ' == -1:', (r.humidity_pct==-1).sum(), ' <0 other:', ((r.humidity_pct<0)&(r.humidity_pct!=-1)).sum())
inv = r.humidity_pct.isna() | (r.humidity_pct<0)
print('invalid humidity total:', inv.sum())
print('-1 by line:', r[r.humidity_pct==-1].line.value_counts().to_dict())
print('-1 by month:', r[r.humidity_pct==-1].date.dt.month.value_counts().sort_index().to_dict())
print('-1 date range:', r[r.humidity_pct==-1].date.min(), r[r.humidity_pct==-1].date.max())
print('NaN humidity by line:', r[r.humidity_pct.isna()].line.value_counts().to_dict())
print('defective>units:', (r.defective_units>r.units_produced).sum(), ' zero units:', (r.units_produced<=0).sum())
print('A3 rate =', r.defective_units.sum()/r.units_produced.sum(), r.defective_units.sum(), r.units_produced.sum())
print('mean of batch rates', (r.defective_units/r.units_produced).mean())
# L1 sensor replacement
l1 = r[(r.line=='L1')&(r.mold_temp>0)].copy()
l1['after'] = l1.date>=pd.Timestamp('2025-04-14')
print(l1.groupby(l1.date.dt.month).mold_temp.agg(['median','mean','count']).round(1))
print('L1 pre/post:', l1.groupby('after').mold_temp.agg(['median','mean']).round(2))
for ln in ['L2','L4']:
    g = r[(r.line==ln)&(r.mold_temp>0)].copy(); g['after']=g.date>=pd.Timestamp('2025-04-14')
    print(ln, g.groupby('after').mold_temp.agg(['median','mean']).round(2).to_dict())
EOF

python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)"; python3 -c "import scipy; print(scipy.__version__)"; python3 -c "import pandas; print(pandas.__version__)"

python3 -c "import statsmodels; print(statsmodels.__version__)" ; python3 -c "import scipy, numpy; print(scipy.__version__, numpy.__version__)"; pip install statsmodels -q 2>&1 | tail -2; python3 -c "import statsmodels; print('sm', statsmodels.__version__)"

cat >> $TMPDIR/work/clean.py <<'EOF'

def load_full():
    r = load()
    s = pd.read_csv(DIR + 'suppliers.csv', dtype=str)
    s['supplier_code'] = s.supplier_code.str.strip().str.upper()
    r['supplier_code'] = r.supplier_code.str.strip().str.upper()
    r['shift'] = r['shift'].str.strip().str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
    r = r.merge(s, on='supplier_code', how='left', validate='m:1')
    r['recipe_cycle_time_s'] = pd.to_numeric(r.recipe_cycle_time_s)
    r['rate'] = r.defective_units / r.units_produced
    # mold temperature in C (L3 logs in Fahrenheit; 0.0 = dropout)
    mt = r.mold_temp.where(r.mold_temp > 0)
    r['mold_c'] = mt.where(r.line != 'L3', (mt - 32) * 5 / 9)
    r['hum'] = r.humidity_pct.where(r.humidity_pct >= 0)
    return r
EOF
python3 - <<'EOF'
import os,sys
sys.path.insert(0, os.environ['TMPDIR']+'/work')
from clean import load_full
import pandas as pd, numpy as np
r = load_full()
print(r.shift.value_counts(dropna=False).to_dict(), r.supplier_code.value_counts().to_dict())
print('A4 median mold C:', r.mold_c.median(), r.mold_c.notna().sum())
print(r.groupby('supplier_name').agg(n=('rate','size'), rate=('defective_units','sum'), units=('units_produced','sum')).assign(r=lambda x: x.rate/x.units))
print(r.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print(r.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
print(r.groupby('operator_id').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).sort_values().to_dict())
print(r[['rate','mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur']].corr(method='spearman')['rate'].round(3).to_dict())
r['cyc_dev']=r.cycle_time_s-r.recipe_cycle_time_s
print('cycle dev corr', r.cyc_dev.describe().round(2).to_dict())
r.to_pickle(os.environ['TMPDIR']+'/work/df.pkl')
EOF

python3 - <<'EOF'
import os,sys
sys.path.insert(0, os.environ['TMPDIR']+'/work')
from clean import load_full
import pandas as pd, numpy as np
r = load_full()
print(r['shift'].value_counts(dropna=False).to_dict(), r.supplier_code.value_counts().to_dict())
print('A4 median mold C:', r.mold_c.median(), r.mold_c.notna().sum())
g=r.groupby('supplier_name')
print((g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
g=r.groupby('line'); print((g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
g=r.groupby('shift'); print((g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
g=r.groupby('operator_id'); print((g.defective_units.sum()/g.units_produced.sum()).round(4).sort_values().to_dict())
print(r[['rate','mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur']].corr(method='spearman')['rate'].round(3).to_dict())
r['cyc_dev']=r.cycle_time_s-r.recipe_cycle_time_s
print('cycle dev', r.cyc_dev.describe().round(2).to_dict())
r.to_pickle(os.environ['TMPDIR']+'/work/df.pkl')
EOF

python3 - <<'EOF'
import os,sys
import pandas as pd, numpy as np
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
r['rw_per_def']=r.rework_cost_eur/r.defective_units
print('rework per defect:', r.rw_per_def.describe().round(3).to_dict())
print('corr rework vs defects', np.corrcoef(r.rework_cost_eur, r.defective_units)[0,1].round(4), ' vs units', np.corrcoef(r.rework_cost_eur, r.units_produced)[0,1].round(4))
print('corr qc vs defects', np.corrcoef(r.qc_inspection_min, r.defective_units)[0,1].round(4), ' vs units', np.corrcoef(r.qc_inspection_min, r.units_produced)[0,1].round(4), ' vs rate', np.corrcoef(r.qc_inspection_min, r.rate)[0,1].round(4))
import statsmodels.formula.api as smf
m = smf.ols('qc_inspection_min ~ defective_units + units_produced + rate', data=r).fit()
print(m.params.round(4).to_dict(), round(m.rsquared,3))
m2 = smf.ols('rework_cost_eur ~ defective_units', data=r).fit()
print(m2.params.round(4).to_dict(), round(m2.rsquared,4))
EOF

cat > $TMPDIR/work/feat.py <<'EOF'
import os, pandas as pd, numpy as np
DIR = '/tmp/edabench_claude_otizci89/'
def add_cleaning(r):
    m = pd.read_csv(DIR + 'maintenance.csv')
    m['date'] = pd.to_datetime(m.date)
    cl = m[m.event == 'mold_cleaning'][['line', 'date']].sort_values('date')
    out = []
    for ln, g in r.groupby('line'):
        c = cl[cl.line == ln].date.values
        for i, d in zip(g.index, g.date.values):
            prev = c[c <= d]
            last = prev[-1] if len(prev) else np.datetime64('NaT')
            out.append((i, (pd.Timestamp(d) - pd.Timestamp(last)).days if len(prev) else np.nan))
    s = pd.Series(dict(out))
    r['days_since_clean'] = s.reindex(r.index)
    return r
EOF
python3 - <<'EOF'
import os,sys
sys.path.insert(0, os.environ['TMPDIR']+'/work')
from feat import add_cleaning
import pandas as pd, numpy as np
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
r = add_cleaning(r)
r.to_pickle(os.environ['TMPDIR']+'/work/df.pkl')
print(r.days_since_clean.describe().round(1).to_dict())
print('days>14 share:', (r.days_since_clean>14).mean().round(3))
print(r.groupby(pd.cut(r.days_since_clean,[-1,3,7,10,14,21,30,60,200])).apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4))
print(r.groupby('line').days_since_clean.agg(['mean','max']).round(1))
EOF

cat > $TMPDIR/work/m1.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf
import statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['cyc_dev'] = d.cycle_time_s - d.recipe_cycle_time_s
d['succ'] = d.defective_units
d['fail'] = d.units_produced - d.defective_units
print('n=', len(d))
def fit(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), freq_weights=None).fit(scale='X2') if False else \
        smf.glm(f, data=data, family=sm.families.Binomial()).fit(scale='X2')
f_full = 'rate ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
# use proportions with var weights
m = smf.glm('rate ~ ' + f_full.split('~')[1], data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit(scale='X2')
print(m.summary().tables[1])
print('scale', m.scale)
EOF
python3 $TMPDIR/work/m1.py 2>&1 | head -80

python3 - <<'EOF'
import os
import pandas as pd, numpy as np
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
print(pd.crosstab(d.operator_id, d.line).to_string())
print(pd.crosstab(d.supplier_name, d.line))
print(pd.crosstab(d.supplier_name, d['shift']))
print(pd.crosstab(d.operator_id, d['shift']).T.to_string())
import patsy
X = patsy.dmatrix('C(operator_id)+C(shift)+C(supplier_name)+C(line)+mold_c+hum+cycle_time_s+machine_age_years+ambient_temp_c+days_since_clean', d, return_type='dataframe')
print(X.shape, np.linalg.matrix_rank(X.values), X.columns.tolist()[:3])
EOF

cat > $TMPDIR/work/m2.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['cyc_dev'] = d.cycle_time_s - d.recipe_cycle_time_s
def glm(f):
    return smf.glm(f, data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit(scale='X2')
base = 'mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean'
A = glm('rate ~ ' + base + ' + C(operator_id)')
B = glm('rate ~ ' + base + ' + C(line)')
print('scale A', round(A.scale,2), 'dev A', round(A.deviance,1), 'dfres', A.df_resid, '| B dev', round(B.deviance,1), B.df_resid)
F = ((B.deviance - A.deviance)/(B.df_resid - A.df_resid)) / A.scale
print('operator within line (beyond line) F=', round(F,2), 'p=', stats.f.sf(F, B.df_resid-A.df_resid, A.df_resid))
# drop-one on line-level model B
full = B
for term in ['mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)','C(supplier_name)','days_since_clean','C(line)']:
    t = term
    import re
    f_red = 'rate ~ ' + ' + '.join([x.strip() for x in ('mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)').split(' + ') if x.strip()!=term])
    R = glm(f_red)
    dfn = R.df_resid - full.df_resid
    F = ((R.deviance - full.deviance)/dfn)/full.scale
    print(f'drop {term:22s} dfdiff={dfn:2d} F={F:8.2f} p={stats.f.sf(F, dfn, full.df_resid):.4g}')
print(B.summary().tables[1])
EOF
python3 $TMPDIR/work/m2.py

cat > $TMPDIR/work/m3.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
base = 'mold_c + hum + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)'
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
M0 = glm('rate ~ ' + base)
print('M0 scale', round(M0.scale,2))
res = []
for ln in ['L1','L2','L3','L4']:
    for dt in pd.date_range('2025-02-01','2025-09-01',freq='D'):
        d['step'] = ((d.line==ln)&(d.date>=dt)).astype(int)
        M1 = glm('rate ~ ' + base + ' + step', d)
        chi = (M0.deviance - M1.deviance)/M1.scale
        res.append((ln, dt.date(), chi, M1.params['step'], M1.bse['step']))
res = pd.DataFrame(res, columns=['line','date','chi2','coef','se'])
print(res.sort_values('chi2', ascending=False).head(12).to_string())
print(res.groupby('line').apply(lambda g: g.loc[g.chi2.idxmax()]).to_string())
EOF
python3 $TMPDIR/work/m3.py

python3 - <<'EOF'
import os
import pandas as pd, numpy as np
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
r['wk'] = r.date.dt.to_period('M')
t = r.groupby(['wk','line']).apply(lambda g: pd.Series({'rate': g.defective_units.sum()/g.units_produced.sum(), 'n': len(g), 'mold': g.mold_c.median(), 'dsc': g.days_since_clean.mean(), 'hum': g.hum.mean(), 'cyc': g.cycle_time_s.mean(), 'amb': g.ambient_temp_c.mean()})).reset_index()
print(t.pivot(index='wk', columns='line', values='rate').round(4).to_string())
print(t.pivot(index='wk', columns='line', values='mold').round(1).to_string())
print(t.pivot(index='wk', columns='line', values='cyc').round(2).to_string())
EOF

cat > $TMPDIR/work/m4.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
base = 'mold_c + hum + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)'
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
M0 = glm('rate ~ ' + base)
for extra in [['s_L2'],['s_L3'],['s_L1'],['s_L2','s_L3'],['s_L2','s_L3','s_L1']]:
    M = glm('rate ~ ' + base + ' + ' + ' + '.join(extra))
    print(extra, 'coef', M.params[extra].round(3).tolist(), 'se', M.bse[extra].round(3).tolist(), 'dev', round(M.deviance,1), 'scale', round(M.scale,2))
M = glm('rate ~ ' + base + ' + s_L2 + s_L3 + s_L1')
print(M.summary().tables[1])
# cleaning history per line in the period
m = pd.read_csv('/tmp/edabench_claude_otizci89/maintenance.csv', parse_dates=['date'])
c = m[(m.event=='mold_cleaning')&(m.date>='2025-04-01')].sort_values(['line','date'])
print(c.groupby('line').date.apply(lambda x: [d.strftime('%m-%d') for d in x]).to_string())
EOF
python3 $TMPDIR/work/m4.py

python3 - <<'EOF'
import os
import pandas as pd, numpy as np
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
r['rw_per_def'] = r.rework_cost_eur / r.defective_units
r['wk'] = r.date.dt.to_period('M')
print(r.groupby(['wk','line']).rw_per_def.median().unstack().round(3).to_string())
print(r.groupby(['wk','line']).qc_inspection_min.median().unstack().round(2).to_string())
# rework vs defects consistency per line, pre/post
r['post2'] = (r.line=='L2')&(r.date>='2025-06-15')
r['post3'] = (r.line=='L3')&(r.date>='2025-07-21')
g = r.groupby(['line', r.date>='2025-06-15'])
print(g.apply(lambda x: pd.Series({'rw_per_def_med': (x.rework_cost_eur/x.defective_units).median(), 'qc_med': x.qc_inspection_min.median(), 'rate': x.defective_units.sum()/x.units_produced.sum(), 'def_per_batch': x.defective_units.mean()})).round(4).to_string())
EOF

python3 - <<'EOF'
import os
import pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
# model without L2 step, on non-L2 data, to predict L2 from its own covariates is not possible; instead fit L2-only model pre-June and predict
base = 'mold_c + hum + cycle_time_s + C(shift) + C(supplier_name) + days_since_clean'
pre = d[(d.line=='L2')&(d.date<'2025-06-01')]
M = smf.glm('rate ~ ' + base, data=pre, family=sm.families.Binomial(), var_weights=pre.units_produced).fit(scale='X2')
L2 = d[d.line=='L2'].copy()
L2['pred'] = M.predict(L2)
L2['res'] = (L2.defective_units - L2.pred*L2.units_produced)
L2['exp']= L2.pred*L2.units_produced
L2['wk'] = L2.date.dt.to_period('W')
x = L2[(L2.date>='2025-05-25')&(L2.date<='2025-07-10')].groupby('date').agg(n=('rate','size'), obs=('defective_units','sum'), units=('units_produced','sum'), exp=('exp','sum'))
x['obs_rate']= x.obs/x.units; x['exp_rate']=x.exp/x.units
print(x.round(3).to_string())
EOF

python3 - <<'EOF'
import os
import pandas as pd, numpy as np
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
c = 4.2537  # EUR per defect from rework ~ defects fit
r['impl_def'] = r.rework_cost_eur / c
per = {'L1':'2025-04-14','L2':'2025-06-15','L3':'2025-07-21','L4':'2025-07-01'}
rows=[]
for ln,g in r.groupby('line'):
    for lab, m in [('pre', g.date < pd.Timestamp(per[ln])), ('post', g.date >= pd.Timestamp(per[ln]))]:
        x = g[m]
        rows.append((ln, lab, len(x), round(x.defective_units.sum()/x.units_produced.sum(),4), round(x.impl_def.sum()/x.units_produced.sum(),4), round((x.rework_cost_eur/x.defective_units).median(),3)))
print(pd.DataFrame(rows, columns=['line','period','n','recorded_rate','rework_implied_rate','rw_per_def_median']).to_string())
# monthly implied rate per line
r['m']=r.date.dt.to_period('M')
print(r.groupby(['m','line']).apply(lambda x: x.impl_def.sum()/x.units_produced.sum()).unstack().round(4).to_string())
EOF

cat > $TMPDIR/work/m5.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['impl'] = (d.rework_cost_eur/4.2537).round().clip(lower=1)
d['irate'] = d.impl/d.units_produced
base = 'mold_c + hum + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(line)'
def glm(f, data=d, y='irate'):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
M0 = glm('irate ~ ' + base)
print('base (implied counts) dev', round(M0.deviance,1), 'scale', round(M0.scale,2))
res=[]
for ln in ['L1','L2','L3','L4']:
    best=None
    for dt in pd.date_range('2025-03-01','2025-08-15',freq='D'):
        d['step']=((d.line==ln)&(d.date>=dt)).astype(int)
        M1=glm('irate ~ '+base+' + step', d)
        chi=(M0.deviance-M1.deviance)/M1.scale
        if best is None or chi>best[2]: best=(ln,dt.date(),chi,M1.params['step'])
    res.append(best)
print(pd.DataFrame(res,columns=['line','date','chi2','coef']).to_string())
# recorded counts for comparison (same covariates)
d['rec_rate']=d.defective_units/d.units_produced
EOF
python3 $TMPDIR/work/m5.py

cat > $TMPDIR/work/m6.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['cyc_dev'] = d.cycle_time_s - d.recipe_cycle_time_s
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['pre'] = d.pre_dried
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
steps = 'C(line) + s_L2 + s_L1'
M = glm(f'rate ~ mold_c + hum + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + {steps}')
print('linear, with steps: ambient', M.params['ambient_temp_c'].round(4), 'p', M.pvalues['ambient_temp_c'].round(3))
# humidity curvature and supplier interaction
Mq = glm(f'rate ~ mold_c + hum + I(hum**2) + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + {steps}')
print('quad hum:', Mq.params[['hum','I(hum ** 2)']].round(5).to_dict(), Mq.pvalues[['hum','I(hum ** 2)']].round(4).to_dict())
Mi = glm(f'rate ~ mold_c + hum*C(supplier_name) + cycle_time_s + ambient_temp_c + C(shift) + days_since_clean + {steps}')
print(Mi.summary().tables[1])
Mp = glm(f'rate ~ mold_c + hum*pre + cycle_time_s + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + {steps}')
print('hum x pre_dried', Mp.params.filter(like='hum').round(5).to_dict(), Mp.pvalues.filter(like='hum').round(4).to_dict())
# days shape
Md = glm(f'rate ~ mold_c + hum + cycle_time_s + C(shift) + C(supplier_name) + C(pd.cut(days_since_clean,[-1,3,7,10,14,20,40])) + {steps}')
print('days bins:', Md.params.filter(like='days').round(3).to_dict())
Mm = glm(f'rate ~ mold_c + hum + cycle_time_s + C(shift) + C(supplier_name) + days_since_clean + I(days_since_clean**2) + {steps}')
print('days quad:', Mm.params[['days_since_clean','I(days_since_clean ** 2)']].round(4).to_dict(), Mm.pvalues[['days_since_clean','I(days_since_clean ** 2)']].round(4).to_dict())
# mold and cycle nonlinearity
Mc = glm(f'rate ~ mold_c + I(mold_c**2) + hum + cycle_time_s + I(cycle_time_s**2) + C(shift) + C(supplier_name) + days_since_clean + {steps}')
print('mold/cycle quad:', Mc.params[['mold_c','I(mold_c ** 2)','cycle_time_s','I(cycle_time_s ** 2)']].round(5).to_dict(), Mc.pvalues[['mold_c','I(mold_c ** 2)','cycle_time_s','I(cycle_time_s ** 2)']].round(4).to_dict())
EOF
python3 $TMPDIR/work/m6.py

cat > $TMPDIR/work/m7.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['sup'] = d.supplier_name
d['pd'] = np.where(d.pre_dried=='yes','pre','no')
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
steps = 'C(line) + s_L2 + s_L1'
ctrl = 'mold_c + cycle_time_s + C(shift) + days_since_clean'
A = glm(f'rate ~ {ctrl} + C(sup)*hum + {steps}')
B = glm(f'rate ~ {ctrl} + C(sup)*(hum + I(hum**2)) + {steps}')
C = glm(f'rate ~ {ctrl} + C(sup)*(hum + I(hum**2)) + ambient_temp_c + {steps}')
print('dev A', round(A.deviance,1), 'B', round(B.deviance,1), 'scale', round(B.scale,2))
F = ((A.deviance-B.deviance)/(A.df_resid-B.df_resid))/B.scale
print('quadratic hum by supplier F', round(F,2), 'p', stats.f.sf(F, A.df_resid-B.df_resid, B.df_resid))
print(B.params.filter(regex='hum').round(5).to_string())
print(B.pvalues.filter(regex='hum').round(4).to_string())
print('ambient with quad hum:', C.params['ambient_temp_c'].round(4), C.pvalues['ambient_temp_c'].round(4))
print(d[['ambient_temp_c','hum','mold_c']].corr().round(3))
# ambient effect with no hum at all
D = glm(f'rate ~ {ctrl} + C(sup) + ambient_temp_c + {steps}')
print('ambient w/o hum:', D.params['ambient_temp_c'].round(4), D.pvalues['ambient_temp_c'].round(4))
EOF
python3 $TMPDIR/work/m7.py

cat > $TMPDIR/work/m8.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['sup'] = d.supplier_name
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
steps = 'C(line) + s_L2 + s_L1'
ctrl = 'mold_c + cycle_time_s + C(shift) + days_since_clean'
# nonparametric humidity: bins of 5 pct
d['hbin'] = pd.cut(d.hum, [0,15,20,25,30,35,40,45,50,55,60,80], right=False)
print(d.groupby('hbin', observed=True).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})).round(4).to_string())
for s in ['Alpha','Beta','Gamma']:
    g = d[d.sup==s]
    print(s, g.groupby('hbin', observed=True).apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).round(4).to_dict())
Mq = glm(f'rate ~ {ctrl} + C(sup)*(hum + I(hum**2)) + {steps}')
Mb = glm(f'rate ~ {ctrl} + C(sup)*bs(hum, df=5) + {steps}')
print('bs dev', round(Mb.deviance,1), 'quad dev', round(Mq.deviance,1), 'scale bs', round(Mb.scale,3))
EOF
python3 $TMPDIR/work/m8.py

cat > $TMPDIR/work/m9.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['sup'] = d.supplier_name
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
spl = 'C(sup)*bs(hum, df=5)'
core = f'mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L2 + s_L1'
FULL = glm(f'rate ~ {core} + ambient_temp_c + machine_age_years + C(line)')
print('full scale', round(FULL.scale,3), 'dev', round(FULL.deviance,1), 'df', FULL.df_resid)
def F_test(red, name):
    dfn = red.df_resid - FULL.df_resid
    F = ((red.deviance-FULL.deviance)/dfn)/FULL.scale
    print(f'{name:28s} dfdiff={dfn:3d} F={F:8.2f} p={stats.f.sf(F,dfn,FULL.df_resid):.3g}')
F_test(glm(f'rate ~ {core} + machine_age_years + C(line)'), 'drop ambient')
F_test(glm(f'rate ~ {core} + ambient_temp_c + C(line)'), 'drop machine_age')
F_test(glm(f'rate ~ {core} + ambient_temp_c + machine_age_years'), 'drop line')
F_test(glm(f'rate ~ {core} + ambient_temp_c + machine_age_years + C(line) - C(shift)'), 'drop shift (approx)') if False else None
F_test(glm(f'rate ~ mold_c + cycle_time_s + days_since_clean + {spl} + s_L2 + s_L1 + ambient_temp_c + machine_age_years + C(line)'), 'drop shift')
F_test(glm(f'rate ~ {core.replace("mold_c + ","")} + ambient_temp_c + machine_age_years + C(line)'), 'drop mold_c')
F_test(glm(f'rate ~ {core.replace("cycle_time_s + ","")} + ambient_temp_c + machine_age_years + C(line)'), 'drop cycle_time')
F_test(glm(f'rate ~ {core.replace(spl,"C(sup)")} + ambient_temp_c + machine_age_years + C(line)'), 'drop humidity (keep sup)')
print('---- operator within line test (operators nested in lines)')
OP = glm(f'rate ~ mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L2 + s_L1 + ambient_temp_c + machine_age_years + C(operator_id)')
F = ((FULL.deviance-OP.deviance)/(FULL.df_resid-OP.df_resid))/OP.scale
print('operator beyond line F', round(F,2), 'df', FULL.df_resid-OP.df_resid, 'p', round(stats.f.sf(F, FULL.df_resid-OP.df_resid, OP.df_resid),4))
print('--- cycle x supplier interaction')
X = glm(f'rate ~ mold_c + C(sup)*cycle_time_s + C(shift) + days_since_clean + {spl} + s_L2 + s_L1 + ambient_temp_c + machine_age_years + C(line)')
F = ((FULL.deviance-X.deviance)/(FULL.df_resid-X.df_resid))/X.scale
print('cycle x sup F', round(F,2), 'p', round(stats.f.sf(F, FULL.df_resid-X.df_resid, X.df_resid),4))
print('--- mold x line? (sensor check)')
print(FULL.params[['mold_c','cycle_time_s','days_since_clean','ambient_temp_c','machine_age_years','s_L2','s_L1']].round(4).to_dict())
print(FULL.pvalues[['mold_c','cycle_time_s','days_since_clean','ambient_temp_c','machine_age_years','s_L2','s_L1']].round(4).to_dict())
print(FULL.params[[c for c in FULL.params.index if 'shift' in c]].round(4).to_dict())
EOF
python3 $TMPDIR/work/m9.py

cat > $TMPDIR/work/m10.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['sup'] = d.supplier_name
# what drives mold temp?
M = smf.ols('mold_c ~ ambient_temp_c + cycle_time_s + C(shift) + machine_age_years + hum + days_since_clean + C(line) + s_L1 + C(sup)', data=d).fit()
print('mold ~ :', M.params.round(3).to_dict()); print('R2', round(M.rsquared,3), 'resid sd', round(np.sqrt(M.scale),2))
# ambient effect on defects per line
spl = 'C(sup)*bs(hum, df=5)'
for ln in ['L1','L2','L3','L4']:
    g = d[d.line==ln]
    G = smf.glm(f'rate ~ mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + ambient_temp_c + s_L2 + s_L1', data=g, family=sm.families.Binomial(), var_weights=g.units_produced).fit(scale='X2')
    print(ln, 'ambient', round(G.params['ambient_temp_c'],4), 'p', round(G.pvalues['ambient_temp_c'],4), 'mold', round(G.params['mold_c'],4))
EOF
python3 $TMPDIR/work/m10.py

cat > $TMPDIR/work/m11.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['sup'] = d.supplier_name
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
spl = 'C(sup)*bs(hum, df=5)'
core = f'mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L1 + s_L2 + s_L3'
FULL = glm(f'rate ~ {core} + ambient_temp_c + machine_age_years + C(line)')
print('scale', round(FULL.scale,3), 'dev', round(FULL.deviance,1))
print(FULL.params[['mold_c','cycle_time_s','days_since_clean','ambient_temp_c','machine_age_years','s_L1','s_L2','s_L3']].round(4).to_dict())
print(FULL.pvalues[['mold_c','cycle_time_s','days_since_clean','ambient_temp_c','machine_age_years','s_L1','s_L2','s_L3']].round(4).to_dict())
print('shift night', FULL.params.filter(like='shift').round(4).to_dict(), FULL.pvalues.filter(like='shift').round(5).to_dict())
def F_test(red, name):
    dfn = red.df_resid - FULL.df_resid
    F = ((red.deviance-FULL.deviance)/dfn)/FULL.scale
    print(f'{name:22s} dfdiff={dfn:3d} F={F:8.2f} p={stats.f.sf(F,dfn,FULL.df_resid):.3g}')
F_test(glm(f'rate ~ {core} + machine_age_years + C(line)'), 'drop ambient')
F_test(glm(f'rate ~ {core} + ambient_temp_c + C(line)'), 'drop machine_age')
F_test(glm(f'rate ~ {core} + ambient_temp_c + machine_age_years'), 'drop line')
F_test(glm(f'rate ~ {core.replace("mold_c + ","")} + ambient_temp_c + machine_age_years + C(line)'), 'drop mold')
F_test(glm(f'rate ~ {core.replace("C(shift) + ","")} + ambient_temp_c + machine_age_years + C(line)'), 'drop shift')
F_test(glm(f'rate ~ {core.replace("cycle_time_s + ","")} + ambient_temp_c + machine_age_years + C(line)'), 'drop cycle')
OP = glm(f'rate ~ {core} + ambient_temp_c + machine_age_years + C(operator_id)')
F = ((FULL.deviance-OP.deviance)/(FULL.df_resid-OP.df_resid))/OP.scale
print('operator beyond line F', round(F,2), 'p', round(stats.f.sf(F, FULL.df_resid-OP.df_resid, OP.df_resid),4))
EOF
python3 $TMPDIR/work/m11.py

cat > $TMPDIR/work/m12.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['sup'] = d.supplier_name
def glm(f, data=d):
    return smf.glm(f, data=data, family=sm.families.Binomial(), var_weights=data.units_produced).fit(scale='X2')
spl = 'C(sup)*bs(hum, df=5)'
core = f'mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L1 + s_L2 + s_L3 + C(line)'
OP = glm(f'rate ~ {core} + C(operator_id)')
# operator deviations relative to line: use operator dummies only (line implied) and report contrasts within line
FULL = glm(f'rate ~ {core}')
print('dev full', round(FULL.deviance,1), 'dev op', round(OP.deviance,1))
ops = d.groupby('operator_id').apply(lambda g: pd.Series({'line': g.line.iloc[0], 'n': len(g)}))
# within-line: operator effects relative to line mean
coefs = OP.params.filter(like='operator')
print(coefs.round(3).to_string())
# time-split: is the operator spread concentrated in L2 post?
for period, m in [('pre', d.date<'2025-06-15'), ('post', d.date>='2025-06-15')]:
    g = d[(d.line=='L2') & m]
    print(period, g.groupby('operator_id').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).round(4).to_dict())
EOF
python3 $TMPDIR/work/m12.py

cat > $TMPDIR/work/m13.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['sup'] = d.supplier_name
spl = 'C(sup)*bs(hum, df=5)'
for ln in ['L1','L2','L3','L4']:
    g = d[d.line==ln].copy()
    base = f'mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L1 + s_L2 + s_L3'
    def glm(f):
        return smf.glm(f, data=g, family=sm.families.Binomial(), var_weights=g.units_produced).fit(scale='X2')
    R = glm(f'rate ~ {base}')
    F_ = glm(f'rate ~ {base} + C(operator_id)')
    dfn = R.df_resid - F_.df_resid
    Fst = ((R.deviance - F_.deviance)/dfn)/F_.scale
    print(ln, 'n', len(g), 'ops', g.operator_id.nunique(), 'F', round(Fst,2), 'df', dfn, 'p', round(stats.f.sf(Fst,dfn,F_.df_resid),4))
EOF
python3 $TMPDIR/work/m13.py 2>/dev/null

cat > $TMPDIR/work/final.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','days_since_clean']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
dv = d.dropna(subset=['hum']).copy()           # complete humidity rows (fit sample)
spl = 'C(supplier_name)*bs(hum, df=5)'
f = f'rate ~ mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L1 + s_L2 + s_L3 + C(line)'
M = smf.glm(f, data=dv, family=sm.families.Binomial(), var_weights=dv.units_produced).fit(scale='X2')
print('fit n', len(dv), 'scale', round(M.scale,3))
# --- C2: Alpha humidity optimum over observed valid range
grid = np.round(np.arange(dv.hum.min(), dv.hum.max()+1e-9, 0.1), 2)
base_row = dv.iloc[[0]].copy()
def pred_alpha(h):
    x = dv.iloc[[0]].copy()
    x = x.assign(hum=h, supplier_name='Alpha')
    return float(M.predict(x).iloc[0])
pa = np.array([pred_alpha(h) for h in grid])
print('C2 Alpha argmin hum (spline):', grid[pa.argmin()], 'range', grid.min(), grid.max(), 'p at min', pa.min().round(5))
# the argmin must not depend on covariates (additive logit); check with a different base row
x2 = dv.iloc[[500]].copy()
pa2 = np.array([float(M.predict(x2.assign(hum=h, supplier_name='Alpha')).iloc[0]) for h in grid])
print('C2 check with another row:', grid[pa2.argmin()])
EOF
python3 $TMPDIR/work/final.py 2>/dev/null

cat > $TMPDIR/work/chk_c2.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','days_since_clean','hum']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
ctrl = 'mold_c + cycle_time_s + C(shift) + days_since_clean + s_L1 + s_L2 + s_L3 + C(line)'
grid = np.round(np.arange(12.1, 72.3, 0.1), 2)
def argmin_for(f, lab):
    M = smf.glm(f, data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit(scale='X2')
    x = d.iloc[[0]].copy()
    p = np.array([float(M.predict(x.assign(hum=h, supplier_name='Alpha')).iloc[0]) for h in grid])
    print(f'{lab:22s} argmin={grid[p.argmin()]:6.1f} scale={M.scale:.3f} dev={M.deviance:.1f}')
for df_ in [3,4,5,6,8]:
    argmin_for(f'rate ~ {ctrl} + C(supplier_name)*bs(hum, df={df_})', f'bs df={df_}')
argmin_for(f'rate ~ {ctrl} + C(supplier_name)*(hum + I(hum**2))', 'quad per supplier')
argmin_for(f'rate ~ {ctrl} + C(supplier_name)*hum + I(hum**2)', 'quad common')
EOF
python3 $TMPDIR/work/chk_c2.py 2>/dev/null

cat >> $TMPDIR/work/chk_c2.py <<'EOF'
print('--- flexible')
for df_ in [10,12]:
    argmin_for(f'rate ~ {ctrl} + C(supplier_name)*bs(hum, df={df_})', f'bs df={df_}')
d['hb'] = (d.hum//5*5).clip(lower=10)
M = smf.glm(f'rate ~ {ctrl} + C(supplier_name) + C(hb)', data=d, family=sm.families.Binomial(), var_weights=d.units_produced).fit(scale='X2')
print('binned 5pt (common shape) dev', round(M.deviance,1))
print(d.groupby('hb').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).round(4).to_dict())
EOF
python3 $TMPDIR/work/chk_c2.py 2>/dev/null | sed -n '/flexible/,$p'

cat > $TMPDIR/work/c2_alpha.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
d = r.dropna(subset=['mold_c','days_since_clean','hum']).copy()
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
a = d[d.supplier_name=='Alpha'].copy()
ctrl = 'mold_c + cycle_time_s + C(shift) + days_since_clean + s_L1 + s_L2 + s_L3 + C(line)'
for w in [5, 2.5]:
    a['hb'] = (a.hum//w*w)
    M = smf.glm(f'rate ~ {ctrl} + C(hb)', data=a, family=sm.families.Binomial(), var_weights=a.units_produced).fit(scale='X2')
    lv = sorted(a.hb.unique())
    coef = {lv[0]: 0.0}
    for k in lv[1:]:
        coef[k] = M.params[f'C(hb)[T.{k}]']
    s = pd.Series(coef).sort_index()
    print('width', w, 'bins', len(lv))
    print(pd.DataFrame({'n': a.groupby('hb').size(), 'rate_adj_logit': s}).round(3).to_string())
    print('argmin bin (lower edge):', s.idxmin())
EOF
python3 $TMPDIR/work/c2_alpha.py 2>/dev/null

cat >> $TMPDIR/work/c2_alpha.py <<'EOF'
print('--- Alpha-only quadratic')
M = smf.glm(f'rate ~ {ctrl} + hum + I(hum**2)', data=a, family=sm.families.Binomial(), var_weights=a.units_produced).fit(scale='X2')
b1, b2 = M.params['hum'], M.params['I(hum ** 2)']
print('vertex', round(-b1/(2*b2),2), 'b1', round(b1,5), 'b2', round(b2,6), 'p(b2)', round(M.pvalues['I(hum ** 2)'],4))
cov = M.cov_params().loc[['hum','I(hum ** 2)'],['hum','I(hum ** 2)']].values
g = np.array([-1/(2*b2), b1/(2*b2**2)])
se = np.sqrt(g @ cov @ g)
print('vertex SE (delta)', round(se,2))
print('Alpha-only cubic check:')
M3 = smf.glm(f'rate ~ {ctrl} + hum + I(hum**2) + I(hum**3)', data=a, family=sm.families.Binomial(), var_weights=a.units_produced).fit(scale='X2')
xs = np.arange(12.1, 72.3, 0.1)
p3 = M3.params
lin = np.array([p3['hum']*x + p3['I(hum ** 2)']*x**2 + p3['I(hum ** 3)']*x**3 for x in xs])
print('cubic argmin', round(xs[lin.argmin()],1))
EOF
python3 $TMPDIR/work/c2_alpha.py 2>/dev/null | sed -n '/Alpha-only quadratic/,$p'

cat > $TMPDIR/work/cf.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
r = r.copy()
r['s_L2'] = ((r.line=='L2')&(r.date>='2025-06-15')).astype(int)
r['s_L1'] = ((r.line=='L1')&(r.date>='2025-04-14')).astype(int)
r['s_L3'] = ((r.line=='L3')&(r.date>='2025-07-21')).astype(int)
fit = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
spl = 'C(supplier_name)*bs(hum, df=5)'
f = f'rate ~ mold_c + cycle_time_s + C(shift) + days_since_clean + {spl} + s_L1 + s_L2 + s_L3 + C(line)'
M = smf.glm(f, data=fit, family=sm.families.Binomial(), var_weights=fit.units_produced).fit(scale='X2')
print('fit rows', len(fit), 'scale', round(M.scale,3))
# model-implied vs observed total on fit rows
print('fit: observed rate', round(fit.defective_units.sum()/fit.units_produced.sum(),5), ' model rate', round((M.predict(fit)*fit.units_produced).sum()/fit.units_produced.sum(),5))
rng = np.random.default_rng(0)
K = 200
# expand all rows with K draws for missing mold / humidity from same-line empirical distributions
valid = r.dropna(subset=['mold_c','hum'])
rep = []
for i, row in r.iterrows():
    n = K if (pd.isna(row.mold_c) or pd.isna(row.hum)) else 1
    rep.append(n)
exp = r.loc[r.index.repeat(rep)].copy()
exp['w'] = 1.0 / np.repeat(rep, rep)
mc_pool = {ln: g.mold_c.dropna().values for ln, g in r.groupby('line')}
hm_pool = {ln: g.hum.dropna().values for ln, g in r.groupby('line')}
miss_m = exp.mold_c.isna().values; miss_h = exp.hum.isna().values
for ln in r.line.unique():
    idx = (exp.line==ln).values
    m1 = idx & miss_m
    exp.loc[m1, 'mold_c'] = rng.choice(mc_pool[ln], m1.sum())
    h1 = idx & miss_h
    exp.loc[h1, 'hum'] = rng.choice(hm_pool[ln], h1.sum())
exp['w'] = exp.w * exp.units_produced
exp['units'] = exp.units_produced
exp = exp.reset_index(drop=True)
exp.to_pickle(os.environ['TMPDIR']+'/work/exp.pkl')
M.save(os.environ['TMPDIR']+'/work/M.pickle')
print('expanded rows', len(exp), 'missing mold filled', miss_m.sum(), 'missing hum filled', miss_h.sum())
EOF
python3 $TMPDIR/work/cf.py 2>/dev/null

cat > $TMPDIR/work/cf2.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.genmod.families import Binomial
exp = pd.read_pickle(os.environ['TMPDIR']+'/work/exp.pkl')
M = sm.load(os.environ['TMPDIR']+'/work/M.pickle')
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
TOT_U = r.units_produced.sum(); TOT_D = r.defective_units.sum()
print('observed rate', TOT_D/TOT_U, TOT_D, TOT_U)
def pred(df):
    return np.asarray(M.predict(df))
# baseline model (expanded) vs observed
p0 = pred(exp)
print('baseline model-implied rate (expanded):', round((p0*exp.w).sum()/TOT_U, 5))
print('--- C1: single supplier, recipe cycle time of grade')
recipe = {'Alpha': 30, 'Beta': 30, 'Gamma': 36}
out = {}
for s, cyc in recipe.items():
    x = exp.copy(); x['supplier_name'] = s; x['cycle_time_s'] = cyc
    ps = pred(x)
    out[s] = (ps*x.w).sum()/TOT_U
    print(f'{s:6s} cycle={cyc}  rate={out[s]:.5f}')
print('best:', min(out, key=out.get))
print('--- C1 without changing cycle (supplier only)')
for s in recipe:
    x = exp.copy(); x['supplier_name'] = s
    print(s, round((pred(x)*x.w).sum()/TOT_U, 5))
print('--- C3: clean every 14 days (days -> days mod 14)')
x = exp.copy(); x['days_since_clean'] = x.days_since_clean % 14
p1 = pred(x)
new_model = (p1*exp.w).sum()/TOT_U
delta = ((p1-p0)*exp.w).sum()/TOT_U
print('model-only rate new:', round(new_model,5), ' observed+delta:', round(TOT_D/TOT_U + delta,5), ' delta', round(delta,5))
print('share of batches with days>=14:', round((r.days_since_clean>=14).mean(),3))
EOF
python3 $TMPDIR/work/cf2.py 2>/dev/null

cat > $TMPDIR/work/sens.py <<'EOF'
import os, pandas as pd, numpy as np
import statsmodels.formula.api as smf, statsmodels.api as sm
exp = pd.read_pickle(os.environ['TMPDIR']+'/work/exp.pkl')
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
TOT_U = r.units_produced.sum(); TOT_D = r.defective_units.sum()
fit = exp[exp.rep_ok] if 'rep_ok' in exp else None
base = exp.dropna(subset=['mold_c','hum','days_since_clean']).copy()
base = base.drop_duplicates(subset=['batch_id']) if False else base
fitrows = r.dropna(subset=['mold_c','hum','days_since_clean']).copy()
fitrows['s_L2'] = ((fitrows.line=='L2')&(fitrows.date>='2025-06-15')).astype(int)
fitrows['s_L1'] = ((fitrows.line=='L1')&(fitrows.date>='2025-04-14')).astype(int)
fitrows['s_L3'] = ((fitrows.line=='L3')&(fitrows.date>='2025-07-21')).astype(int)
for lab, dayspec in [('linear', 'days_since_clean'), ('bs4', 'bs(days_since_clean, df=4)'), ('cat', 'C(pd.cut(days_since_clean,[-1,3,7,10,14,20,40]))')]:
    f = f'rate ~ mold_c + cycle_time_s + C(shift) + {dayspec} + C(supplier_name)*bs(hum, df=5) + s_L1 + s_L2 + s_L3 + C(line)'
    M = smf.glm(f, data=fitrows, family=sm.families.Binomial(), var_weights=fitrows.units_produced).fit(scale='X2')
    x0 = exp.copy(); x1 = exp.copy(); x1['days_since_clean'] = x1.days_since_clean % 14
    p0 = np.asarray(M.predict(x0)); p1 = np.asarray(M.predict(x1))
    delta = ((p1-p0)*exp.w).sum()/TOT_U
    print(f'{lab:7s} C3 = {TOT_D/TOT_U + delta:.5f}  delta={delta:.5f}')
m = r.mold_c.dropna()
print('A4 median exact:', m.median(), 'n', len(m), 'ex-L3 check median raw F->C mix ok')
EOF
python3 $TMPDIR/work/sens.py 2>/dev/null

python3 - <<'EOF'
import os
import pandas as pd
r = pd.read_pickle(os.environ['TMPDIR']+'/work/df.pkl')
m = r.mold_c.dropna()
print('median as recorded (C-converted):', m.median(), len(m))
adj = r.mold_c.copy()
adj[(r.line=='L1')&(r.date>='2025-04-14')] -= 6.2
print('median if L1 post-sensor offset -6.2 C removed:', round(adj.dropna().median(),2))
EOF
