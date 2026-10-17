ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/prof.py <<'EOF'
import pandas as pd
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape)
for c in b.columns:
    vc = b[c].value_counts()
    print('\n##', c, 'nunique=', b[c].nunique(), 'empty=', (b[c].str.strip()=='').sum())
    print(vc.head(12).to_string())
EOF
python3 $TMPDIR/prof.py; echo ---; cat suppliers.csv; echo ---; cat maintenance.csv | awk -F, '{print $2,$3,$4}' | sort | uniq -c | sort -rn | head -30

cat > $TMPDIR/p2.py <<'EOF'
import pandas as pd, re
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
# date formats
pats = b.production_date.str.replace(r'\d','9',regex=True).value_counts()
print(pats)
print(b[~b.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$')].production_date.head(20).tolist())
# duplicates
d = b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows', len(d), 'dup ids', d.batch_id.nunique())
print(d.head(8).to_string())
# are dup pairs identical?
print('identical dup rows:', b.duplicated().sum())
g = d.groupby('batch_id').nunique()
print((g>1).sum())
EOF
python3 $TMPDIR/p2.py

cat > $TMPDIR/p3.py <<'EOF'
import pandas as pd
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
s = b[b.production_date.str.contains('/')].production_date.str.split('/', expand=True).astype(int)
print('slash rows', len(s), 'first>12', (s[0]>12).sum(), 'second>12', (s[1]>12).sum())
iso = b[~b.production_date.str.contains('/')].production_date
print('iso range', iso.min(), iso.max())
# try MM/DD and DD/MM
mdy = pd.to_datetime(b[b.production_date.str.contains('/')].production_date, format='%m/%d/%Y', errors='coerce')
dmy = pd.to_datetime(b[b.production_date.str.contains('/')].production_date, format='%d/%m/%Y', errors='coerce')
print('mdy NaT', mdy.isna().sum(), 'range', mdy.min(), mdy.max())
print('dmy NaT', dmy.isna().sum(), 'range', dmy.min(), dmy.max())
# which interpretation keeps counts per day flat? compare batches per date with ISO
isod = pd.to_datetime(iso)
print('iso per-day mean', isod.value_counts().mean(), 'days', isod.nunique())
print('mdy per-day mean', mdy.value_counts().mean(), 'days', mdy.nunique())
print('dmy per-day mean', dmy.value_counts().mean(), 'days', dmy.nunique())
print('mdy dates in ISO days share', mdy.isin(isod).mean(), 'dmy', dmy.isin(isod).mean())
print('dow iso', isod.dt.dayofweek.value_counts().sort_index().tolist())
print('dow mdy', mdy.dt.dayofweek.value_counts().sort_index().tolist())
print('dow dmy', dmy.dt.dayofweek.value_counts().sort_index().tolist())
EOF
python3 $TMPDIR/p3.py

cat > $TMPDIR/p4.py <<'EOF'
import pandas as pd
raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
raw['row']=range(len(raw))
iso = raw[~raw.production_date.str.contains('/')].copy()
iso['d']=pd.to_datetime(iso.production_date)
# is ISO date monotone in row order?
print('ISO monotone violations:', (iso.d.diff().dt.days<0).sum(), 'of', len(iso))
print(iso[['row','production_date','line']].head(15).to_string())
print(iso[['row','production_date','line']].iloc[300:310].to_string())
print(iso[['row','production_date','line']].tail(5).to_string())
# per line
for ln in ['L1']:
    x=iso[iso.line==ln]
    print(ln,'violations',(x.d.diff().dt.days<0).sum(),len(x))
EOF
python3 $TMPDIR/p4.py

cat > $TMPDIR/p5.py <<'EOF'
import pandas as pd, numpy as np
raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
raw['row']=range(len(raw))
raw['is_iso']=~raw.production_date.str.contains('/')
iso = raw[raw.is_iso].copy(); iso['d']=pd.to_datetime(iso.production_date)
# violations
v = iso[iso.d.diff().dt.days<0]
print(v[['row','production_date','line','batch_id']].head(10).to_string())
prev_ = iso.set_index('row')['d'].reindex(raw.row).ffill()
nxt = iso.set_index('row')['d'].reindex(raw.row).bfill()
raw['prev']=prev_.values; raw['next']=nxt.values
sl = raw[~raw.is_iso].copy()
mdy = pd.to_datetime(sl.production_date, format='%m/%d/%Y', errors='coerce')
dmy = pd.to_datetime(sl.production_date, format='%d/%m/%Y', errors='coerce')
ok_m = (mdy>=sl.prev)&(mdy<=sl.next)
ok_d = (dmy>=sl.prev)&(dmy<=sl.next)
print('mdy only',(ok_m&~ok_d).sum(),'dmy only',(ok_d&~ok_m).sum(),'both',(ok_m&ok_d).sum(),'neither',(~ok_m&~ok_d).sum())
EOF
python3 $TMPDIR/p5.py

cat >> $TMPDIR/p5.py <<'EOF'
sl['mdy']=ok_m; sl['dmy']=ok_d
dec = sl[sl.mdy ^ sl.dmy].copy()
dec['fmt']=np.where(dec.mdy,'MDY','DMY')
print(pd.crosstab(dec.line, dec.fmt))
print(pd.crosstab(dec.supplier_code, dec.fmt))
print(pd.crosstab(dec.shift, dec.fmt))
# rows around a violation to see context
print(raw.loc[278:290, ['row','production_date','line','shift','batch_id']].to_string())
EOF
python3 $TMPDIR/p5.py | tail -60

cat > $TMPDIR/p6.py <<'EOF'
import pandas as pd, numpy as np
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x = pd.to_numeric(b[c].str.strip(), errors='coerce')
    print(c, 'nonnumeric', (x.isna()).sum(), 'min', x.min(), 'max', x.max(), 'median', x.median())
    print('   nonnum samples', b.loc[x.isna(), c].unique()[:10])
m = pd.to_numeric(b.mold_temp, errors='coerce')
print('mold >300:', (m>300).sum(), ' mold==0:', (m==0).sum())
print(pd.cut(m[m>0],[0,150,180,200,230,260,300,400,500]).value_counts().sort_index())
print(pd.crosstab(b.line, m>300))
print(b.loc[m>300, ['production_date','line']].head(10).to_string())
EOF
python3 $TMPDIR/p6.py

cat > $TMPDIR/p7.py <<'EOF'
import pandas as pd, numpy as np
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates().reset_index(drop=True)
b['row']=b.index
b['mt']=pd.to_numeric(b.mold_temp)
l3 = b[b.line=='L3'].copy()
l3['iso']=~l3.production_date.str.contains('/')
l3['d']=pd.to_datetime(l3.production_date, format='mixed', errors='coerce')
print(l3.d.isna().sum())
l3=l3.sort_values('row')
print(l3[['row','production_date','mt']].assign(F=lambda x: x.mt>300).groupby('F').agg(['min','max']))
low = l3[l3.mt<=300]
print(low[['row','production_date','shift','mt']].to_string())
print(l3[l3.mt>300].d.min(), l3[l3.mt>300].d.max())
print(l3[(l3.mt>0)].assign(F=lambda x: x.mt>300).groupby(pd.Grouper(key='d',freq='MS'))['F'].mean().to_string())
EOF
python3 $TMPDIR/p7.py

cat > $TMPDIR/clean.py <<'EOF'
import pandas as pd, numpy as np

def load():
    raw = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
    b = raw.drop_duplicates().copy()          # 60 exact duplicate rows
    b['batch_id'] = b.batch_id.str.strip()
    assert b.batch_id.is_unique

    # dates: ISO everywhere except L1 (MM/DD/YYYY) and L4 (DD/MM/YYYY)
    p = b.production_date.str.strip()
    is_iso = p.str.match(r'^\d{4}-\d{2}-\d{2}$')
    slash = ~is_iso
    assert set(b.loc[slash,'line']) <= {'L1','L4'}
    d = pd.to_datetime(p.where(is_iso), format='%Y-%m-%d', errors='coerce')
    d[slash & (b.line=='L1')] = pd.to_datetime(p[slash & (b.line=='L1')], format='%m/%d/%Y')
    d[slash & (b.line=='L4')] = pd.to_datetime(p[slash & (b.line=='L4')], format='%d/%m/%Y')
    assert d.notna().all()
    b['date'] = d

    b['shift'] = b['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
    assert b['shift'].notna().all()
    b['supplier_code'] = b.supplier_code.str.strip().str.upper()
    b['operator_id'] = b.operator_id.str.strip().str.upper()

    for c in ['machine_age_years','ambient_temp_c','mold_temp','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
        b[c] = pd.to_numeric(b[c].str.strip())

    # humidity: -1 sentinel and blanks are invalid
    h = pd.to_numeric(b.humidity_pct.str.strip(), errors='coerce')
    h[h < 0] = np.nan
    b['humidity'] = h

    # mold temp: 0.0 = missing; L3 logs in Fahrenheit throughout
    mt = b.mold_temp.copy()
    mt[mt == 0] = np.nan
    l3 = b.line == 'L3'
    mt[l3] = (mt[l3] - 32) * 5 / 9
    b['mold_c'] = mt

    b['defect_rate'] = b.defective_units / b.units_produced
    return raw, b
EOF
cat > $TMPDIR/check.py <<'EOF'
import sys; sys.path.insert(0, sys.argv[1])
from clean import load
import pandas as pd
raw, b = load()
print('rows raw', len(raw), 'unique', len(b), b.batch_id.nunique())
print('humidity missing', b.humidity.isna().sum(), 'range', b.humidity.min(), b.humidity.max())
print('mold_c missing', b.mold_c.isna().sum(), 'median', b.mold_c.median())
print(b.groupby('line').mold_c.describe())
print('defective>units', (b.defective_units>b.units_produced).sum(), 'zero defect', (b.defective_units==0).sum())
print(b.date.min(), b.date.max())
print(b.supplier_code.value_counts().to_dict(), b.shift.value_counts().to_dict())
print(b.operator_id.nunique(), b.operator_id.unique()[:30])
print('total def/units', b.defective_units.sum()/b.units_produced.sum())
EOF
python3 $TMPDIR/check.py $TMPDIR

sed -i "s/b.shift.value_counts/b['shift'].value_counts/" $TMPDIR/check.py && python3 $TMPDIR/check.py $TMPDIR 2>&1 | tail -8

cat maintenance.csv | sort -t, -k2,2 -k1,1 | awk -F, 'NR==1 || $2!=p{if(NR>1)print ""; p=$2} {print}' | head -90; echo; cat > $TMPDIR/p8.py <<'EOF'
import sys; sys.path.insert(0,'/tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
EOF
echo ok

cat >> $TMPDIR/clean.py <<'EOF'

def load_all():
    raw, b = load()
    sup = pd.read_csv('suppliers.csv', dtype=str)
    sup['supplier_code'] = sup.supplier_code.str.strip().str.upper()
    sup['recipe_cycle_time_s'] = sup.recipe_cycle_time_s.astype(float)
    b = b.merge(sup[['supplier_code','supplier_name','resin_grade','pre_dried','recipe_cycle_time_s']], on='supplier_code', how='left')
    assert b.supplier_name.notna().all()
    b['pre_dried'] = b.pre_dried.eq('yes')
    mt = pd.read_csv('maintenance.csv', dtype=str)
    mt = mt[mt.event.str.strip()=='mold_cleaning'].copy()
    mt['date'] = pd.to_datetime(mt.date)
    mt['line'] = mt.line.str.strip()
    def days_since(g):
        cl = np.sort(mt.loc[mt.line==g.name,'date'].values)
        out = []
        for d in g.date.values:
            prev = cl[cl<=d]
            out.append((d-prev[-1]).astype('timedelta64[D]').astype(int) if len(prev) else np.nan)
        return pd.Series(out, index=g.index)
    b['days_since_clean'] = b.groupby('line', group_keys=False).apply(days_since)
    return raw, b, mt
EOF
cat > $TMPDIR/explore.py <<'EOF'
import sys; sys.path.insert(0,'/tmp/edabench_claude_st7olfnw/../claude-0/x') 
EOF
cat > $TMPDIR/ex1.py <<'EOF'
import sys; sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
import pandas as pd, numpy as np
from clean import load_all
pd.set_option('display.width',200)
raw,b,mt = load_all()
print(b.days_since_clean.describe())
print(b.days_since_clean.isna().sum())
b['r']=b.defect_rate
print(b.groupby('supplier_name').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()))
print(b.groupby('line').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()))
print(b.groupby(['supplier_name','pre_dried']).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum(),'cyc':g.cycle_time_s.mean(),'rec':g.recipe_cycle_time_s.mean()})))
print(b.groupby(b.days_since_clean.clip(upper=40)//5*5).apply(lambda g: pd.Series({'n':len(g),'rate':g.defective_units.sum()/g.units_produced.sum()})))
print(b.groupby('shift').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()))
print(b.groupby('operator_id').apply(lambda g: g.defective_units.sum()/g.units_produced.sum()).sort_values().to_string())
print(b[['defect_rate','humidity','mold_c','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','days_since_clean','units_produced']].corr()['defect_rate'])
EOF
python3 $TMPDIR/ex1.py 2>&1 | grep -v Warning

python3 -c "import statsmodels, sklearn, pandas, numpy; print(statsmodels.__version__, sklearn.__version__, pandas.__version__, numpy.__version__)" 2>&1; python3 -c "import scipy; print(scipy.__version__)" 2>&1

python3 -c "import statsmodels; print(statsmodels.__version__)" 2>&1 | tail -1; python3 -c "import pandas, numpy; print(pandas.__version__, numpy.__version__)"; pip install statsmodels 2>&1 | tail -2

cd $TMPDIR && cat > m1.py <<'EOF'
import sys; sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',200)
from clean import load_all
raw,b,mt = load_all()
d = b.dropna(subset=['mold_c']).copy()
d['hum_missing'] = d.humidity.isna().astype(int)
d['hum'] = d.humidity.fillna(d.humidity.mean())
d['y_fail'] = d.defective_units
d['ok'] = d.units_produced - d.defective_units
def fit(f, data=d):
    m = smf.glm(f, data=data, family=sm.families.Binomial(), freq_weights=data.units_produced).fit()
    return m
f1 = 'defect_rate ~ mold_c + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
m1 = fit(f1)
print(m1.summary2().tables[1].round(4).to_string())
print('AIC', m1.aic, 'dev', m1.deviance, 'df', m1.df_resid)
EOF
python3 m1.py 2>&1 | grep -v Warn

cd $TMPDIR && sed -i "s#'batches.csv'#'/tmp/edabench_claude_st7olfnw/batches.csv'#; s#'suppliers.csv'#'/tmp/edabench_claude_st7olfnw/suppliers.csv'#; s#'maintenance.csv'#'/tmp/edabench_claude_st7olfnw/maintenance.csv'#" clean.py && grep -n "read_csv" clean.py && python3 m1.py 2>&1 | grep -v Warn

cd $TMPDIR && cat > base.py <<'EOF'
import sys; sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',220)
from clean import load_all
raw,b,mt = load_all()
d = b.copy()
d['ok'] = d.units_produced - d.defective_units
d['hum_missing'] = d.humidity.isna().astype(int)
d['hum'] = d.humidity.fillna(d.humidity.mean())
d['dev_cyc'] = d.cycle_time_s - d.recipe_cycle_time_s
d['pre'] = d.pre_dried.astype(int)
d['mold_ok'] = d.mold_c.notna().astype(int)
d['mold'] = d.mold_c.fillna(d.mold_c.mean())
def fit(f, data=None, scale='X2'):
    data = d if data is None else data
    m = smf.glm(f + ' ', data=data, family=sm.families.Binomial()).fit() if False else None
    return None
def glm(formula, data, lhs=('defective_units','ok')):
    import patsy
    y, X = patsy.dmatrices(formula, data, return_type='dataframe')
    yy = data.loc[X.index, list(lhs)].values.astype(float)
    m = sm.GLM(yy, X, family=sm.families.Binomial()).fit(scale='X2')
    return m
EOF
cat > m2.py <<'EOF'
from base import *
full = 'defective_units + ok ~ mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
import patsy
y,X = patsy.dmatrices('defective_units + ok ~ mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean', d, return_type='dataframe')
print(X.shape, y.shape)
EOF
python3 m2.py 2>&1 | tail -3

cd $TMPDIR && cat > base.py <<'EOF'
import sys; sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
import pandas as pd, numpy as np, patsy, statsmodels.api as sm
pd.set_option('display.width', 220)
from clean import load_all
raw, b, mt = load_all()
d = b.copy()
d['ok'] = d.units_produced - d.defective_units
d['hum_missing'] = d.humidity.isna().astype(int)
d['hum'] = d.humidity.fillna(d.humidity.mean())
d['dev_cyc'] = d.cycle_time_s - d.recipe_cycle_time_s
d['pre'] = d.pre_dried.astype(int)
d['mold'] = d.mold_c.fillna(d.mold_c.mean())
d['mold_missing'] = d.mold_c.isna().astype(int)

def glm(formula, data=None, scale='X2'):
    data = d if data is None else data
    y, X = patsy.dmatrices('defective_units + ok ~ ' + formula, data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(scale=scale)

def show(m, keep=None):
    t = pd.DataFrame({'coef': m.params, 'se': m.bse, 'p': m.pvalues})
    if keep: t = t[t.index.str.contains(keep)]
    print(t.round(4).to_string())
    print('dispersion', round(m.scale, 3), 'deviance', round(m.deviance, 1), 'llf', round(m.llf, 1))
EOF
cat > m2.py <<'EOF'
from base import *
f = 'mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
m = glm(f)
show(m, keep='^(?!C\(operator)')
EOF
python3 m2.py 2>&1 | grep -v Warn

cd $TMPDIR && cat > dbg.py <<'EOF'
from base import *
y, X = patsy.dmatrices('defective_units + ok ~ mold', d, return_type='dataframe')
print(y.head(3)); print(y.sum()); print(X.head(2))
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
print('raw scale', m.scale, 'pearson chi2', m.pearson_chi2, 'df', m.df_resid)
EOF
python3 dbg.py 2>&1 | grep -v Warn

cd $TMPDIR && cat > dbg2.py <<'EOF'
from base import *
f = 'mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
y, X = patsy.dmatrices('defective_units + ok ~ ' + f, d, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
print('scale1 pearson', m.pearson_chi2, 'df', m.df_resid, 'ratio', m.pearson_chi2/m.df_resid)
mu = m.fittedvalues * d.units_produced.values
res = (d.defective_units.values - mu)
print('resid sd', res.std(), 'mean binomial sd', np.sqrt(d.units_produced*m.fittedvalues*(1-m.fittedvalues)).mean())
print(pd.Series(m.resid_pearson).describe())
EOF
python3 dbg2.py 2>&1 | grep -v Warn

cd $TMPDIR && cat > dbg3.py <<'EOF'
from base import *
f = 'mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
y, X = patsy.dmatrices('defective_units + ok ~ ' + f, d, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
d['pr'] = m.resid_pearson
d['pred'] = m.fittedvalues
d['obs_rate']=d.defect_rate
d['res_rate'] = d.obs_rate - d.pred
d['mon'] = d.date.dt.to_period('M')
print(d.groupby(['line','mon']).agg(n=('pr','size'), pr_mean=('pr','mean'), obs=('obs_rate','mean'), pred=('pred','mean')).round(3).to_string())
print(d.groupby('line').pr.agg(['mean','std']))
print(d.sort_values('pr', key=abs, ascending=False)[['batch_id','date','line','shift','operator_id','supplier_code','units_produced','defective_units','mold_c','humidity','cycle_time_s','pr']].head(15).to_string())
EOF
python3 dbg3.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > cp.py <<'EOF'
from base import *
base_f = 'mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
def dev(data, f):
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
m0 = dev(d, base_f)
phi = m0.pearson_chi2/m0.df_resid
print('phi', round(phi,2))
res = []
for ln in ['L1','L2','L3','L4']:
    best=None
    for cut in pd.date_range('2025-02-01','2025-09-15',freq='D'):
        dd = d.copy()
        dd['step'] = ((dd.line==ln) & (dd.date>=cut)).astype(int)
        m = dev(dd, base_f + ' + step')
        r = (m0.deviance - m.deviance)/phi
        if best is None or r>best[1]: best=(cut.date(), r)
    res.append((ln,)+best)
    print(ln, 'best step date', best[0], 'chi2-equivalent gain', round(best[1],1))
EOF
python3 cp.py 2>&1 | grep -v -i warn

sleep 100; cat /tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/bdggc624r.output 2>/dev/null | grep -v -i warn | tail -10

cd $TMPDIR && sed -i '1i import warnings; warnings.filterwarnings("ignore")' base.py && cat > spl.py <<'EOF'
from base import *
lin = 'mold + hum + hum_missing + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days_since_clean'
spl = 'cr(mold, df=4) + cr(hum, df=4) + hum_missing + cr(cycle_time_s, df=4) + cr(machine_age_years, df=3) + cr(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(supplier_name) + C(line) + cr(days_since_clean, df=4)'
for name, f in [('lin', lin), ('spl', spl)]:
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, d, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    print(name, 'df', X.shape[1], 'pearson/df', round(m.pearson_chi2/m.df_resid,3), 'deviance', round(m.deviance,1), 'AIC', round(m.aic,1))
EOF
python3 spl.py

cd $TMPDIR && cat > cp2.py <<'EOF'
from base import *
base_f = 'bs(mold, df=4) + bs(hum, df=4) + hum_missing + bs(cycle_time_s, df=4) + bs(machine_age_years, df=3) + bs(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(supplier_name) + C(line) + bs(days_since_clean, df=4)'
def fit(data, f):
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
m0 = fit(d, base_f)
phi = m0.pearson_chi2/m0.df_resid
print('base phi', round(phi,2), 'rank', np.linalg.matrix_rank(m0.model.exog))
for ln in ['L1','L2','L3','L4']:
    res=[]
    for cut in pd.date_range('2025-02-01','2025-09-15',freq='7D'):
        dd = d.copy(); dd['step'] = ((dd.line==ln) & (dd.date>=cut)).astype(int)
        m = fit(dd, base_f + ' + step')
        res.append((round((m0.deviance-m.deviance)/phi,1), cut.date(), round(m.params[-1],3)))
    best = max(res)
    print(ln, 'best', best[1], 'gain', best[0], 'coef', best[2], flush=True)
EOF
nohup python3 cp2.py > cp2.out 2>&1 &
echo started

cd $TMPDIR && cat > leak.py <<'EOF'
from base import *
print('A2 invalid humidity (unique batches):', d.humidity.isna().sum())
print('A4 median mold C:', repr(d.mold_c.median()), 'n valid', d.mold_c.notna().sum())
print('A3 overall rate:', repr(d.defective_units.sum()/d.units_produced.sum()))
print('rework/defect ratio', (d.rework_cost_eur/d.defective_units).describe().round(3).to_dict())
print('corr defect_rate vs qc', round(np.corrcoef(d.defect_rate, d.qc_inspection_min)[0,1],3), 'vs rework', round(np.corrcoef(d.defect_rate, d.rework_cost_eur/d.units_produced)[0,1],3))
print('corr defective vs rework', round(np.corrcoef(d.defective_units, d.rework_cost_eur)[0,1],3))
import statsmodels.formula.api as smf
print(smf.ols('qc_inspection_min ~ defect_rate + mold_c + humidity + cycle_time_s + ambient_temp_c + C(shift) + C(line)', d.dropna(subset=['humidity','mold_c'])).fit().summary2().tables[1].round(4).to_string())
EOF
python3 leak.py 2>&1 | grep -v -i warn

sleep 60; cat $TMPDIR/cp2.out

cat $TMPDIR/cp2.out; echo; echo "--- check:"; pgrep -f cp2.py >/dev/null && echo running || echo done

cd $TMPDIR && cat > m3.py <<'EOF'
from base import *
base_f = 'bs(mold, df=4) + bs(hum, df=4) + hum_missing + bs(cycle_time_s, df=4) + bs(machine_age_years, df=3) + bs(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(supplier_name) + C(line) + bs(days_since_clean, df=4)'
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-15')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-12')).astype(int)
def fit(data, f):
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(), X
for extra in ['', ' + s_L2', ' + s_L2 + s_L3', ' + s_L2 + s_L3 + s_L1']:
    m, X = fit(d, base_f + extra)
    print(repr(extra), 'pearson/df', round(m.pearson_chi2/m.df_resid,3), 'dev', round(m.deviance,1))
    if extra.count('+')==2:
        print(pd.DataFrame({'coef':m.params[-3:], 'se':m.bse[-3:], 'z':m.tvalues[-3:]}).round(3))
EOF
python3 m3.py

cd $TMPDIR && cat > mix.py <<'EOF'
from base import *
d['mon']=d.date.dt.to_period('M')
d['op_hi']=d.operator_id.isin(['OP-19','OP-20','OP-21','OP-22','OP-23','OP-24']).astype(int)
d['night']=(d['shift']=='Night').astype(int)
for ln in ['L2','L3']:
    x=d[d.line==ln]
    t=x.groupby('mon').agg(n=('batch_id','size'), rate=('defect_rate','mean'), w_rate=('defective_units','sum'),
        units=('units_produced','sum'), alpha=('supplier_code', lambda s:(s=='SP-01').mean()), beta=('supplier_code', lambda s:(s=='SP-02').mean()),
        gamma=('supplier_code', lambda s:(s=='SP-03').mean()), ophi=('op_hi','mean'), night=('night','mean'), mold=('mold_c','mean'), hum=('humidity','mean'),
        cyc=('cycle_time_s','mean'), amb=('ambient_temp_c','mean'), age=('machine_age_years','mean'), dsc=('days_since_clean','mean'), qc=('qc_inspection_min','mean'))
    t['wrate']=t.w_rate/t.units
    print('== ',ln); print(t.drop(columns=['w_rate','units']).round(3).to_string())
EOF
python3 mix.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > qc.py <<'EOF'
from base import *
d['mon']=d.date.dt.to_period('M')
# qc vs defect rate relation, pooled, to see if qc is just a function of defects
import statsmodels.formula.api as smf
x = d.copy()
x['L2']=(x.line=='L2').astype(int); x['L3']=(x.line=='L3').astype(int)
m = smf.ols('qc_inspection_min ~ defect_rate + C(line) + C(shift) + ambient_temp_c + cycle_time_s + C(supplier_name)', x).fit()
print(m.params.round(3).to_string(), 'R2', round(m.rsquared,3))
x['qc_res']= m.resid
print(x.groupby(['line','mon']).qc_res.mean().unstack(0).round(2).to_string())
# daily qc for L3 around change
l3=d[d.line=='L3'].sort_values('date')
print(l3[(l3.date>='2025-07-10')&(l3.date<='2025-08-10')].groupby('date').agg(qc=('qc_inspection_min','mean'), n=('batch_id','size'), dr=('defect_rate','mean')).round(3).to_string())
rw = d.assign(rwd=d.rework_cost_eur/d.defective_units).groupby(['line','mon']).rwd.mean().unstack(0).round(2)
print(rw.to_string())
EOF
python3 qc.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > l2day.py <<'EOF'
from base import *
base_f = 'bs(mold, df=4) + bs(hum, df=4) + hum_missing + bs(cycle_time_s, df=4) + bs(machine_age_years, df=3) + bs(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(supplier_name) + C(line) + bs(days_since_clean, df=4)'
def fit(data, f):
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
m0 = fit(d, base_f); phi = m0.pearson_chi2/m0.df_resid
out=[]
for cut in pd.date_range('2025-05-20','2025-07-10',freq='D'):
    dd = d.copy(); dd['step']=((dd.line=='L2')&(dd.date>=cut)).astype(int)
    m = fit(dd, base_f+' + step')
    out.append((round((m0.deviance-m.deviance)/phi,1), str(cut.date()), round(m.params.iloc[-1],3)))
for o in sorted(out, reverse=True)[:6]: print(o)
EOF
python3 l2day.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > l2raw.py <<'EOF'
from base import *
x = d[(d.line=='L2')&(d.date>='2025-06-09')&(d.date<='2025-06-20')].sort_values(['date','row'] if 'row' in d else ['date'])
print(x.groupby('date').agg(n=('batch_id','size'), units=('units_produced','sum'), defects=('defective_units','sum'), rate=('defect_rate','mean'), wrate=('defective_units', 'sum')).assign(w=lambda t: t.defects/t.units).round(4).to_string())
EOF
python3 l2raw.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > final.py <<'EOF'
from base import *
d['s_L2'] = ((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['s_L3'] = ((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['s_L1'] = ((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
core = 'bs(mold, df=4) + hum_missing + bs(cycle_time_s, df=4) + bs(machine_age_years, df=3) + bs(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(supplier_name) + C(line) + bs(days_since_clean, df=4) + s_L2 + s_L3'
hum_sup = 'bs(hum, df=4):C(supplier_name)'
hum_common = 'bs(hum, df=4)'
hum_pre = 'bs(hum, df=4) + bs(hum, df=4):pre'
def fit(f, data=d):
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, data, return_type='dataframe')
    return sm.GLM(y.values, X, family=sm.families.Binomial()).fit(), X
if __name__ == '__main__':
    res = {}
    for name, hf in [('common', hum_common), ('pre-dried split', hum_pre), ('per-supplier', hum_sup)]:
        m, X = fit(core + ' + ' + hf)
        res[name] = m
        print(name, 'params', X.shape[1], 'rank', np.linalg.matrix_rank(X.values), 'pearson/df', round(m.pearson_chi2/m.df_resid,3), 'deviance', round(m.deviance,1), 'AIC', round(m.aic,1))
EOF
python3 final.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > resid.py <<'EOF'
from final import *
m, X = fit(core + ' + ' + hum_pre)
d['pr'] = m.resid_pearson
d['fit'] = m.fittedvalues
print('overall var pr', round(d.pr.var(),2))
for g in ['line','supplier_name','shift','operator_id']:
    print(d.groupby(g).pr.agg(['mean','var']).round(2).T.to_string())
d['mon']=d.date.dt.to_period('M')
print(d.groupby(['line','mon']).pr.var().unstack(0).round(2).to_string())
print(d.groupby(pd.qcut(d.mold, 8, duplicates='drop')).pr.agg(['mean','var']).round(2).to_string())
print(d.groupby(pd.qcut(d.cycle_time_s, 8, duplicates='drop')).pr.agg(['mean','var']).round(2).to_string())
print(d.groupby(pd.qcut(d.hum, 8, duplicates='drop')).pr.agg(['mean','var']).round(2).to_string())
EOF
python3 resid.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > b1.py <<'EOF'
from final import *
from scipy import stats
full_f = core + ' + ' + hum_pre
m, X = fit(full_f); phi = m.pearson_chi2/m.df_resid
print('phi', round(phi,3))
terms = {
 'mold_temp': ['bs(mold, df=4)'],
 'humidity_pct': ['bs(hum, df=4)', 'bs(hum, df=4):pre', 'hum_missing'],
 'cycle_time_s': ['bs(cycle_time_s, df=4)'],
 'machine_age_years': ['bs(machine_age_years, df=3)'],
 'ambient_temp_c': ['bs(ambient_temp_c, df=3)'],
 'operator_id': ['C(operator_id)'],
 'shift': ['C(shift)'],
}
for name, drop in terms.items():
    f = full_f
    for t in drop:
        f = f.replace(' + ' + t, '').replace(t + ' + ', '')
    mr, Xr = fit(f)
    dfdiff = X.shape[1] - Xr.shape[1]
    dev_diff = (mr.deviance - m.deviance)/phi
    p = stats.chi2.sf(dev_diff, dfdiff) if dfdiff>0 else np.nan
    print(f'{name:20s} df={dfdiff:2d} F-like chi2={dev_diff:9.2f} p={p:.4g}')
EOF
python3 b1.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > op.py <<'EOF'
from final import *
print(pd.crosstab(d.operator_id, d.line).to_string())
m, X = fit(core + ' + ' + hum_pre)
t = pd.DataFrame({'coef':m.params,'z':m.tvalues,'p':m.pvalues})
print(t[t.index.str.contains('operator|s_L|shift|ambient|C\(line')].round(3).to_string())
# linear ambient alternative
f2 = core.replace('bs(ambient_temp_c, df=3)', 'ambient_temp_c') + ' + ' + hum_pre
m2,_ = fit(f2); print('linear ambient coef', round(m2.params['ambient_temp_c'],4), 'z', round(m2.tvalues['ambient_temp_c'],2), 'p', round(m2.pvalues['ambient_temp_c'],4))
EOF
python3 op.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > conf.py <<'EOF'
from final import *
from scipy import stats
print(d[['ambient_temp_c','humidity','machine_age_years','mold','cycle_time_s','days_since_clean']].corr().round(2).to_string())
print(d.groupby('line')[['machine_age_years','ambient_temp_c','humidity']].mean().round(2))
print(pd.crosstab(d.line, d.supplier_name))
# operator test with correct df: rank difference
full_f = core + ' + ' + hum_pre
m, X = fit(full_f); phi = m.pearson_chi2/m.df_resid
r_no_op = fit(full_f.replace('C(operator_id) + ', ''))
mr, Xr = r_no_op
rk = np.linalg.matrix_rank(X.values); rkr = np.linalg.matrix_rank(Xr.values)
dfd = rk - rkr; chi = (mr.deviance - m.deviance)/phi
print('operator: rank diff', dfd, 'chi2', round(chi,2), 'p', stats.chi2.sf(chi, dfd))
# ambient test with proper rank too
mr2, Xr2 = fit(full_f.replace(' + bs(ambient_temp_c, df=3)', ''))
dfd2 = np.linalg.matrix_rank(X.values)-np.linalg.matrix_rank(Xr2.values); chi2=(mr2.deviance-m.deviance)/phi
print('ambient: df', dfd2, 'chi2', round(chi2,2), 'p', stats.chi2.sf(chi2,dfd2))
EOF
python3 conf.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > permop.py <<'EOF'
from final import *
rng = np.random.default_rng(0)
full_f = core + ' + ' + hum_pre
def chi_op(data):
    m, X = fit(full_f, data); return m
base = d.copy()
mfull = chi_op(base); phi = mfull.pearson_chi2/mfull.df_resid
nop = fit(full_f.replace('C(operator_id) + ', ''), base)[0]
obs = (nop.deviance - mfull.deviance)/phi
print('observed chi2', round(obs,2), flush=True)
cnt=0; B=200; null=[]
for b_ in range(B):
    dd = base.copy()
    for ln, idx in dd.groupby('line').groups.items():
        dd.loc[idx, 'operator_id'] = rng.permutation(dd.loc[idx, 'operator_id'].values)
    m1 = chi_op(dd); m0 = fit(full_f.replace('C(operator_id) + ', ''), dd)[0]
    stat = (m0.deviance - m1.deviance)/phi
    null.append(stat)
null = np.array(null)
print('perm p-value', (np.sum(null>=obs)+1)/(B+1), 'null 95pct', np.percentile(null,95).round(2), flush=True)
EOF
nohup python3 permop.py > permop.out 2>&1 &
echo started

cd $TMPDIR && cat > cf.py <<'EOF'
from final import *
full_f = core + ' + ' + hum_pre
y, X = patsy.dmatrices('defective_units + ok ~ ' + full_f, d, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
phi = m.pearson_chi2/m.df_resid
def predict(df):
    Xn = patsy.build_design_matrices([X.design_info], df, return_type='dataframe')[0]
    return m.predict(Xn.values)
d['p_obs'] = predict(d)
print('model overall rate (observed covariates):', round((d.p_obs*d.units_produced).sum()/d.units_produced.sum(),6))
print('observed overall rate:', round(d.defective_units.sum()/d.units_produced.sum(),6))
# C1
rec = pd.read_csv('/tmp/edabench_claude_st7olfnw/suppliers.csv', dtype=str)
rec['supplier_code']=rec.supplier_code.str.strip().str.upper()
out = []
for _, r in rec.iterrows():
    c = d.copy()
    c['supplier_name'] = r.supplier_name
    c['pre'] = int(r.pre_dried=='yes')
    c['cycle_time_s'] = float(r.recipe_cycle_time_s)
    p = predict(c)
    out.append((r.supplier_name, round((p*c.units_produced).sum()/c.units_produced.sum(),6), round((d.defective_units*p/d.p_obs).sum()/d.units_produced.sum(),6)))
print('C1 counterfactual (model, ratio):'); [print('  ',o) for o in out]
# C2
a = d[d.supplier_name=='Alpha'].copy()
grid = np.round(np.arange(d.humidity.min(), d.humidity.max()+1e-9, 0.1), 1)
res = []
for h in grid:
    c = a.copy(); c['hum'] = h; c['hum_missing']=0
    p = predict(c)
    res.append((h, (p*c.units_produced).sum()/c.units_produced.sum()))
res = pd.DataFrame(res, columns=['hum','rate'])
best = res.loc[res.rate.idxmin()]
print('C2 best Alpha humidity:', best.hum, 'rate', round(best.rate,6))
print(res.iloc[::50].round(5).to_string())
# C3
cl = mt.copy(); cl['date']=pd.to_datetime(cl.date)
d_cf = np.full(len(d), np.nan)
for ln in d.line.unique():
    actual = set(cl.loc[cl.line==ln,'date'])
    last = min(actual) if False else None
    days = sorted(d.loc[d.line==ln,'date'].unique())
    # start from last cleaning before data
    prior = sorted(x for x in actual if x <= pd.Timestamp('2025-01-06'))
    last = prior[-1]
    cleans=set()
    timeline = pd.date_range(pd.Timestamp('2025-01-06'), pd.Timestamp('2025-09-30'))
    cur = last
    for t in timeline:
        if t in actual or (t-cur).days >= 14:
            cur = t
        cleans.add((t,cur))
    cmap = dict(cleans)
    idx = d.index[d.line==ln]
    d_cf[idx] = [(d.loc[i,'date'] - cmap[d.loc[i,'date']]).days for i in idx]
d['days_cf'] = d_cf
print('days_cf range', d.days_cf.min(), d.days_cf.max(), 'mean obs', round(d.days_since_clean.mean(),2), 'mean cf', round(d.days_cf.mean(),2))
c = d.copy(); c['days_since_clean'] = c.days_cf
p_cf = predict(c)
print('C3 counterfactual (model):', round((p_cf*d.units_produced).sum()/d.units_produced.sum(),6))
print('C3 counterfactual (ratio):', round((d.defective_units*p_cf/d.p_obs).sum()/d.units_produced.sum(),6))
EOF
python3 cf.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > c2check.py <<'EOF'
from final import *
a = d[d.supplier_name=='Alpha'].copy()
a['h2'] = a.hum**2
f = 'hum + h2 + bs(mold, df=4) + hum_missing + bs(cycle_time_s, df=4) + bs(machine_age_years, df=3) + bs(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(line) + bs(days_since_clean, df=4) + s_L2 + s_L3'
y, X = patsy.dmatrices('defective_units + ok ~ ' + f, a, return_type='dataframe')
m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
b1, b2 = m.params[X.columns.get_loc('hum')], m.params[X.columns.get_loc('h2')]
print('quadratic hum coef', round(b1,4), round(b2,6), 'vertex', round(-b1/(2*b2),2), 'z-sq', round(m.tvalues[X.columns.get_loc('h2')],2))
print('alpha n', len(a), 'hum range', a.hum.min(), a.hum.max())
# spline optimum on Alpha only, finer grid check
print('phi', round(m.pearson_chi2/m.df_resid,2))
EOF
python3 c2check.py 2>&1 | grep -v -i warn; echo ---; cat permop.out | grep -v -i warn

cd $TMPDIR && sed -i "s/b1, b2 = m.params\[X.columns.get_loc('hum')\], m.params\[X.columns.get_loc('h2')\]/P = np.asarray(m.params); T = np.asarray(m.tvalues); i1, i2 = X.columns.get_loc('hum'), X.columns.get_loc('h2'); b1, b2 = P[i1], P[i2]/; s/round(m.tvalues\[X.columns.get_loc('h2')\],2)/round(T[i2],2)/" c2check.py && python3 c2check.py 2>&1 | grep -v -i warn; echo ---; grep -v -i warn permop.out

pgrep -f permop.py >/dev/null && echo running || echo finished; cat $TMPDIR/permop.out | grep -v -i warn | tail -5

cd $TMPDIR && grep -v -i warn cp2.out; cat > l1.py <<'EOF'
from final import *
from scipy import stats
full_f = core + ' + ' + hum_pre
m, X = fit(full_f); phi = m.pearson_chi2/m.df_resid
m1, X1 = fit(full_f + ' + s_L1')
chi = (m.deviance - m1.deviance)/phi
print('L1 sensor step chi2', round(chi,2), 'p', round(stats.chi2.sf(chi,1),4), 'coef', round(np.asarray(m1.params)[-1],4))
# L1 mold reading shift check: mean mold_c before/after replacement
l1 = d[d.line=='L1']
print(l1.groupby(l1.date>='2025-04-14').agg(mold=('mold_c','mean'), rate=('defect_rate','mean'), n=('batch_id','size')).round(4).to_string())
EOF
python3 l1.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > l2final.py <<'EOF'
from final import *
base_nos2 = core.replace(' + s_L2', '') + ' + ' + hum_pre
m0 = fit(base_nos2)[0]; phi = m0.pearson_chi2/m0.df_resid
out=[]
for cut in pd.date_range('2025-06-10','2025-06-22',freq='D'):
    dd = d.copy(); dd['s2']=((dd.line=='L2')&(dd.date>=cut)).astype(int)
    m = fit(base_nos2 + ' + s2', dd)[0]
    out.append((str(cut.date()), round((m0.deviance-m.deviance)/phi,1), round(np.asarray(m.params)[-1],3)))
for o in out: print(o)
EOF
python3 l2final.py 2>&1 | grep -v -i warn

pgrep -f permop.py >/dev/null && echo running || echo finished; grep -v -i warn $TMPDIR/permop.out

cd $TMPDIR && cat > b1b.py <<'EOF'
from final import *
from scipy import stats
full_f = core + ' + s_L1 + ' + hum_pre
m, X = fit(full_f); phi = m.pearson_chi2/m.df_resid
print('phi', round(phi,3), 'rank', np.linalg.matrix_rank(X.values), 'coef s_L1', round(np.asarray(m.params)[list(X.columns).index('s_L1')],4))
def lr(f_red, label, dfd=None):
    mr, Xr = fit(f_red)
    dfd = np.linalg.matrix_rank(X.values) - np.linalg.matrix_rank(Xr.values) if dfd is None else dfd
    chi = (mr.deviance - m.deviance)/phi
    print(f'{label:20s} df={dfd:2d} chi2={chi:8.2f} p={stats.chi2.sf(chi,dfd):.4g}')
lr(full_f.replace(' + bs(mold, df=4)', ''), 'mold_temp')
lr(full_f.replace(' + bs(hum, df=4):pre', '').replace(' + bs(hum, df=4)', '').replace(' + hum_missing',''), 'humidity_pct')
lr(full_f.replace(' + bs(cycle_time_s, df=4)', ''), 'cycle_time_s')
lr(full_f.replace(' + bs(machine_age_years, df=3)', ''), 'machine_age_years')
lr(full_f.replace(' + bs(ambient_temp_c, df=3)', ''), 'ambient_temp_c')
lr(full_f.replace(' + C(operator_id)', ''), 'operator_id')
lr(full_f.replace(' + C(shift)', ''), 'shift')
EOF
python3 b1b.py 2>&1 | grep -v -i warn

for i in $(seq 1 1); do sleep 1; done; pgrep -f permop.py >/dev/null && echo running || echo finished; grep -v -i warn $TMPDIR/permop.out

cd $TMPDIR && cat > opdiag.py <<'EOF'
from final import *
full_f = core + ' + s_L1 + ' + hum_pre
m, X = fit(full_f); phi = m.pearson_chi2/m.df_resid
d['mu'] = m.fittedvalues*d.units_produced
# model without operator, to see whether residual operator pattern exists
mn, Xn = fit(full_f.replace(' + C(operator_id)', ''))
d['mu_n'] = mn.fittedvalues*d.units_produced
g = d.groupby('operator_id').agg(line=('line','first'), obs=('defective_units','sum'), exp_no_op=('mu_n','sum'))
g['oe'] = g.obs/g.exp_no_op
g['z'] = (g.obs-g.exp_no_op)/np.sqrt(phi*g.exp_no_op)
print(g.round(3).to_string())
print('var of z', round(g.z.var(),3), 'expected ~1 under no operator effect (within-line demeaned)')
EOF
python3 opdiag.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > moldtest.py <<'EOF'
from final import *
from scipy import stats
full_f = core + ' + s_L1 + ' + hum_pre
m, X = fit(full_f); phi = m.pearson_chi2/m.df_resid
red = full_f.replace('bs(mold, df=4) + ', '')
mr, Xr = fit(red)
dfd = np.linalg.matrix_rank(X.values) - np.linalg.matrix_rank(Xr.values)
chi = (mr.deviance-m.deviance)/phi
print('mold_temp df', dfd, 'chi2', round(chi,2), 'p', stats.chi2.sf(chi,dfd))
EOF
python3 moldtest.py 2>&1 | grep -v -i warn; pgrep -f permop.py >/dev/null && echo running || (echo finished; grep -v -i warn permop.out)

cd $TMPDIR && sed "s/full_f = core + ' + ' + hum_pre/full_f = core + ' + s_L1 + ' + hum_pre/" cf.py > cf2.py && python3 cf2.py 2>&1 | grep -v -i warn

cd $TMPDIR && cat > c2b.py <<'EOF'
from final import *
a = d[d.supplier_name=='Alpha'].copy(); a['h2']=a.hum**2
base = 'bs(mold, df=4) + hum_missing + bs(cycle_time_s, df=4) + bs(machine_age_years, df=3) + bs(ambient_temp_c, df=3) + C(operator_id) + C(shift) + C(line) + bs(days_since_clean, df=4) + s_L2 + s_L3 + s_L1'
for name, f in [('quad', 'hum + h2 + ' + base), ('splineAlpha', 'bs(hum, df=4) + ' + base)]:
    y, X = patsy.dmatrices('defective_units + ok ~ ' + f, a, return_type='dataframe')
    m = sm.GLM(y.values, X, family=sm.families.Binomial()).fit()
    if name=='quad':
        P=np.asarray(m.params); i1,i2=X.columns.get_loc('hum'),X.columns.get_loc('h2')
        print('quad vertex', round(-P[i1]/(2*P[i2]),2))
    else:
        grid = np.arange(12.1, 72.31, 0.1)
        Xg = patsy.build_design_matrices([X.design_info], pd.DataFrame({c: a[c].iloc[0] if c!='hum' else grid for c in ['hum']}|{}) , return_type='dataframe')
        # rebuild by replacing hum in every row
        rates=[]
        for h in grid:
            c = a.copy(); c['hum']=h
            Xn = patsy.build_design_matrices([X.design_info], c, return_type='dataframe')[0]
            rates.append((np.asarray(m.predict(Xn.values))*c.units_produced).sum()/c.units_produced.sum())
        rates=np.array(rates)
        print('spline Alpha-only argmin', round(grid[rates.argmin()],1), 'rate', round(rates.min(),5))
EOF
python3 c2b.py 2>&1 | grep -v -i warn | tail -4

cd $TMPDIR && sed -i '/Xg = patsy.build_design_matrices/d' c2b.py && python3 c2b.py 2>&1 | grep -v -i warn | tail -4

pgrep -f permop.py >/dev/null && echo running || echo finished; grep -v -i warn $TMPDIR/permop.out

until ! pgrep -f permop.py >/dev/null; do sleep 5; done; grep -v -i warn $TMPDIR/permop.out

cat /tmp/claude-0/-tmp-edabench-claude-st7olfnw/7048de4e-dead-54b1-94eb-1442c83575c4/tasks/brqy1jp3q.output 2>/dev/null | tail -3; echo; pgrep -f permop.py >/dev/null && echo running || echo finished

until ! pgrep -f permop.py >/dev/null; do sleep 5; done; grep -v -i warn $TMPDIR/permop.out

pgrep -f permop.py >/dev/null && echo running || echo finished; grep -v -i warn $TMPDIR/permop.out

pgrep -f permop.py >/dev/null && echo running || echo finished; grep -v -i warn $TMPDIR/permop.out
