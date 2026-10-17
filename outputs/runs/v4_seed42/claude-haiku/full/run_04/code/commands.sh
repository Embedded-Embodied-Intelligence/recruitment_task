ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/profile.py <<'EOF'
import pandas as pd
pd.set_option('display.width', 200); pd.set_option('display.max_columns', 30)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc = b[c].value_counts()
    print(f"\n--- {c}: nunique={b[c].nunique()} empty={(b[c].str.strip()=='').sum()}")
    if b[c].nunique() < 40: print(vc.to_string())
    else: print(b[c].sample(8, random_state=1).tolist())
print("\nduplicated batch_id rows:", b.duplicated('batch_id', keep=False).sum())
print("full duplicated rows:", b.duplicated(keep='first').sum())
print(b[b.duplicated('batch_id', keep=False)].sort_values('batch_id').head(20).to_string())
EOF
python3 $TMPDIR/profile.py

cat > $TMPDIR/profile2.py <<'EOF'
import pandas as pd, re
pd.set_option('display.width', 200)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
bn = b.copy()
for c in num:
    bn[c] = pd.to_numeric(bn[c].str.strip(), errors='coerce')
    bad = b[c][bn[c].isna()]
    print(c, 'non-numeric/blank:', bad.unique()[:10], len(bad))
    print(bn[c].describe().round(2).to_dict())
# date formats
pat = b.production_date.str.replace(r'\d','9',regex=True)
print(pat.value_counts())
# ambiguous slash dates
sl = b.production_date[b.production_date.str.contains('/')]
parts = sl.str.split('/', expand=True).astype(int)
print('first>12:', (parts[0]>12).sum(), 'second>12:', (parts[1]>12).sum(), 'both<=12:', ((parts[0]<=12)&(parts[1]<=12)).sum())
# suspicious rows
print('units<=0', (bn.units_produced<=0).sum(), 'defect>units', (bn.defective_units>bn.units_produced).sum(), 'defect<0', (bn.defective_units<0).sum())
print('humidity values sorted extremes:', sorted(bn.humidity_pct.dropna().unique())[:8], sorted(bn.humidity_pct.dropna().unique())[-8:])
print('mold_temp > 300 count', (bn.mold_temp>300).sum(), 'values', sorted(bn.mold_temp.dropna().unique())[-15:])
print('mold_temp < 150 count', (bn.mold_temp<150).sum(), sorted(bn.mold_temp.dropna().unique())[:10])
print('cycle_time sorted', sorted(bn.cycle_time_s.unique())[:5], sorted(bn.cycle_time_s.unique())[-5:])
print('ambient', sorted(bn.ambient_temp_c.unique())[:5], sorted(bn.ambient_temp_c.unique())[-5:])
print('machine_age', sorted(bn.machine_age_years.unique())[:5], sorted(bn.machine_age_years.unique())[-5:])
print('qc', sorted(bn.qc_inspection_min.unique())[:5], sorted(bn.qc_inspection_min.unique())[-5:])
print(b.line.unique(), b.operator_id.unique())
EOF
python3 $TMPDIR/profile2.py

cat > $TMPDIR/profile3.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 200)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
b['mt'] = pd.to_numeric(b.mold_temp, errors='coerce')
b['hum'] = pd.to_numeric(b.humidity_pct.replace('', np.nan), errors='coerce')
b['F'] = b.mt > 300
print(pd.crosstab(b.line, b.F))
print('mold_temp histogram (C-range):')
print(np.histogram(b.mt[(b.mt>150)&(b.mt<=300)], bins=15))
print(np.histogram(b.mt[b.mt>300], bins=12))
print('zeros/low:', b[b.mt<150][['batch_id','line','production_date','mold_temp']].to_string())
print('hum neg:', (b.hum<0).sum(), 'hum zero', (b.hum==0).sum(), 'hum>=0 min', b.hum[b.hum>=0].min())
print('hum outliers high', b.hum[b.hum>70].tolist())
# date format vs row order
b['fmt'] = np.where(b.production_date.str.contains('-'), 'iso', 'slash')
print(b.fmt.value_counts())
print(b.groupby('line').fmt.value_counts().unstack())
print(b.head(30)[['batch_id','production_date','line','fmt','mt']].to_string())
EOF
python3 $TMPDIR/profile3.py

cat > $TMPDIR/profile4.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 200)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
s = b[b.production_date.str.contains('/')].copy()
p = s.production_date.str.split('/', expand=True).astype(int)
s['a']=p[0]; s['b']=p[1]
for ln, g in s.groupby('line'):
    print(ln, 'first>12', (g.a>12).sum(), 'second>12', (g.b>12).sum(), 'ambig', ((g.a<=12)&(g.b<=12)).sum())
print('L3 non-F readings:')
b['mt']=pd.to_numeric(b.mold_temp, errors='coerce')
print(b[(b.line=='L3')&(b.mt<=300)][['batch_id','production_date','shift','mold_temp']].to_string())
print('mold_temp L3 converted vs others (C):')
l3 = b[(b.line=='L3')&(b.mt>300)].mt
print(((l3-32)*5/9).describe().round(2).to_dict())
print(b[b.line!='L3'].mt[b.mt>0].describe().round(2).to_dict())
print('zeros count', (b.mt==0).sum())
print('L3 ISO dates range sample', b[b.line=='L3'].production_date.head(3).tolist())
EOF
python3 $TMPDIR/profile4.py; echo ----; cat maintenance.csv | head -80; cat suppliers.csv

cat > $TMPDIR/clean.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 220); pd.set_option('display.max_columns', 40)
raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
raw = raw.apply(lambda c: c.str.strip())
df = raw.drop_duplicates().copy()
assert df.batch_id.is_unique, 'conflicting duplicate batch ids'

def parse_date(r):
    s = r.production_date
    if '-' in s:
        return pd.Timestamp(s)
    a, b_, y = map(int, s.split('/'))
    if r.line == 'L1':   # MM/DD/YYYY
        return pd.Timestamp(y, a, b_)
    if r.line == 'L4':   # DD/MM/YYYY
        return pd.Timestamp(y, b_, a)
    raise ValueError(s)
df['date'] = df.apply(parse_date, axis=1)

sm = {'d':'Day','day':'Day','n':'Night','night':'Night'}
df['shift'] = df['shift'].str.lower().map(sm)
assert df['shift'].notna().all()
df['supplier_code'] = df.supplier_code.str.upper()
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s',
       'units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    df[c] = pd.to_numeric(df[c].replace('', np.nan), errors='coerce')
df.loc[df.humidity_pct < 0, 'humidity_pct'] = np.nan
df.loc[df.mold_temp == 0, 'mold_temp'] = np.nan
f = df.line.eq('L3') & (df.mold_temp > 300)
df.loc[f, 'mold_temp'] = (df.loc[f, 'mold_temp'] - 32) * 5 / 9
df['defect_rate'] = df.defective_units / df.units_produced
df = df.merge(pd.read_csv('suppliers.csv', dtype=str).assign(supplier_code=lambda x: x.supplier_code.str.upper()), on='supplier_code', how='left')
assert df.supplier_name.notna().all()
df.to_pickle(f'{__import__("os").environ["TMPDIR"]}/clean.pkl')
print(df.shape, df.batch_id.nunique())
print(df.date.min(), df.date.max())
print(df.groupby('line').date.agg(['min','max']))
EOF
python3 $TMPDIR/clean.py

cat > $TMPDIR/explore1.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 220); pd.set_option('display.max_columns', 40)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
print('A2 missing humidity (unique):', df.humidity_pct.isna().sum())
print('A3 overall defect rate:', df.defective_units.sum()/df.units_produced.sum())
print('A4 median mold temp:', df.mold_temp.median(), df.mold_temp.notna().sum())
# leakage check
print(df[['defective_units','units_produced','defect_rate','qc_inspection_min','rework_cost_eur']].corr().round(3))
df['rw_per_def'] = df.rework_cost_eur/df.defective_units
print(df.rw_per_def.describe().round(3).to_dict())
# L1 mold temp by period
df['post'] = df.date >= '2025-04-14'
print(df.groupby(['line','post']).mold_temp.agg(['median','mean','count']).round(2))
print(df.groupby(['line','post']).defect_rate.mean().round(4))
EOF
python3 $TMPDIR/explore1.py

cat > $TMPDIR/explore2.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 40); pd.set_option('display.max_rows', 200)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
df['month'] = df.date.dt.to_period('M')
print(df.pivot_table(index='month', columns='line', values='mold_temp', aggfunc='median').round(1))
print(df.pivot_table(index='month', columns='line', values='ambient_temp_c', aggfunc='median').round(1))
print(df.pivot_table(index='month', columns='line', values='defect_rate', aggfunc='mean').round(4))
print(df.pivot_table(index='month', columns='line', values='humidity_pct', aggfunc='median').round(1))
print(df.pivot_table(index='month', columns='line', values='batch_id', aggfunc='count'))
EOF
python3 $TMPDIR/explore2.py

python3 -c "import statsmodels, scipy, sklearn; print(statsmodels.__version__, scipy.__version__, sklearn.__version__)" 2>&1; python3 -c "import pandas; print(pandas.__version__)"

python3 -c "import statsmodels, scipy; print(statsmodels.__version__, scipy.__version__)" 2>&1; pip install -q statsmodels scipy 2>&1 | tail -2; python3 -c "import statsmodels, scipy; print(statsmodels.__version__, scipy.__version__)"

cat > $TMPDIR/model1.py <<'EOF'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
import statsmodels.api as sm
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 40)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['fail'] = d.units_produced - d.defective_units
# leakage check on qc time
for f in ['qc_inspection_min ~ defective_units', 'qc_inspection_min ~ defective_units + units_produced',
          'qc_inspection_min ~ defective_units + units_produced + C(line)+C(shift)+C(supplier_name)+mold_temp+humidity_pct+cycle_time_s+ambient_temp_c+machine_age_years']:
    m = smf.ols(f, data=df).fit(); print(f, 'R2=', round(m.rsquared,3))
print(smf.ols('qc_inspection_min ~ defective_units', data=df).fit().params.round(4))
print('cycle vs recipe diff:', (df.cycle_time_s - df.recipe_cycle_time_s).describe().round(2).to_dict())
print(df.groupby('supplier_name').cycle_time_s.mean().round(2))
m = smf.glm('defective_units + fail ~ C(line) + C(supplier_name) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift)', data=d, family=sm.families.Binomial()).fit()
print(m.summary().tables[1])
EOF
python3 $TMPDIR/model1.py 2>&1 | head -150

sed -i "s/df = pd.read_pickle(f'{os.environ\[\"TMPDIR\"\]}\/clean.pkl')/df = pd.read_pickle(f'{os.environ[\"TMPDIR\"]}\/clean.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)/" $TMPDIR/model1.py && python3 $TMPDIR/model1.py 2>&1 | head -150

cat > $TMPDIR/sensor.py <<'EOF'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
pd.set_option('display.width', 250)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
df['post'] = (df.date >= '2025-04-14').astype(int)
df['L1post'] = ((df.line=='L1')&(df.post==1)).astype(int)
d = df.dropna(subset=['mold_temp'])
print(smf.ols('mold_temp ~ ambient_temp_c + C(line) + L1post', data=d).fit().summary().tables[1])
print(smf.ols('mold_temp ~ ambient_temp_c + C(line) + C(supplier_name) + cycle_time_s + C(shift) + C(line):post', data=d).fit().summary().tables[1])
print('correlations:'); print(df[['ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','machine_age_years','units_produced']].corr().round(3))
print(df.groupby('supplier_name')[['humidity_pct','ambient_temp_c','mold_temp']].mean().round(2))
print(df.groupby('shift')[['mold_temp','humidity_pct','cycle_time_s','defect_rate']].mean().round(4))
EOF
python3 $TMPDIR/sensor.py

cat > $TMPDIR/resid.py <<'EOF'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
d = df.dropna(subset=['mold_temp']).copy()
m = smf.ols('mold_temp ~ ambient_temp_c + C(line)', data=d).fit()
d['res'] = m.resid
d['month'] = d.date.dt.to_period('M')
print(d.pivot_table(index='month', columns='line', values='res', aggfunc='mean').round(2))
# L3 raw F-check: compare L3 F-converted vs C for same ambient bins
d['amb_bin'] = pd.cut(d.ambient_temp_c, [10,15,20,25,31])
print(d.pivot_table(index='amb_bin', columns='line', values='mold_temp', aggfunc='mean').round(2))
print(d.pivot_table(index='amb_bin', columns='line', values='mold_temp', aggfunc='count'))
EOF
python3 $TMPDIR/resid.py

cat > $TMPDIR/sensor2.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
d = df.dropna(subset=['mold_temp']).copy()
d['period'] = np.where(d.date < '2025-04-14', 'pre', 'post')
d['amb_bin'] = pd.cut(d.ambient_temp_c, [10,14,18,22,26,31])
for p in ['pre','post']:
    x = d[d.period==p]
    t = x.pivot_table(index='amb_bin', columns='line', values='mold_temp', aggfunc='mean').round(2)
    n = x.pivot_table(index='amb_bin', columns='line', values='mold_temp', aggfunc='count')
    print(p); print(t); print(n)
# regression on ambient bins with line effect within period
import statsmodels.formula.api as smf
for p in ['pre','post']:
    x = d[d.period==p]
    m = smf.ols('mold_temp ~ C(amb_bin) + C(line)', data=x).fit()
    print(p, m.params.filter(like='line').round(2).to_dict(), 'n', len(x))
EOF
python3 $TMPDIR/sensor2.py

cat > $TMPDIR/age.py <<'EOF'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 200)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
df['month'] = df.date.dt.to_period('M')
print(df.pivot_table(index='month', columns='line', values='machine_age_years', aggfunc='mean').round(2))
print(df.groupby('line').machine_age_years.describe().round(2))
d = df.dropna(subset=['mold_temp']).copy(); d['post']=(d.date>='2025-04-14').astype(int)
d['L1post']=((d.line=='L1')&(d.post==1)).astype(int)
print(smf.ols('mold_temp ~ ambient_temp_c + machine_age_years + C(line) + L1post', data=d).fit().summary().tables[1])
EOF
python3 $TMPDIR/age.py

cat > $TMPDIR/sensor3.py <<'EOF'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf
pd.set_option('display.width', 250)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl')
d = df.dropna(subset=['mold_temp']).copy()
d['post']=(d.date>='2025-04-14').astype(int)
d['L1post']=((d.line=='L1')&(d.post==1)).astype(int)
d['L3post']=((d.line=='L3')&(d.post==1)).astype(int)
d['L3']=(d.line=='L3').astype(int)
d['amb_fine']=pd.cut(d.ambient_temp_c, np.arange(10,32,1.0)).astype(str)
m = smf.ols('mold_temp ~ C(amb_fine) + C(line) + L1post', data=d).fit()
print('bins+line+L1post:', m.params[['C(line)[T.L2]','C(line)[T.L3]','C(line)[T.L4]','L1post']].round(2).to_dict(), 'resid sd', round(np.sqrt(m.scale),2))
m2 = smf.ols('mold_temp ~ C(amb_fine) + C(line) + L1post + L3post', data=d).fit()
print('with L3post:', m2.params[['C(line)[T.L2]','C(line)[T.L3]','C(line)[T.L4]','L1post','L3post']].round(2).to_dict(), m2.pvalues[['L1post','L3post']].round(4).to_dict())
# does L3 have a post-shift? compare L3 vs L2/L4 by period
m3 = smf.ols('mold_temp ~ C(amb_fine) + C(line)*post', data=d[d.line!='L1']).fit()
print('L3 post interaction:', m3.params.filter(like='post').round(2).to_dict(), m3.pvalues.filter(like='post').round(4).to_dict())
# within post, L1 offset vs L2/L4
dd = d[d.line.isin(['L2','L4'])]
mm = smf.ols('mold_temp ~ C(amb_fine) + C(line)', data=pd.concat([dd, d[d.line=='L1'][d.post==1]])).fit()
print('L1 post offset vs L2/L4 with bins:', round(mm.params.get('C(line)[T.L1]', np.nan),2) if 'C(line)[T.L1]' in mm.params else mm.params.filter(like='line').round(2).to_dict())
EOF
python3 $TMPDIR/sensor3.py 2>&1 | grep -v Warning | grep -v wls

cat > $TMPDIR/changept.py <<'EOF'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
df = pd.read_pickle(f'{os.environ["TMPDIR"]}/clean.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
# mold temp change dates per line: scan split date for step in mold residual (after ambient flexible), per line
d = df.dropna(subset=['mold_temp']).copy()
d['amb_fine']=pd.cut(d.ambient_temp_c, np.arange(10,32,1.0)).astype(str)
base = smf.ols('mold_temp ~ C(amb_fine) + C(line)', data=d).fit()
d['mres']=base.resid
for ln in ['L1','L2','L3','L4']:
    x = d[d.line==ln].sort_values('date')
    best=None
    for dt in pd.date_range('2025-02-01','2025-08-15'):
        a = x[x.date<dt].mres; b=x[x.date>=dt].mres
        if len(a)<30 or len(b)<30: continue
        sse = ((a-a.mean())**2).sum()+((b-b.mean())**2).sum()
        if best is None or sse<best[0]: best=(sse,dt,b.mean()-a.mean(),len(a),len(b))
    print('mold step', ln, best[1].date(), 'shift', round(best[2],2), 'n', best[3], best[4])
# defect residual scan using process vars w/o line & time
d2 = df.dropna(subset=['humidity_pct','mold_temp']).copy(); d2['fail']=d2.units_produced-d2.defective_units
g = smf.glm('defective_units + fail ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift) + C(operator_id) + C(supplier_name) + machine_age_years', data=d2, family=sm.families.Binomial()).fit()
d2['pred']=g.predict(d2)
d2['obs']=d2.defective_units/d2.units_produced
d2['resid']=d2.defective_units - d2.pred*d2.units_produced
def scan(x, label):
    x=x.sort_values('date'); best=None
    ys=x.defective_units.values; ns=x.units_produced.values; ps=x.pred.values
    for dt in pd.date_range('2025-02-01','2025-08-31'):
        m = (x.date<dt).values
        if m.sum()<60 or (~m).sum()<60: continue
        ll=0
        for mask in [m,~m]:
            p = ys[mask].sum()/ns[mask].sum()
            ll += (ys[mask]*np.log(p/ps[mask]*0+1e-12+ (ps[mask]/ps[mask]) )).sum()*0
        # compare observed rate in each segment to fitted expected rate, chi2-like
        o1,e1 = ys[m].sum(), (ps[m]*ns[m]).sum(); o2,e2=ys[~m].sum(), (ps[~m]*ns[~m]).sum()
        stat = (o1-e1)**2/e1 + (o2-e2)**2/e2
        if best is None or stat>best[0]: best=(stat,dt.date(),round(o1/e1,3),round(o2/e2,3))
    print(label, best)
for ln in ['L1','L2','L3','L4']:
    scan(d2[d2.line==ln], ln)
print('overall ratio obs/exp by line:'); print(d2.groupby('line').apply(lambda x: round(x.defective_units.sum()/(x.pred*x.units_produced).sum(),3)))
EOF
python3 $TMPDIR/changept.py 2>&1 | grep -v -i warn

cat > $TMPDIR/clean_days.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean.pkl')
mt = pd.read_csv('maintenance.csv', dtype=str).apply(lambda c: c.str.strip())
mt['date']=pd.to_datetime(mt.date)
print(mt.event.value_counts())
cl = mt[mt.event=='mold_cleaning'][['line','date']]
def days_since(r):
    c = cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date - c.max()).days if len(c) else np.nan
df['days_since_clean'] = df.apply(days_since, axis=1)
print(df.days_since_clean.describe().round(2))
print('missing', df.days_since_clean.isna().sum())
print(df.groupby('line').days_since_clean.describe().round(1))
# how many batches exceed 14 days, per line
print('>14 days share by line:', df.assign(o=df.days_since_clean>14).groupby('line').o.mean().round(3).to_dict())
df.to_pickle(f'{T}/clean2.pkl')
EOF
python3 $TMPDIR/clean_days.py

cat > $TMPDIR/model2.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy(); d['fail']=d.units_produced-d.defective_units
for f in ['defective_units + fail ~ C(line) + C(supplier_name) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + days_since_clean',
          'defective_units + fail ~ C(line) + C(supplier_name) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + days_since_clean + I(days_since_clean**2)']:
    g = smf.glm(f, data=d, family=sm.families.Binomial()).fit()
    print(g.params.filter(regex='^(?!C\\(operator)').round(4).to_string()); print('AIC', round(g.aic,1))
# binned days since cleaning effect
d['dbin']=pd.cut(d.days_since_clean,[-1,3,7,10,14,21,40])
print(d.groupby('dbin').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).round(4))
EOF
python3 $TMPDIR/model2.py

cat > $TMPDIR/rank.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
import patsy
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
X = patsy.dmatrix('C(line) + C(supplier_name) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + days_since_clean', d, return_type='dataframe')
print(X.shape, np.linalg.matrix_rank(X.values))
print(X.columns[np.linalg.svd(X.values, full_matrices=False)[2][-3:].argmax()] if False else '')
u,s,vt = np.linalg.svd(X.values, full_matrices=False)
print('smallest sing vals', s[-4:])
print('collinear col pairs:', [X.columns[i] for i in np.argsort(-np.abs(vt[-1]))[:5]])
print(pd.crosstab(d.supplier_name, d.line))
print(d.operator_id.value_counts().min(), d.groupby('line').operator_id.nunique().to_dict())
EOF
python3 $TMPDIR/rank.py

cat > $TMPDIR/scan2.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy(); d['fail']=d.units_produced-d.defective_units
g = smf.glm('defective_units + fail ~ C(line) + C(supplier_name) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + C(operator_id)', data=d, family=sm.families.Binomial()).fit()
d['pred']=g.predict(d)
def scan(x, label):
    x=x.sort_values('date'); best=None
    ys=x.defective_units.values; ns=x.units_produced.values; ps=x.pred.values
    dates = x.date.values
    for dt in pd.date_range('2025-02-01','2025-08-31'):
        m = dates < np.datetime64(dt)
        if m.sum()<60 or (~m).sum()<60: continue
        o1,e1 = ys[m].sum(), (ps[m]*ns[m]).sum(); o2,e2=ys[~m].sum(), (ps[~m]*ns[~m]).sum()
        stat = (o1-e1)**2/e1 + (o2-e2)**2/e2
        if best is None or stat>best[0]: best=(round(stat,1),dt.date(),round(o1/e1,3),round(o2/e2,3))
    print(label, best)
for ln in ['L1','L2','L3','L4']:
    scan(d[d.line==ln], ln)
# also check whole-plant pooled defect residual per month
d['month']=d.date.dt.to_period('M')
print(d.groupby(['line','month']).apply(lambda x: round(x.defective_units.sum()/(x.pred*x.units_produced).sum(),3)).unstack(0))
EOF
python3 $TMPDIR/scan2.py

cat > $TMPDIR/rawshift.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
def seg(ln, dt):
    x = df[df.line==ln].copy(); x['post']=x.date>=pd.Timestamp(dt)
    return x.groupby('post').agg(n=('batch_id','count'), units=('units_produced','mean'), defects=('defective_units','mean'),
        rate=('defect_rate','mean'), wrate=('defective_units', 'sum')).assign(
        wrate=lambda t: t.wrate/ x.groupby('post').units_produced.sum().values,
        mold=x.groupby('post').mold_temp.mean().values, hum=x.groupby('post').humidity_pct.mean().values,
        cyc=x.groupby('post').cycle_time_s.mean().values, dsc=x.groupby('post').days_since_clean.mean().values,
        shiftNight=x.groupby('post').shift.apply(lambda s:(s=='Night').mean()).values,
        sup=x.groupby('post').supplier_name.apply(lambda s: s.value_counts(normalize=True).round(2).to_dict()).values)
print('L2 @2025-06-15'); print(seg('L2','2025-06-15').round(4).to_string())
print('L3 @2025-07-21'); print(seg('L3','2025-07-21').round(4).to_string())
print('L1 @2025-04-12'); print(seg('L1','2025-04-12').round(4).to_string())
EOF
python3 $TMPDIR/rawshift.py

cat > $TMPDIR/rawshift.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
def seg(ln, dt):
    x = df[df.line==ln].copy(); x['post']=x.date>=pd.Timestamp(dt)
    out = {}
    for p,g in x.groupby('post'):
        out[('post' if p else 'pre')] = dict(n=len(g), units_mean=g.units_produced.mean(), def_mean=g.defective_units.mean(),
            pooled_rate=g.defective_units.sum()/g.units_produced.sum(), mold=g.mold_temp.mean(), hum=g.humidity_pct.mean(),
            cycle=g.cycle_time_s.mean(), dsc=g.days_since_clean.mean(), night=(g['shift']=='Night').mean(),
            alpha=(g.supplier_name=='Alpha').mean(), beta=(g.supplier_name=='Beta').mean(), gamma=(g.supplier_name=='Gamma').mean(),
            qc=g.qc_inspection_min.mean(), age=g.machine_age_years.mean(), amb=g.ambient_temp_c.mean())
    return pd.DataFrame(out).round(4)
print('L2 @2025-06-15'); print(seg('L2','2025-06-15').to_string())
print('L3 @2025-07-21'); print(seg('L3','2025-07-21').to_string())
print('L1 @2025-04-12'); print(seg('L1','2025-04-12').to_string())
EOF
python3 $TMPDIR/rawshift.py

cat > $TMPDIR/l2check.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
df['dbin']=pd.cut(df.days_since_clean,[-1,3,7,10,14,21,40])
for ln, dt in [('L2','2025-06-15'),('L3','2025-07-21')]:
    x=df[df.line==ln].copy(); x['post']=x.date>=pd.Timestamp(dt)
    t=x.groupby(['dbin','post'], observed=True).apply(lambda g: pd.Series({'rate':g.defective_units.sum()/g.units_produced.sum(),'n':len(g)})).unstack()
    print(ln, dt); print(t.round(4))
# also check qc vs defect link within L1 pre-period
x=df[(df.line=='L1')&(df.date<'2025-04-12')]
print('L1 pre qc~defects slope', np.polyfit(x.defective_units, x.qc_inspection_min, 1).round(4), 'corr', round(np.corrcoef(x.defective_units,x.qc_inspection_min)[0,1],3))
EOF
python3 $TMPDIR/l2check.py

cat > $TMPDIR/ambcheck.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
df['abin']=pd.cut(df.ambient_temp_c,[10,15,18,21,24,27,31])
df['per']=np.where(df.date>=pd.Timestamp('2025-06-15'),'post06-15','pre')
t = df.groupby(['line','abin','per'], observed=True).apply(lambda g: pd.Series({'rate':round(g.defective_units.sum()/g.units_produced.sum(),4),'n':len(g)})).unstack('per')
print(t.to_string())
EOF
python3 $TMPDIR/ambcheck.py

cat > $TMPDIR/l2daily.py <<'EOF'
import pandas as pd, numpy as np, os
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
x = df[(df.line=='L2')].sort_values(['date','batch_id'])
g = x.groupby('date').agg(n=('batch_id','count'), defects=('defective_units','sum'), units=('units_produced','sum'), dsc=('days_since_clean','mean'), amb=('ambient_temp_c','mean'))
g['rate']=(g.defects/g.units).round(4)
print(g.loc['2025-05-25':'2025-07-05'].to_string())
# cumulative: per-batch rate before/after scan over dates in June
best=None
dates = x.date.values
ys=x.defective_units.values; ns=x.units_produced.values
import pandas as pd
for dt in pd.date_range('2025-05-15','2025-07-15'):
    m = dates < np.datetime64(dt)
    if m.sum()<30 or (~m).sum()<30: continue
    p1=ys[m].sum()/ns[m].sum(); p2=ys[~m].sum()/ns[~m].sum()
    ll = (ys[m]*np.log(p1)+(ns[m]-ys[m])*np.log(1-p1)).sum() + (ys[~m]*np.log(p2)+(ns[~m]-ys[~m])*np.log(1-p2)).sum()
    if best is None or ll>best[0]: best=(ll,dt.date(),round(p1,4),round(p2,4))
print('best binomial split on L2 (raw rate):', best)
EOF
python3 $TMPDIR/l2daily.py

cat > $TMPDIR/direct.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy(); d['fail']=d.units_produced-d.defective_units
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
F='defective_units + fail ~ '
def fit(form, data, label):
    g = smf.glm(F+form, data=data, family=sm.families.Binomial()).fit(disp=0)
    keep=[k for k in g.params.index if not k.startswith('C(operator') and not k.startswith('C(line')]
    print(label, {k:(round(g.params[k],4), round(g.pvalues[k],4)) for k in keep if k!='Intercept'})
fit('mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(operator_id) + C(line) + days_since_clean', d, 'ALL:')
fit('mold_temp + humidity_pct + cycle_time_s + C(shift) + C(operator_id) + C(line) + days_since_clean', d, 'no ambient:')
for ln in ['L2','L4']:
    fit('mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + machine_age_years + C(shift) + C(operator_id) + days_since_clean', d[d.line==ln], ln+' only:')
# machine age within line (line fixed effect via C(line) above). Check age range within line
print(d.groupby('line').machine_age_years.agg(['min','max','std']).round(2))
EOF
python3 $TMPDIR/direct.py

cat > $TMPDIR/direct2.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy(); d['fail']=d.units_produced-d.defective_units
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
F='defective_units + fail ~ '
def fit(form, data, label):
    g = smf.glm(F+form, data=data, family=sm.families.Binomial()).fit(disp=0)
    keep=[k for k in g.params.index if not k.startswith('C(operator') and not k.startswith('C(line') and k!='Intercept']
    print(label, {k:(round(g.params[k],4), round(g.pvalues[k],4)) for k in keep}, 'AIC', round(g.aic,1))
    return g
base='mold_c + humidity_pct + cycle_time_s + machine_age_years + C(shift) + C(operator_id) + C(line) + days_since_clean + L2post + L3post'
fit(base+' + ambient_temp_c', d, 'ALL corrected+dummies:')
fit(base, d, 'no ambient:')
fit(base.replace('mold_c','mold_temp')+' + ambient_temp_c', d, 'uncorrected mold, ambient:')
fit(base.replace('mold_c','mold_temp')+' + L1post', d, 'uncorrected mold + L1post:')
EOF
python3 $TMPDIR/direct2.py

cat > $TMPDIR/lrt.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy(); d['fail']=d.units_produced-d.defective_units
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
F='defective_units + fail ~ '
full_terms = ['mold_c','humidity_pct','cycle_time_s','machine_age_years','C(shift)','C(operator_id)','C(line)','days_since_clean','L2post','L3post','ambient_temp_c']
def fit(terms):
    return smf.glm(F+' + '.join(terms), data=d, family=sm.families.Binomial()).fit(disp=0)
full = fit(full_terms)
print('full AIC', round(full.aic,1), 'deviance', round(full.deviance,1))
for t in ['mold_c','humidity_pct','cycle_time_s','machine_age_years','C(shift)','C(operator_id)','days_since_clean','ambient_temp_c','C(line)']:
    red = fit([x for x in full_terms if x!=t])
    lr = 2*(red.llf-full.llf)
    df_ = full.df_model - red.df_model
    print(f'drop {t:20s} LR={lr:8.2f} df={df_:.0f} p={stats.chi2.sf(lr, df_):.4g}')
# machine age within each line
for ln in ['L1','L2','L3','L4']:
    x = d[d.line==ln]
    g = smf.glm(F+'mold_c + humidity_pct + cycle_time_s + machine_age_years + C(shift) + C(operator_id) + days_since_clean + L2post + L3post', data=x, family=sm.families.Binomial()).fit(disp=0)
    print(ln, 'age coef', round(g.params['machine_age_years'],4), 'p', round(g.pvalues['machine_age_years'],4))
EOF
python3 $TMPDIR/lrt.py

cat > $TMPDIR/lrt2.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
print('operator nested in line:', d.groupby('operator_id').line.nunique().max())
print('machine age within operator (std mean):', d.groupby(['line','operator_id']).machine_age_years.std().mean().round(3))
print('machine age by line-operator mean sample:'); print(d.groupby(['line','operator_id']).machine_age_years.mean().round(2).unstack(0).head(6))
def fit(terms, data=d):
    return smf.glm('rate ~ ' + ' + '.join(terms), data=data, family=sm.families.Binomial(), freq_weights=data.units_produced).fit()
full_terms = ['mold_c','humidity_pct','cycle_time_s','machine_age_years','C(shift)','C(operator_id)','days_since_clean','L2post','L3post','ambient_temp_c']
full = fit(full_terms)
print('full AIC', round(full.aic,1), 'df', full.df_model)
for t in ['mold_c','humidity_pct','cycle_time_s','machine_age_years','C(shift)','C(operator_id)','days_since_clean','ambient_temp_c']:
    red = fit([x for x in full_terms if x!=t])
    lr = 2*(full.llf-red.llf); dfd = full.df_model-red.df_model
    print(f'drop {t:20s} LR={lr:9.2f} df={dfd:.0f} p={stats.chi2.sf(lr, dfd):.4g}')
g = full
print(g.params[[k for k in g.params.index if not 'operator' in k]].round(4).to_string())
EOF
python3 $TMPDIR/lrt2.py

cat > $TMPDIR/age2.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
x = df[df.operator_id=='OP-01'].sort_values('date')
print(x[['date','machine_age_years','defect_rate']].head(15).to_string())
print('distinct ages for OP-01:', x.machine_age_years.nunique(), 'of', len(x))
print('L4 op ages:', df[df.line=='L4'].groupby('operator_id').machine_age_years.agg(['mean','std']).round(2).head(6).to_string())
# age vs time trend within line
for ln in ['L1','L2','L3','L4']:
    y=df[df.line==ln]
    print(ln, 'corr(age, day)', round(np.corrcoef(y.machine_age_years, y.date.astype('int64'))[0,1],3), 'corr(age,dsc)', round(np.corrcoef(y.machine_age_years, y.days_since_clean)[0,1],3))
EOF
python3 $TMPDIR/age2.py

cat > $TMPDIR/age3.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
base = 'mold_c + humidity_pct + cycle_time_s + C(shift) + C(operator_id) + days_since_clean + L2post + L3post'
def fit(f): return smf.glm('rate ~ '+f, data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
m0 = fit(base); m1 = fit(base+' + machine_age_years'); m2 = fit(base+' + machine_age_years*C(line)')
m3 = fit(base+' + C(pd.cut(machine_age_years,[0,3,5,7,10,25]))')
for lab,m,mm in [('age linear vs none', m1, m0), ('age x line vs linear', m2, m1), ('age bins vs none', m3, m0)]:
    lr=2*(m.llf-mm.llf); dfd=m.df_model-mm.df_model
    print(lab, round(lr,2), dfd, round(stats.chi2.sf(lr,dfd),4))
print(m2.params.filter(like='machine_age').round(4).to_string())
print('within-line age effect on rate, sd(age within operator)', round(d.groupby('operator_id').machine_age_years.std().mean(),2))
EOF
python3 $TMPDIR/age3.py

cat > $TMPDIR/age4.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
flex = 'bs(mold_c, df=5) + bs(humidity_pct, df=4) + bs(cycle_time_s, df=4) + bs(days_since_clean, df=4) + C(shift) + C(operator_id) + L2post + L3post'
def fit(f): return smf.glm('rate ~ '+f, data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
m0 = fit(flex)
m1 = fit(flex+' + machine_age_years')
m2 = fit(flex+' + machine_age_years*C(operator_id)'.replace('*C(operator_id)',''))  # placeholder
lr=2*(m1.llf-m0.llf); print('flex: age linear LR', round(lr,2), 'p', round(stats.chi2.sf(lr,1),4), 'coef', round(m1.params['machine_age_years'],4))
m3 = fit(flex+' + machine_age_years*C(line)') if False else None
d['L4']=(d.line=='L4').astype(int)
m3 = fit(flex+' + machine_age_years + machine_age_years:L4')
lr=2*(m3.llf-m1.llf); print('flex: age x L4 LR', round(lr,2), 'p', round(stats.chi2.sf(lr,1),4), 'slope nonL4', round(m3.params['machine_age_years'],4), 'extra L4', round(m3.params['machine_age_years:L4'],4))
EOF
python3 $TMPDIR/age4.py 2>&1 | grep -v -i warn

cat > $TMPDIR/hum.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
base='C(shift) + C(operator_id) + days_since_clean + L2post + L3post + mold_c'
def fit(f, data=d): return smf.glm('rate ~ '+f, data=data, family=sm.families.Binomial(), freq_weights=data.units_produced).fit()
# cycle: absolute vs deviation vs both
ma=fit(base+' + cycle_time_s + humidity_pct + C(supplier_name)')
mb=fit(base+' + cyc_dev + humidity_pct + C(supplier_name)')
mc=fit(base+' + cycle_time_s + cyc_dev + humidity_pct + C(supplier_name)')
print('abs cycle AIC', round(ma.aic,1), 'dev AIC', round(mb.aic,1), 'both AIC', round(mc.aic,1))
print('both coef:', mc.params[['cycle_time_s','cyc_dev']].round(4).to_dict(), mc.pvalues[['cycle_time_s','cyc_dev']].round(4).to_dict())
# humidity shape overall
d['hbin']=pd.cut(d.humidity_pct,[10,20,25,30,35,40,45,50,60,75])
print(d.groupby('hbin',observed=True).apply(lambda g: pd.Series({'rate':g.defective_units.sum()/g.units_produced.sum(),'n':len(g)})).round(4).T.to_string())
# humidity shape per supplier
for s,g in d.groupby('supplier_name'):
    gg = g.copy()
    h = fit(base+' + bs(humidity_pct, df=4) + cycle_time_s + C(supplier_name)', gg) if False else None
    hl = smf.glm('rate ~ '+base+' + bs(humidity_pct, df=4) + cycle_time_s', data=gg, family=sm.families.Binomial(), freq_weights=gg.units_produced).fit()
    xs = np.arange(12,73,1.0)
    newd = pd.DataFrame({'humidity_pct':xs,'mold_c':gg.mold_c.median(),'shift':'Day','operator_id':'OP-01','days_since_clean':7,'L2post':0,'L3post':0,'cycle_time_s':gg.cycle_time_s.mean()})
    p = hl.predict(newd)
    print(s, 'lowest-rate humidity (spline):', xs[np.argmin(p.values)], 'rate range', round(p.min(),4), round(p.max(),4))
    lin = smf.glm('rate ~ '+base+' + humidity_pct + cycle_time_s', data=gg, family=sm.families.Binomial(), freq_weights=gg.units_produced).fit()
    print('   linear humidity coef', round(lin.params['humidity_pct'],4))
    print('   operator-free quad:', smf.glm('rate ~ '+base+' + humidity_pct + I(humidity_pct**2) + cycle_time_s', data=gg, family=sm.families.Binomial(), freq_weights=gg.units_produced).fit().params[['humidity_pct','I(humidity_pct ** 2)']].round(5).to_dict())
EOF
python3 $TMPDIR/hum.py 2>&1 | grep -v -i warn

cat > $TMPDIR/hum2.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
from scipy import stats
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
d['h2']=(d.humidity_pct-40)**2
base='C(shift) + C(operator_id) + days_since_clean + L2post + L3post + mold_c + cycle_time_s'
def fit(f, data): return smf.glm('rate ~ '+f, data=data, family=sm.families.Binomial(), freq_weights=data.units_produced).fit()
m = fit(base+' + humidity_pct + I(humidity_pct**2) + C(supplier_name)', d)
b1=m.params['humidity_pct']; b2=m.params['I(humidity_pct ** 2)']
print('pooled quad:', round(b1,4), round(b2,6), 'opt', round(-b1/(2*b2),2), 'AIC', round(m.aic,1))
# interaction with supplier
mi = fit(base+' + C(supplier_name)*(humidity_pct + I(humidity_pct**2))', d)
print('interaction AIC', round(mi.aic,1), 'LR p', round(stats.chi2.sf(2*(mi.llf-m.llf),4),4))
for s,g in d.groupby('supplier_name'):
    ms = fit(base+' + humidity_pct + I(humidity_pct**2)', g)
    b1=ms.params['humidity_pct']; b2=ms.params['I(humidity_pct ** 2)']
    print(s, 'b1',round(b1,4),'b2',round(b2,6),'opt humidity', round(-b1/(2*b2),2), 'n', len(g))
    # spline-free check: binned rate min
    gb = g.assign(hb=pd.cut(g.humidity_pct,np.arange(10,76,2.5))).groupby('hb',observed=True).apply(lambda x: x.defective_units.sum()/x.units_produced.sum())
    print('   binned min bin:', gb.idxmin(), round(gb.min(),4))
EOF
python3 $TMPDIR/hum2.py 2>&1 | grep -v -i warn

sed -i 's/^import statsmodels.formula.api as smf$/import statsmodels.formula.api as smf\nimport statsmodels.api as sm/' $TMPDIR/hum2.py && python3 $TMPDIR/hum2.py 2>&1 | grep -v -i warn

cat > $TMPDIR/alpha_hum.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
a = d[d.supplier_name=='Alpha'].copy()
lo, hi = d.humidity_pct.min(), d.humidity_pct.max()
grid = np.arange(np.ceil(lo), np.floor(hi)+0.01, 0.5)
base='C(shift) + C(operator_id) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(line)'
for df_ in [4,5,6,8]:
    m = smf.glm('rate ~ '+base+f' + bs(humidity_pct, df={df_})', data=a, family=sm.families.Binomial(), freq_weights=a.units_produced).fit()
    nd = a.iloc[[0]*len(grid)].copy().reset_index(drop=True)
    nd['humidity_pct']=grid
    p = m.predict(nd)
    print('bs df',df_,'AIC', round(m.aic,1), 'argmin humidity', grid[np.argmin(p.values)], 'min pred', round(p.min(),5))
# nonparametric check: binned Alpha rates after adjusting for operator/shift/time via GLM without humidity
m0 = smf.glm('rate ~ '+base, data=a, family=sm.families.Binomial(), freq_weights=a.units_produced).fit()
a['adj'] = m0.predict(a)  # expected rate without humidity
a['obs_over_exp'] = a.defective_units/(a.adj*a.units_produced)
a['hb'] = pd.cut(a.humidity_pct, np.arange(12,75,4))
print(a.groupby('hb',observed=True).apply(lambda g: pd.Series({'obs/exp':round(g.defective_units.sum()/(g.adj*g.units_produced).sum(),3),'n':len(g)})).to_string())
EOF
python3 $TMPDIR/alpha_hum.py 2>&1 | grep -v -i warn

cat > $TMPDIR/cf.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width', 250)
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['mold_c']=d.mold_temp - 7.5*d.L1post
d['rate']=d.defective_units/d.units_produced
F = 'rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name)*(humidity_pct + I(humidity_pct**2))'
m = smf.glm(F, data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
print('AIC', round(m.aic,1)); print(m.params.filter(regex='^(?!C\\(operator)').round(5).to_string())
d['pred_base'] = m.predict(d)
print('obs total rate', round(d.defective_units.sum()/d.units_produced.sum(),5), 'pred total', round((d.pred_base*d.units_produced).sum()/d.units_produced.sum(),5))
# C1: all resin from one supplier, standard recipe cycle time for grade
res={}
for s in ['SP-01','SP-02','SP-03']:
    nm = d.supplier_name.iloc[0] if False else df.drop_duplicates('supplier_code').set_index('supplier_code').loc[s,'supplier_name']
    rec = float(df.drop_duplicates('supplier_code').set_index('supplier_code').loc[s,'recipe_cycle_time_s'])
    x = d.copy(); x['supplier_name']=nm; x['cycle_time_s']=rec
    p = m.predict(x)
    res[nm]=round((p*x.units_produced).sum()/x.units_produced.sum(),6)
print('C1 counterfactual overall rates:', res)
d.to_pickle(f'{T}/model_d.pkl')
EOF
python3 $TMPDIR/cf.py

cat > $TMPDIR/checks.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
d = pd.read_pickle(f'{T}/model_d.pkl')
df = pd.read_pickle(f'{T}/clean2.pkl')
sup = df.drop_duplicates('supplier_code').set_index('supplier_code')
# spec B: no supplier x humidity interaction
mB = smf.glm('rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name) + humidity_pct + I(humidity_pct**2)', data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
out={}
for s in ['SP-01','SP-02','SP-03']:
    nm=sup.loc[s,'supplier_name']; rec=float(sup.loc[s,'recipe_cycle_time_s'])
    x=d.copy(); x['supplier_name']=nm; x['cycle_time_s']=rec
    out[nm]=round((mB.predict(x)*x.units_produced).sum()/x.units_produced.sum(),5)
print('C1 spec B (no interaction):', out)
# alpha optimum on rate (linear) scale
a = d[d.supplier_name=='Alpha'].copy()
lp = smf.ols('rate ~ humidity_pct + I(humidity_pct**2) + mold_c + days_since_clean + C(shift) + cycle_time_s + L2post + L3post', data=a, weights=a.units_produced).fit()
b1,b2 = lp.params['humidity_pct'], lp.params['I(humidity_pct ** 2)']
print('Alpha linear-scale optimum', round(-b1/(2*b2),2))
# Alpha logit quad optimum (model 'mB' style, alpha only)
la = smf.glm('rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + humidity_pct + I(humidity_pct**2)', data=a, family=sm.families.Binomial(), freq_weights=a.units_produced).fit()
print('Alpha logit quad optimum', round(-la.params['humidity_pct']/(2*la.params['I(humidity_pct ** 2)']),2))
EOF
python3 $TMPDIR/checks.py

cat > $TMPDIR/c3.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
d = pd.read_pickle(f'{T}/model_d.pkl')
mt = pd.read_csv('maintenance.csv', dtype=str).apply(lambda c: c.str.strip())
mt['date']=pd.to_datetime(mt.date)
cl = mt[mt.event=='mold_cleaning']
F = 'rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name)*(humidity_pct + I(humidity_pct**2))'
m = smf.glm(F, data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
end = pd.Timestamp('2025-09-30')
# build cleaning schedule with 14-day rule: add cleanings at last+14k until next actual cleaning
new = {}
for ln, g in cl.groupby('line'):
    act = sorted(g.date.tolist())
    sched = []
    for i, c in enumerate(act):
        nxt = act[i+1] if i+1 < len(act) else end + pd.Timedelta(days=60)
        sched.append(c)
        k = 1
        while c + pd.Timedelta(days=14*k) < nxt:
            sched.append(c + pd.Timedelta(days=14*k)); k += 1
    new[ln] = sorted(sched)
    print(ln, 'actual', len(act), 'with rule', len(sched), 'added', len(sched)-len(act))
def dsc(r, sched):
    s = [x for x in sched if x <= r.date]
    return (r.date - max(s)).days if s else np.nan
x = d.copy()
x['dsc_new'] = x.apply(lambda r: dsc(r, new[r.line]), axis=1)
print('days_since old max/mean', d.days_since_clean.max(), round(d.days_since_clean.mean(),2), 'new max/mean', x.dsc_new.max(), round(x.dsc_new.mean(),2))
print('new >14 count', (x.dsc_new>14).sum())
x2 = x.copy(); x2['days_since_clean'] = x2.dsc_new
p_old = m.predict(d); p_new = m.predict(x2)
obs = d.defective_units.sum()/d.units_produced.sum()
pred_old_total = (p_old*d.units_produced).sum()/d.units_produced.sum()
pred_new_total = (p_new*d.units_produced).sum()/d.units_produced.sum()
print('observed', round(obs,6), 'model old', round(pred_old_total,6), 'model new', round(pred_new_total,6))
print('scaled counterfactual (obs * new/old):', round(obs*pred_new_total/pred_old_total,6))
EOF
python3 $TMPDIR/c3.py

cat > $TMPDIR/c3_full.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
d = pd.read_pickle(f'{T}/model_d.pkl')
full = pd.read_pickle(f'{T}/clean2.pkl')
full['L1post']=((full.line=='L1')&(full.date>='2025-04-14')).astype(int)
full['L2post']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['L3post']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['mold_c']=full.mold_temp - 7.5*full.L1post
full['rate']=full.defective_units/full.units_produced
full['humidity_imp']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
print('missing humidity imputed:', full.humidity_pct.isna().sum(), 'mold missing:', full.mold_c.isna().sum())
print('reconstructed rows:', len(full))
F = 'rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name)*(humidity_imp + I(humidity_imp**2))'
m = smf.glm(F, data=full.dropna(subset=['mold_c']), family=sm.families.Binomial(), freq_weights=full.dropna(subset=['mold_c']).units_produced).fit()
f = full.dropna(subset=['mold_c']).copy()
# new schedule from c3.py logic
mt = pd.read_csv('maintenance.csv', dtype=str).apply(lambda c: c.str.strip()); mt['date']=pd.to_datetime(mt.date)
cl = mt[mt.event=='mold_cleaning']; end=pd.Timestamp('2025-09-30')
new={}
for ln,g in cl.groupby('line'):
    act=sorted(g.date.tolist()); sch=[]
    for i,c in enumerate(act):
        nxt = act[i+1] if i+1<len(act) else end+pd.Timedelta(days=60)
        sch.append(c); k=1
        while c+pd.Timedelta(days=14*k)<nxt: sch.append(c+pd.Timedelta(days=14*k)); k+=1
    new[ln]=sorted(sch)
def dsc(r):
    s=[x for x in new[r.line] if x<=r.date]; return (r.date-max(s)).days
f['dsc_new']=f.apply(dsc,axis=1)
x=f.copy(); x['days_since_clean']=x.dsc_new
old=m.predict(f); nw=m.predict(x)
U=f.units_produced
print('model old total', round((old*U).sum()/U.sum(),6), 'observed (complete mold rows)', round(f.defective_units.sum()/U.sum(),6))
print('counterfactual rate (model, complete mold rows):', round((nw*U).sum()/U.sum(),6))
print('observed-anchored counterfactual:', round(f.defective_units.sum()/U.sum()*(nw*U).sum()/(old*U).sum(),6))
# all 3000 batches: observed total, and counterfactual by adjusting observed defects by model ratio
allU = full.units_produced; print('A3 check, full 3000:', round(full.defective_units.sum()/allU.sum(),6))
EOF
python3 $TMPDIR/c3_full.py

cat > $TMPDIR/c3_all.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
full = pd.read_pickle(f'{T}/clean2.pkl')
full['L1post']=((full.line=='L1')&(full.date>='2025-04-14')).astype(int)
full['L2post']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['L3post']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['mold_c']=full.mold_temp - 7.5*full.L1post
full['rate']=full.defective_units/full.units_produced
full['humidity_imp']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
# impute missing mold (0.0 sentinel) from ambient + line + L-post
mm = smf.ols('mold_c ~ ambient_temp_c + C(line) + L2post + L3post', data=full.dropna(subset=['mold_c'])).fit()
miss = full.mold_c.isna()
full.loc[miss,'mold_c'] = mm.predict(full[miss])
print('mold imputed rows', miss.sum())
F = 'rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name)*(humidity_imp + I(humidity_imp**2))'
m = smf.glm(F, data=full, family=sm.families.Binomial(), freq_weights=full.units_produced).fit()
mt = pd.read_csv('maintenance.csv', dtype=str).apply(lambda c: c.str.strip()); mt['date']=pd.to_datetime(mt.date)
cl = mt[mt.event=='mold_cleaning']; end=pd.Timestamp('2025-09-30')
new={}
for ln,g in cl.groupby('line'):
    act=sorted(g.date.tolist()); sch=[]
    for i,c in enumerate(act):
        nxt = act[i+1] if i+1<len(act) else end+pd.Timedelta(days=60)
        sch.append(c); k=1
        while c+pd.Timedelta(days=14*k)<nxt: sch.append(c+pd.Timedelta(days=14*k)); k+=1
    new[ln]=sorted(sch)
def dsc(r):
    s=[x for x in new[r.line] if x<=r.date]; return (r.date-max(s)).days
x=full.copy(); x['days_since_clean']=x.apply(dsc,axis=1)
U=full.units_produced
old=m.predict(full); nw=m.predict(x)
print('observed A3-style rate:', round(full.defective_units.sum()/U.sum(),6))
print('model predicted rate, actual cleanings:', round((old*U).sum()/U.sum(),6))
print('C3 counterfactual (14-day rule), all 3000 batches:', round((nw*U).sum()/U.sum(),6))
print('C3 observed-anchored:', round(full.defective_units.sum()/U.sum()*(nw*U).sum()/(old*U).sum(),6))
EOF
python3 $TMPDIR/c3_all.py

cat > $TMPDIR/a4.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
valid = df.mold_temp.notna()
L1post = (df.line=='L1')&(df.date>='2025-04-14')
for off in [0,6.4,7.5,8.0]:
    v = df.mold_temp - off*L1post
    print('offset', off, 'median', round(v[valid].median(),3), 'n', valid.sum())
# C1 on full base with imputed humidity
full = df.copy(); full['L1post']=((full.line=='L1')&(full.date>='2025-04-14')).astype(int)
full['L2post']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['L3post']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['mold_c']=full.mold_temp - 7.5*full.L1post
full['rate']=full.defective_units/full.units_produced
full['humidity_imp']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
mm = smf.ols('mold_c ~ ambient_temp_c + C(line) + L2post + L3post', data=full.dropna(subset=['mold_c'])).fit()
miss=full.mold_c.isna(); full.loc[miss,'mold_c']=mm.predict(full[miss])
F='rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name)*(humidity_imp + I(humidity_imp**2))'
m=smf.glm(F, data=full, family=sm.families.Binomial(), freq_weights=full.units_produced).fit()
sup = df.drop_duplicates('supplier_code').set_index('supplier_code')
res={}
for s in ['SP-01','SP-02','SP-03']:
    nm=sup.loc[s,'supplier_name']; rec=float(sup.loc[s,'recipe_cycle_time_s'])
    x=full.copy(); x['supplier_name']=nm; x['cycle_time_s']=rec
    res[nm]=round((m.predict(x)*x.units_produced).sum()/x.units_produced.sum(),5)
print('C1 full base:', res)
EOF
python3 $TMPDIR/a4.py

cat > $TMPDIR/l3test.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['rate']=d.defective_units/d.units_produced
d['h2']=d.humidity_pct**2
def run(off1, off3, label, extra=''):
    x=d.copy(); x['m']=x.mold_temp - off1*x.L1post - off3*((x.line=='L3')&(x.date>='2025-04-14')).astype(int)
    f='rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + m + cycle_time_s + C(supplier_name)*(humidity_pct + h2) + ambient_temp_c'+extra
    m=smf.glm(f, data=x, family=sm.families.Binomial(), freq_weights=x.units_produced).fit()
    print(f'{label:28s} AIC={m.aic:.1f} amb={m.params["ambient_temp_c"]:.4f} p={m.pvalues["ambient_temp_c"]:.3f} m={m.params["m"]:.4f}')
run(0,0,'no correction')
run(7.5,0,'L1 corr 7.5')
run(7.5,4,'L1 7.5, L3 4')
run(7.5,2,'L1 7.5, L3 2')
EOF
python3 $TMPDIR/l3test.py

sed -i "s/+ L2post + m + cycle_time_s/+ L2post + L3post + m + cycle_time_s/" $TMPDIR/l3test.py && python3 $TMPDIR/l3test.py

cat > $TMPDIR/offgrid.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
T=os.environ["TMPDIR"]
df = pd.read_pickle(f'{T}/clean2.pkl')
d = df.dropna(subset=['humidity_pct','mold_temp']).copy()
d['L1post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['L2post']=((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['L3post']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['rate']=d.defective_units/d.units_produced; d['h2']=d.humidity_pct**2
best=None
for off in np.arange(5.0,10.01,0.5):
    d['m']=d.mold_temp-off*d.L1post
    m=smf.glm('rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + m + cycle_time_s + C(supplier_name)*(humidity_pct+h2) + ambient_temp_c', data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
    print(off, round(m.aic,1), round(m.params['ambient_temp_c'],4))
    if best is None or m.aic<best[1]: best=(off,m.aic)
print('best offset', best)
EOF
python3 $TMPDIR/offgrid.py

sed -i 's/^import statsmodels.formula.api as smf$/import statsmodels.formula.api as smf\nimport statsmodels.api as sm/' $TMPDIR/offgrid.py && python3 $TMPDIR/offgrid.py

cat > $TMPDIR/final.py <<'EOF'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
T=os.environ["TMPDIR"]
OFF=8.5
raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).apply(lambda c: c.str.strip())
print('rows', len(raw), 'unique batch_id', raw.drop_duplicates().batch_id.nunique())
df = pd.read_pickle(f'{T}/clean2.pkl'); df['recipe_cycle_time_s']=df.recipe_cycle_time_s.astype(float)
print('A1', df.batch_id.nunique(), 'A2 humidity NaN', df.humidity_pct.isna().sum())
print('A3', round(df.defective_units.sum()/df.units_produced.sum(),8))
df['L1post']=((df.line=='L1')&(df.date>='2025-04-14')).astype(int)
df['L2post']=((df.line=='L2')&(df.date>='2025-06-15')).astype(int)
df['L3post']=((df.line=='L3')&(df.date>='2025-07-21')).astype(int)
df['mold_c']=df.mold_temp - OFF*df.L1post
print('A4 median mold (C, L1 corrected):', round(df.mold_c.dropna().median(),3), 'n', df.mold_c.notna().sum())
print('A4 median mold (C, no sensor corr):', round(df.mold_temp.dropna().median(),3))
df['rate']=df.defective_units/df.units_produced
df['humidity_imp']=df.humidity_pct.fillna(df.groupby('supplier_name').humidity_pct.transform('median'))
mm = smf.ols('mold_c ~ ambient_temp_c + C(line) + L2post + L3post', data=df.dropna(subset=['mold_c'])).fit()
miss=df.mold_c.isna(); df.loc[miss,'mold_c']=mm.predict(df[miss])
F='rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + C(supplier_name)*(humidity_imp + I(humidity_imp**2))'
m=smf.glm(F, data=df, family=sm.families.Binomial(), freq_weights=df.units_produced).fit()
U=df.units_produced
sup = df.drop_duplicates('supplier_code').set_index('supplier_code')
c1={}
for s in ['SP-01','SP-02','SP-03']:
    nm=sup.loc[s,'supplier_name']; rec=float(sup.loc[s,'recipe_cycle_time_s'])
    x=df.copy(); x['supplier_name']=nm; x['cycle_time_s']=rec
    c1[nm]=round((m.predict(x)*U).sum()/U.sum(),5)
print('C1', c1)
b1=m.params['humidity_imp']; b2=m.params['I(humidity_imp ** 2)']
print('C2 alpha-humidity optimum (pooled-spec coefficient, alpha base):', 'computed next')
a = df[df.supplier_name=='Alpha'].copy()
ma = smf.glm('rate ~ C(operator_id) + C(shift) + days_since_clean + L2post + L3post + mold_c + cycle_time_s + humidity_imp + I(humidity_imp**2)', data=a, family=sm.families.Binomial(), freq_weights=a.units_produced).fit()
print('C2 Alpha optimum', round(-ma.params['humidity_imp']/(2*ma.params['I(humidity_imp ** 2)']),2))
mt = pd.read_csv('maintenance.csv', dtype=str).apply(lambda c: c.str.strip()); mt['date']=pd.to_datetime(mt.date)
cl = mt[mt.event=='mold_cleaning']; end=pd.Timestamp('2025-09-30')
new={}
for ln,g in cl.groupby('line'):
    act=sorted(g.date.tolist()); sch=[]
    for i,c in enumerate(act):
        nxt = act[i+1] if i+1<len(act) else end+pd.Timedelta(days=60)
        sch.append(c); k=1
        while c+pd.Timedelta(days=14*k)<nxt: sch.append(c+pd.Timedelta(days=14*k)); k+=1
    new[ln]=sorted(sch)
def dsc(r):
    s=[x for x in new[r.line] if x<=r.date]; return (r.date-max(s)).days
x=df.copy(); x['days_since_clean']=x.apply(dsc,axis=1)
old=m.predict(df); nw=m.predict(x)
print('C3 counterfactual', round((nw*U).sum()/U.sum(),6), '| model with actual cleanings', round((old*U).sum()/U.sum(),6), '| observed', round(df.defective_units.sum()/U.sum(),6))
EOF
python3 $TMPDIR/final.py
