ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat suppliers.csv && echo && python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc=b[c].value_counts()
    print('\n##',c,'nunique',b[c].nunique(),'empty',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_dict())
    else: print(vc.head(8).to_dict())
"

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d),'dup ids',d.batch_id.nunique())
print('exact-dup rows', b.duplicated().sum())
print(d.head(12).to_string())
print('\nDATE formats:')
import re
print(b.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$').sum(), b.production_date.str.match(r'^\d{2}/\d{2}/\d{4}$').sum())
print(b.production_date[~b.production_date.str.match(r'^(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})$')].unique()[:20])
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min']:
    x=pd.to_numeric(b[c],errors='coerce')
    print(c,'nonnum',x.isna().sum(),'min',x.min(),'max',x.max(),'median',x.median())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
iso=b.production_date.str.match(r'^\d{4}-')
slash=b.production_date[~iso]
a=slash.str.split('/',expand=True).astype(int)
print('first>12',(a[0]>12).sum(),'second>12',(a[1]>12).sum(),'both<=12',((a[0]<=12)&(a[1]<=12)).sum())
print('first>12 => DD/MM:',(a[0]>12).sum(), ' second>12 => MM/DD:',(a[1]>12).sum())
# check ISO rows against line-day
mt=pd.to_numeric(b.mold_temp)
print('mold_temp hist')
print(np.histogram(mt[mt>0],bins=[0,150,180,200,230,250,280,300,350,400,420,450,470]))
print('F-like rows by line:', b[mt>300].line.value_counts().to_dict(), 'n',(mt>300).sum())
print('zero mold rows by line:', b[mt==0].line.value_counts().to_dict())
print('humid -1 by line:', b[pd.to_numeric(b.humidity_pct)==-1].line.value_counts().to_dict())
print(b.head(3).production_date.tolist())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
b['idx']=range(len(b))
iso=b.production_date.str.match(r'^\d{4}-')
x=b[iso].copy(); x['d']=pd.to_datetime(x.production_date)
print('ISO rows monotonic in file order?', x.d.is_monotonic_increasing, 'spearman', x.idx.corr(x.d.astype('int64'),method='spearman'))
print(x[['idx','production_date','line']].iloc[::150].to_string())
y=b[~iso]; print(y[['idx','production_date','line']].iloc[::200].to_string())
" ; python3 -c "
import pandas as pd
b=pd.read_csv('/tmp/edabench_claude_701mn25a/batches.csv',dtype=str,keep_default_na=False)
m=b.mold_temp.astype(float)
L3=b[b.line=='L3'].copy(); L3['mt']=L3.mold_temp.astype(float)
L3['iso']=L3.production_date.str.match(r'^\d{4}-')
print('L3 mold>300 share by iso/format', (L3.mt>300).groupby(L3.iso).mean().to_dict())
print('non-L3 mold>300:', ((b.line!='L3')&(m>300)).sum(), ' L3 mold<300 nonzero:', ((b.line=='L3')&(m<300)&(m>0)).sum())
"

python3 -c "
import pandas as pd
m=pd.read_csv('maintenance.csv',dtype=str,keep_default_na=False)
print(m.shape); print(m.event.value_counts().to_dict()); print(m.line.value_counts().to_dict())
print(m.note.value_counts().to_dict())
print(m.date.str.match(r'^\d{4}-\d{2}-\d{2}$').sum(), m.date[~m.date.str.match(r'^\d{4}-\d{2}-\d{2}$')].tolist())
print(m[m.event!='mold_cleaning'].to_string())
print(m.duplicated().sum())
print(m.sort_values(['line','date']).to_string())
"

mkdir -p $TMPDIR/work && cat > $TMPDIR/work/clean.py <<'EOF'
import pandas as pd, numpy as np

SRC = '/tmp/edabench_claude_701mn25a/'
raw = pd.read_csv(SRC + 'batches.csv', dtype=str, keep_default_na=False)
raw['row'] = np.arange(len(raw))
b = raw.copy()
for c in b.columns:
    if c not in ('row',):
        b[c] = b[c].str.strip()

# --- categorical normalisation
shift_map = {'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'}
b['shift'] = b['shift'].str.lower().map(shift_map)
b['supplier_code'] = b['supplier_code'].str.upper()
assert b['shift'].notna().all()

# --- dates: ISO or slash; slash is ambiguous when both parts <= 12
iso = b['production_date'].str.match(r'^\d{4}-\d{2}-\d{2}$')
d = pd.Series(pd.NaT, index=b.index, dtype='datetime64[ns]')
d[iso] = pd.to_datetime(b.loc[iso, 'production_date'], format='%Y-%m-%d')
sl = b.loc[~iso, 'production_date'].str.split('/', expand=True).astype(int)
dmy = pd.to_datetime(dict(year=2025, month=sl[1], day=sl[0]), errors='coerce')
mdy = pd.to_datetime(dict(year=2025, month=sl[0], day=sl[1]), errors='coerce')
cand_ok = pd.DataFrame({'dmy': dmy, 'mdy': mdy})
only_dmy = dmy.notna() & mdy.isna()
only_mdy = mdy.notna() & dmy.isna()
both = dmy.notna() & mdy.notna()
d[~iso] = np.nan
d[~iso & 0 == 0] = np.nan
tmp = pd.Series(pd.NaT, index=sl.index, dtype='datetime64[ns]')
tmp[only_dmy] = dmy[only_dmy]
tmp[only_mdy] = mdy[only_mdy]
d.loc[sl.index] = tmp
# resolve ambiguous rows by neighbours in file order (file is chronological)
known = d.dropna()
for i in b.index[~iso][both.values]:
    pos = b.index.get_loc(i)
    prev = d.iloc[:pos].dropna()
    nxt = d.iloc[pos + 1:].dropna()
    lo = prev.iloc[-1] if len(prev) else pd.Timestamp('2025-01-06')
    hi = nxt.iloc[0] if len(nxt) else pd.Timestamp('2025-09-30')
    c1, c2 = dmy[i], mdy[i]
    mid = lo + (hi - lo) / 2
    pick = c1 if abs(c1 - mid) <= abs(c2 - mid) else c2
    d[i] = pick
b['date'] = pd.to_datetime(d)
assert b['date'].notna().all()

# --- numerics
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s',
       'units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    b[c] = pd.to_numeric(b[c], errors='coerce')

# L3 mold sensor reports Fahrenheit
f_line = b['line'].eq('L3')
b['mold_unit_raw'] = np.where(f_line, 'F', 'C')
b.loc[f_line, 'mold_temp'] = (b.loc[f_line, 'mold_temp'] - 32) * 5 / 9
# 0.0 mold temp = dropout
b.loc[b['mold_temp'].round(6).eq(0) | (b['mold_temp'] <= 0), 'mold_temp'] = np.nan
# humidity sentinel
b['humidity_valid'] = b['humidity_pct'].notna() & (b['humidity_pct'] >= 0)
b.loc[~b['humidity_valid'], 'humidity_pct'] = np.nan

b.to_pickle(f'{TMPDIR}/work/clean_rows.pkl')
EOF
cd $TMPDIR/work && python3 -c "print(1)" && python3 clean.py && echo done

cd $TMPDIR/work && python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('/tmp/edabench_claude_701mn25a/batches.csv',dtype=str,keep_default_na=False)
s=b.production_date[~b.production_date.str.match(r'^\d{4}-')].str.split('/',expand=True).astype(int)
dmy=pd.to_datetime(dict(year=2025,month=s[1],day=s[0]),errors='coerce')
mdy=pd.to_datetime(dict(year=2025,month=s[0],day=s[1]),errors='coerce')
print(dmy.isna().sum(), mdy.isna().sum(), (dmy.isna()&mdy.isna()).sum())
print(s[(dmy.isna())|(mdy.isna())].head())
print(b.production_date.str.match(r'^\d{4}-\d{2}-\d{2}$').sum())
"

cat > $TMPDIR/work/clean.py <<'EOF'
import pandas as pd, numpy as np

SRC = '/tmp/edabench_claude_701mn25a/'
raw = pd.read_csv(SRC + 'batches.csv', dtype=str, keep_default_na=False)
b = raw.apply(lambda s: s.str.strip())
b.insert(0, 'row', np.arange(len(b)))

# categorical normalisation
b['shift'] = b['shift'].str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
assert b['shift'].notna().all()
b['supplier_code'] = b['supplier_code'].str.upper()

# dates: ISO, or slash format where either DD/MM or MM/DD may apply
dates = [None] * len(b)
cands = {}
for i, s in enumerate(b['production_date']):
    if '-' in s:
        dates[i] = pd.Timestamp(s)
    else:
        a, c, _ = (int(x) for x in s.split('/'))
        opts = []
        for m, dd in ((c, a), (a, c)):   # DD/MM then MM/DD
            try:
                opts.append(pd.Timestamp(2025, m, dd))
            except ValueError:
                pass
        cands[i] = opts
        if len(opts) == 1:
            dates[i] = opts[0]
print('ambiguous:', sum(len(v) == 2 for v in cands.values()), 'unparseable:', sum(len(v) == 0 for v in cands.values()))
# file is chronological: resolve each ambiguous row against the nearest resolved neighbours
for i in sorted(cands):
    if len(cands[i]) == 2:
        prev = [dates[j] for j in range(i - 1, -1, -1) if dates[j] is not None]
        nxt = [dates[j] for j in range(i + 1, len(dates)) if dates[j] is not None]
        lo = prev[0] if prev else pd.Timestamp('2025-01-06')
        hi = nxt[0] if nxt else pd.Timestamp('2025-09-30')
        mid = lo + (hi - lo) / 2
        dates[i] = min(cands[i], key=lambda t: abs(t - mid))
b['date'] = pd.to_datetime(pd.Series(dates))
assert b['date'].notna().all()
print('date range', b['date'].min().date(), b['date'].max().date())

# numerics
num = ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct', 'cycle_time_s',
       'units_produced', 'defective_units', 'qc_inspection_min', 'rework_cost_eur']
for c in num:
    b[c] = pd.to_numeric(b[c], errors='coerce')

# L3 mold sensor reports Fahrenheit; 0 is a dropout
f_line = b['line'].eq('L3')
b.loc[f_line, 'mold_temp'] = (b.loc[f_line, 'mold_temp'] - 32) * 5 / 9
b.loc[b['mold_temp'] <= 0, 'mold_temp'] = np.nan
# humidity sentinel -1 and blanks are invalid
b.loc[b['humidity_pct'] < 0, 'humidity_pct'] = np.nan

b.to_pickle(f'{TMPDIR}/work/clean_rows.pkl')
print(b.shape)
EOF
cd $TMPDIR/work && python3 clean.py

cd $TMPDIR/work && python3 - <<'EOF'
import re
src = open('clean.py').read()
src = src.replace("b.to_pickle(f'{TMPDIR}/work/clean_rows.pkl')", "b.to_pickle('clean_rows.pkl')")
src = src.replace("        if len(opts) == 1:", "        opts = [t for t in opts if pd.Timestamp('2025-01-06') <= t <= pd.Timestamp('2025-09-30')]\n        cands[i] = opts\n        if len(opts) == 1:")
open('clean.py','w').write(src)
EOF
python3 clean.py && python3 -c "
import pandas as pd
b=pd.read_pickle('clean_rows.pkl') if False else None
" ; python3 - <<'EOF'
import pandas as pd, numpy as np, runpy
ns = runpy.run_path('/tmp/claude-0/work/clean.py') if False else None
EOF
cd $TMPDIR/work && python3 -c "
import pandas as pd
b=pd.read_pickle('clean_rows.pkl')
print(b.date.min(), b.date.max())
print(b[b.date>'2025-09-30'][['row','production_date','line','date']].to_string())
print(b[b.date.dt.month.isin([1,2])].shape)
"

cd $TMPDIR/work && python3 -c "
import pandas as pd, numpy as np
b=pd.read_pickle('clean_rows.pkl')
iso=b.production_date.str.contains('-')
print('spearman all rows', b.row.corr(b.date.astype('int64'),method='spearman'))
# local jumps: for each row, compare with median of 6 neighbours (excluding self)
d=b.date.astype('int64')/8.64e13
med=pd.Series(d).rolling(7,center=True,min_periods=3).median()
dev=(d-med).abs()
print('rows >10 days from local median:', (dev>10).sum(), ' ambiguous among them:', (dev>10)[~iso.values].sum())
print(b.loc[dev>10,['row','production_date','line','date']].head(20).to_string())
"

cd $TMPDIR/work && python3 -c "
import pandas as pd, numpy as np
b=pd.read_pickle('clean_rows.pkl')
cols=[c for c in b.columns if c not in ('row','production_date','mold_unit_raw')]
dup_all=b.duplicated(subset=cols,keep=False)
print('rows that duplicate another row on all content fields:', dup_all.sum(), ' extra copies:', b.duplicated(subset=cols).sum())
# same id, different content
g=b[b.batch_id.duplicated(keep=False)]
key=['batch_id']
diff=g.groupby('batch_id').apply(lambda x: len(x.drop_duplicates(subset=cols)))
print('ids with >1 distinct content:', (diff>1).sum(), ' ids with identical content only:', (diff==1).sum())
print(g[g.batch_id.isin(diff[diff>1].index)].sort_values('batch_id')[['row','batch_id','date','line','shift','operator_id','supplier_code','units_produced','defective_units','mold_temp','humidity_pct']].head(24).to_string())
"

cd $TMPDIR/work && python3 -c "
import pandas as pd, numpy as np
b=pd.read_pickle('clean_rows.pkl')
raw=pd.read_csv('/tmp/edabench_claude_701mn25a/batches.csv',dtype=str,keep_default_na=False)
rawdup=raw.duplicated(keep=False)
ex=raw[rawdup]
print('raw exact-dup rows',len(ex))
cols=['batch_id','shift','operator_id','supplier_code','machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur','line']
bb=b.copy()
bb['sc']=bb.supplier_code
# find cleaned dup groups that are not raw dup groups
key=['batch_id','line','shift','operator_id','supplier_code','units_produced','defective_units','cycle_time_s']
g=bb[bb.duplicated(subset=[c for c in cols if c!='mold_temp'] ,keep=False)]
print(g.groupby(['batch_id']).size().value_counts())
x=bb[bb.duplicated(subset=['batch_id','line','units_produced','defective_units','cycle_time_s'],keep=False)].sort_values(['batch_id','row'])
print(x[['row','production_date','batch_id','line','shift','operator_id','supplier_code','units_produced','defective_units','date']].to_string())
" 2>&1 | head -80

cd $TMPDIR/work && python3 -c "
import pandas as pd
b=pd.read_pickle('clean_rows.pkl')
iso=b.production_date.str.contains('-')
for r in (699,2307):
    w=b[(b.row>=r-6)&(b.row<=r+6)]
    print('--- around row',r)
    print(w[['row','production_date','line','date']].to_string())
"

cd $TMPDIR/work && python3 -c "
import pandas as pd
b=pd.read_pickle('clean_rows.pkl')
x=b[b.batch_id=='B-35957']
print(x.drop(columns=['row','production_date','mold_unit_raw']).T.to_string())
content=[c for c in b.columns if c not in ('row','production_date','date','mold_unit_raw')]
# id collisions within the same line
g=b.groupby(['batch_id','line']).size()
print('batch_id repeated within same line:', (g>1).sum())
# id repeated across lines
print('batch_id spanning >1 line:', (b.groupby('batch_id').line.nunique()>1).sum())
# within (batch_id,line): distinct content groups
c2=b.groupby(['batch_id','line']).apply(lambda x: len(x[content].drop_duplicates())).reset_index(name='k')
print('same id+line with different content:', (c2.k>1).sum())
print('unique by content (excl row/date):', len(b.drop_duplicates(subset=content)))
print('unique by (batch_id,line):', b[['batch_id','line']].drop_duplicates().shape[0])
print('unique by batch_id only:', b.batch_id.nunique())
"

cd $TMPDIR/work && python3 -c "
import pandas as pd
b=pd.read_pickle('clean_rows.pkl')
x=b[b.batch_id=='B-35957']
print(x.drop(columns=['row','production_date']).T.to_string())
content=[c for c in b.columns if c not in ('row','production_date','date')]
g=b.groupby(['batch_id','line']).size()
print('batch_id repeated within same line:', (g>1).sum())
print('batch_id spanning >1 line:', (b.groupby('batch_id').line.nunique()>1).sum())
c2=b.groupby(['batch_id','line']).apply(lambda x: len(x[content].drop_duplicates())).reset_index(name='k')
print('same id+line with different content:', (c2.k>1).sum())
print('unique by content (excl row/date):', len(b.drop_duplicates(subset=content)))
print('unique by (batch_id,line):', b[['batch_id','line']].drop_duplicates().shape[0])
print('unique by batch_id only:', b.batch_id.nunique())
" 2>&1 | grep -v Warning

cd $TMPDIR/work && python3 -c "
import pandas as pd
b=pd.read_pickle('clean_rows.pkl')
content=[c for c in b.columns if c not in ('row','production_date','date')]
same=b[b.duplicated(subset=['batch_id','line'],keep=False)]
print('rows in same-id-same-line groups:',len(same), 'groups:', same.groupby(['batch_id','line']).ngroups)
print('groups with differing content:', sum(len(g[content].drop_duplicates())>1 for _,g in same.groupby(['batch_id','line'])))
print('groups with differing date:', sum(g.date.nunique()>1 for _,g in same.groupby(['batch_id','line'])))
u=b.drop_duplicates(subset=['batch_id','line']+[c for c in content if c not in ('batch_id','line')])
print('unique batches after dedup on id+line+content:', len(u))
print('unique (batch_id,line):', b[['batch_id','line']].drop_duplicates().shape[0])
print('raw rows:', 3060)
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && python3 -c "
import pandas as pd, numpy as np
b=pd.read_pickle('clean_rows.pkl')
u=b.drop_duplicates(subset=['batch_id','line']).copy()
print('unique',len(u))
print('mold by line (C):'); print(u.groupby('line').mold_temp.describe().round(2).to_string())
l1=u[u.line=='L1'].copy(); l1['post']=l1.date>='2025-04-14'
print(l1.groupby('post').mold_temp.describe().round(2).to_string())
u['month']=u.date.dt.to_period('M')
print(u.pivot_table(index='month',columns='line',values='mold_temp',aggfunc='median').round(1).to_string())
print(u.groupby('line').ambient_temp_c.median())
"  2>&1 | grep -v -i warn

cd $TMPDIR/work && python3 -c "import statsmodels, sklearn; print('ok', statsmodels.__version__)" 2>&1 | tail -1; python3 -c "
import pandas as pd, numpy as np
b=pd.read_pickle('clean_rows.pkl')
u=b.drop_duplicates(subset=['batch_id','line']).copy()
u['rate']=u.defective_units/u.units_produced
print('defective>units', (u.defective_units>u.units_produced).sum(), ' zero defects', (u.defective_units==0).sum())
print(u[['rate','qc_inspection_min','rework_cost_eur','units_produced','cycle_time_s','mold_temp','humidity_pct','machine_age_years','ambient_temp_c']].corr(method='spearman')['rate'].round(3).to_string())
print(u.groupby('supplier_code')[['rate','cycle_time_s','humidity_pct','mold_temp']].mean().round(4).to_string())
print(u.groupby('shift').rate.mean().round(4).to_dict())
print(u.groupby('operator_id').rate.mean().round(4).describe())
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && cat > common.py <<'EOF'
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
b = pd.read_pickle('/tmp/claude-0/work/clean_rows.pkl') if False else pd.read_pickle('clean_rows.pkl')
u = b.drop_duplicates(subset=['batch_id', 'line']).copy()
u['rate'] = u.defective_units / u.units_produced
u['ok_mold'] = u.mold_temp.notna()
u['ok_hum'] = u.humidity_pct.notna()
u['doy'] = (u.date - pd.Timestamp('2025-01-01')).dt.days
EOF
python3 -c "
import statsmodels.formula.api as smf, statsmodels.api as sm
" && echo statsmodels_ok; python3 - <<'EOF'
import sys; sys.path.insert(0,'.')
import os; os.chdir('.')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
print('complete cases', len(d))
f = 'rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_code)'
m = smf.glm(f, data=d, family=sm.families.Binomial(), freq_weights=d.units_produced)
r = m.fit(scale='X2')
print(r.summary().tables[1])
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
print(d.groupby(['shift']).operator_id.nunique().to_dict())
print(pd.crosstab(d.operator_id, d.shift).head(6))
print(pd.crosstab(d.line,d.supplier_code))
base = 'C(operator_id) + C(shift) + C(line) + C(supplier_code) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c'
full = smf.glm('rate ~ ' + base, data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
print('rank full', np.linalg.matrix_rank(full.model.exog), full.model.exog.shape[1])
print('pearson chi2/df', full.pearson_chi2 / full.df_resid)
phi = full.pearson_chi2 / full.df_resid
for term in ['C(operator_id)','C(shift)','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','C(supplier_code)','C(line)']:
    rest = [t.strip() for t in base.split('+') if t.strip() != term]
    red = smf.glm('rate ~ ' + ' + '.join(rest), data=d, family=sm.families.Binomial(), freq_weights=d.units_produced).fit()
    ddev = (red.deviance - full.deviance) / phi
    dfree = red.df_resid - full.df_resid
    print(f'{term:25s} F-like chi2={ddev:9.2f} df={dfree:3d} p={stats.chi2.sf(ddev,dfree):.3g}')
EOF

cd $TMPDIR/work && cat > fit.py <<'EOF'
import sys; sys.path.insert(0,'/tmp/claude-0/work')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
def glm(formula, data):
    d = data.copy()
    d['ok'] = d.units_produced - d.defective_units
    return smf.glm(formula, data=d, family=sm.families.Binomial(),
                   formula_kwargs=None) if False else None
EOF
python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
d['ok_units'] = d.units_produced - d.defective_units
d['endog'] = list(zip(d.defective_units, d.ok_units))
def fit(f):
    return smf.glm(f, data=d, family=sm.families.Binomial()).fit()
base_terms = ['C(operator_id)','C(shift)','C(line)','C(supplier_code)','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']
full = smf.glm('defective_units + ok_units ~ ' + ' + '.join(base_terms), data=d, family=sm.families.Binomial()).fit()
print('rank', np.linalg.matrix_rank(full.model.exog), full.model.exog.shape[1], 'dispersion', round(full.pearson_chi2/full.df_resid,3))
print(full.summary().tables[1])
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
d['ok_units'] = d.units_produced - d.defective_units
base_terms = ['C(operator_id)','C(shift)','C(line)','C(supplier_code)','mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c']
X = smf.glm('defective_units + ok_units ~ ' + ' + '.join(base_terms), data=d, family=sm.families.Binomial()).fit().model.exog
names = smf.glm('defective_units + ok_units ~ ' + ' + '.join(base_terms), data=d, family=sm.families.Binomial()).fit().model.exog_names
# find dependent columns
u_,s,vt = np.linalg.svd(X, full_matrices=False)
null = vt[s < 1e-8*s[0]]
for v in null:
    print([ (names[i], round(v[i],3)) for i in np.where(np.abs(v)>1e-6)[0]])
print(d.groupby('line').supplier_code.value_counts().unstack().to_string())
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
print(pd.crosstab(u.operator_id, u.line).to_string())
print(pd.crosstab(u.operator_id, u['shift']).T.to_string())
EOF

cd $TMPDIR/work && cat > model.py <<'EOF'
import sys; sys.path.insert(0,'/tmp/claude-0/work')
import warnings; warnings.filterwarnings('ignore')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
d['ok_units'] = d.units_produced - d.defective_units
def G(f, data=None):
    return smf.glm(f, data=d if data is None else data, family=sm.families.Binomial()).fit()
EOF
python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
terms = {'operator':'C(operator_id)','shift':'C(shift)','supplier':'C(supplier_code)','mold':'mold_temp','humid':'humidity_pct',
         'cycle':'cycle_time_s','age':'machine_age_years','ambient':'ambient_temp_c'}
full_f = 'defective_units + ok_units ~ ' + ' + '.join(terms.values())
full = G(full_f); phi = full.pearson_chi2/full.df_resid
print('rank', np.linalg.matrix_rank(full.model.exog), full.model.exog.shape[1], 'phi', round(phi,2))
for k,t in terms.items():
    rest = [v for kk,v in terms.items() if kk!=k]
    if k=='operator': rest = rest + ['C(line)']
    red = G('defective_units + ok_units ~ ' + ' + '.join(rest))
    dev = (red.deviance-full.deviance)/phi; df = red.df_resid-full.df_resid
    print(f'{k:9s} chi2={dev:9.2f} df={df:3.0f} p={stats.chi2.sf(dev,df):.3g}')
# operator within line: full model has operator (includes line) ; reduced has line
red = G('defective_units + ok_units ~ C(line) + C(shift) + C(supplier_code) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c')
dev = (red.deviance-full.deviance)/phi; df = red.df_resid-full.df_resid
print('operator within line', round(dev,2), df, stats.chi2.sf(dev,df))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from scipy import stats
rest = 'C(operator_id) + C(shift) + C(supplier_code) + mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c'
full = G('defective_units + ok_units ~ '+rest); phi = full.pearson_chi2/full.df_resid
for v in ['machine_age_years','mold_temp','humidity_pct','cycle_time_s','ambient_temp_c']:
    base = rest
    nl = G('defective_units + ok_units ~ '+ rest.replace(v, f'bs({v}, df=4)'))
    # test: spline version vs linear
    dev=(full.deviance-nl.deviance)/phi; df=nl.df_model-full.df_model
    print(f'{v:18s} nonlinearity chi2={dev:8.2f} df={df:.0f} p={stats.chi2.sf(dev,df):.3g}')
print('age bins')
d['age_bin']=pd.cut(d.machine_age_years,[0,3,6,9,12,30])
print(d.groupby('age_bin').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).round(4).to_string())
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from scipy import stats
base = 'C(shift) + C(supplier_code) + bs(mold_temp, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line)'
d = d.copy()
f0 = G('defective_units + ok_units ~ '+base, data=d)
phi = f0.pearson_chi2/f0.df_resid
print('phi', round(phi,2))
res=[]
for L in ['L1','L2','L3','L4']:
    best=None
    dates = sorted(d[d.line==L].date.unique())
    for t in dates[30:-30]:
        x = d.assign(step=((d.line==L)&(d.date>=t)).astype(int))
        m = G('defective_units + ok_units ~ '+base+' + step', data=x)
        dev = (f0.deviance - m.deviance)/phi
        if best is None or dev>best[0]: best=(dev, pd.Timestamp(t).date(), m.params['step'], m.bse['step'])
    res.append((L,)+best)
    print(L, 'max chi2 %.1f at %s  step coef %.3f se %.3f p=%.3g' % (best[0], best[1], best[2], best[3], stats.chi2.sf(best[0],1)))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from scipy import stats
ww = d.copy(); ww['wk']=ww.date.dt.to_period('W')
t = ww.groupby(['line','wk']).apply(lambda x: pd.Series({'rate':x.defective_units.sum()/x.units_produced.sum(),'n':len(x)})).reset_index()
for L in ['L2','L3']:
    s=t[t.line==L]
    print(L); print(s.assign(rate=s.rate.round(4)).to_string(index=False))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
ww = u.copy(); ww['wk']=ww.date.dt.to_period('W')
t = ww.groupby(['line','wk']).agg(mold=('mold_temp','mean'), hum=('humidity_pct','mean'), cyc=('cycle_time_s','mean'), amb=('ambient_temp_c','mean'), n=('batch_id','size')).reset_index()
for L in ['L1','L2','L3','L4']:
    s=t[t.line==L]
    print(L, s[['wk','mold','hum','cyc','amb']].round(1).iloc[::3].to_string(index=False))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
h = u[u.humidity_pct==50.2]
print('50.2 rows', len(h), 'by line', h.line.value_counts().to_dict())
print(h.date.min().date(), h.date.max().date())
print(h.groupby(h.date.dt.to_period('M')).size().to_string())
print('raw 50.2 count', (b.humidity_pct==50.2).sum(), ' 50.1/50.3 unique-batch counts', u.humidity_pct.isin([50.1,50.3]).sum())
x=u[u.line=='L2']; x=x.assign(is50=x.humidity_pct==50.2)
print(x.groupby(x.date.dt.to_period('M')).is50.mean().round(2).to_string())
print('rate on 50.2 rows', round(h.defective_units.sum()/h.units_produced.sum(),4), ' others', round(u[u.humidity_pct!=50.2].defective_units.sum()/u[u.humidity_pct!=50.2].units_produced.sum(),4))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
x = b[(b.line=='L2')&(b.date>='2025-02-25')&(b.date<='2025-04-30')].sort_values(['row'])
x = x.assign(stuck=x.humidity_pct.eq(50.2))
print(x[['row','date','humidity_pct','stuck','units_produced','defective_units']].to_string(index=False))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
o = b[(b.humidity_pct==50.2)&~((b.line=='L2')&(b.date>='2025-03-03')&(b.date<='2025-04-13'))]
print(o[['row','production_date','line','date','humidity_pct','units_produced','defective_units']].to_string(index=False))
# stuck runs in other numeric columns, within line, in file order
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','qc_inspection_min','rework_cost_eur']:
    for L in ['L1','L2','L3','L4']:
        s = b[b.line==L].sort_values('row')[c]
        runs = (s != s.shift()).cumsum()
        mx = s.groupby(runs).size().max()
        if mx >= 4:
            print('run', c, L, 'max consecutive identical', mx, 'value', s.iloc[0])
EOF

cd $TMPDIR/work && python3 - <<'EOF'
src = open('clean.py').read()
old = "# humidity sentinel -1 and blanks are invalid\nb.loc[b['humidity_pct'] < 0, 'humidity_pct'] = np.nan\n"
new = ("# humidity: -1 sentinel and blanks are invalid; L2 sensor stuck at 50.2 from 2025-03-03 to 2025-04-13\n"
       "b.loc[b['humidity_pct'] < 0, 'humidity_pct'] = np.nan\n"
       "stuck = b['line'].eq('L2') & b['date'].between('2025-03-03', '2025-04-13') & b['humidity_pct'].eq(50.2)\n"
       "b.loc[stuck, 'humidity_pct'] = np.nan\n")
assert old in src
src = src.replace(old, new).replace("b.to_pickle('clean_rows.pkl')", "b.to_pickle('clean_rows.pkl')")
open('clean.py','w').write(src)
EOF
python3 clean.py && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
print('unique batches', len(u))
print('invalid humidity (unique batches):', u.humidity_pct.isna().sum())
print('invalid mold (unique batches):', u.mold_temp.isna().sum())
print('A3 rate', round(u.defective_units.sum()/u.units_produced.sum(),6))
print('A4 median mold C', round(u.mold_temp.median(),4), 'n', u.mold_temp.notna().sum())
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
d['ok_units'] = d.units_produced - d.defective_units
post = (d.line=='L1')&(d.date>='2025-04-14')
res=[]
for delta in np.arange(-4,20.5,1.0):
    x = d.copy(); x['mold_c'] = x.mold_temp - np.where(post, delta, 0.0)
    m = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line)', data=x, family=sm.families.Binomial()).fit()
    res.append((delta, m.deviance))
    print(f'delta {delta:5.1f} deviance {m.deviance:.2f}')
best = min(res,key=lambda t:t[1]); print('best delta', best)
# step test on L1 with no correction vs with best
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from scipy import stats
d = u.dropna(subset=['mold_temp','humidity_pct']).copy()
d['ok_units'] = d.units_produced - d.defective_units
post = (d.line=='L1')&(d.date>='2025-04-14')
best=None
for delta in np.arange(8.0,10.01,0.1):
    x = d.copy(); x['mold_c'] = x.mold_temp - np.where(post, delta, 0.0)
    m = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line)', data=x, family=sm.families.Binomial()).fit()
    if best is None or m.deviance < best[1]: best=(round(delta,2), m.deviance)
print('best delta fine', best)
delta = best[0]
# L1 step after correction
x = d.copy(); x['mold_c'] = x.mold_temp - np.where(post, delta, 0.0)
base='C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line)'
f0 = smf.glm('defective_units + ok_units ~ '+base, data=x, family=sm.families.Binomial()).fit(); phi=f0.pearson_chi2/f0.df_resid
for L in ['L1','L2','L3','L4']:
    best2=None
    for t in sorted(x[x.line==L].date.unique())[30:-30]:
        y = x.assign(step=((x.line==L)&(x.date>=t)).astype(int))
        m = smf.glm('defective_units + ok_units ~ '+base+' + step', data=y, family=sm.families.Binomial()).fit()
        dev=(f0.deviance-m.deviance)/phi
        if best2 is None or dev>best2[0]: best2=(dev, pd.Timestamp(t).date(), m.params['step'])
    print(L, 'chi2 %.1f  date %s  coef %.3f  p=%.3g' % (best2[0], best2[1], best2[2], stats.chi2.sf(best2[0],1)))
EOF

cd $TMPDIR/work && cat > cleaning.py <<'EOF'
import pandas as pd, numpy as np
m = pd.read_csv('/tmp/edabench_claude_701mn25a/maintenance.csv', dtype=str, keep_default_na=False)
m['date'] = pd.to_datetime(m['date'])
cl = m[m.event.str.strip() == 'mold_cleaning']
def days_since(df, cleanings):
    out = np.full(len(df), np.nan)
    for L, g in df.groupby('line'):
        c = np.sort(cleanings[cleanings.line == L].date.values)
        idx = g.index
        for i, dt in zip(idx, g.date.values):
            k = np.searchsorted(c, dt, side='right') - 1   # last cleaning on or before this day
            out[df.index.get_loc(i)] = (dt - c[k]).astype('timedelta64[D]').astype(int) if k >= 0 else np.nan
    return out
EOF
python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
from scipy import stats
d = d.reset_index(drop=True)
d['dsc'] = days_since(d, cl)
print('days since cleaning summary by line'); print(d.groupby('line').dsc.describe().round(1).to_string())
print('rows with no prior cleaning:', d.dsc.isna().sum())
base = 'C(shift) + C(supplier_code) + bs(mold_temp, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line)'
f0 = G('defective_units + ok_units ~ '+base, data=d); phi=f0.pearson_chi2/f0.df_resid
f1 = G('defective_units + ok_units ~ '+base+' + dsc', data=d)
print('dsc coef', round(f1.params['dsc'],5), 'se', round(f1.bse['dsc'],5), 'p', f1.pvalues['dsc'], 'chi2 gain', round((f0.deviance-f1.deviance)/phi,2))
print('dsc effect per 14 days on rate (log-odds *14):', round(f1.params['dsc']*14,4))
bins = pd.cut(d.dsc,[-1,0,3,7,10,14,21,30,60,400])
print(d.groupby(bins).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()})).round(4).to_string())
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
from scipy import stats
d = d.reset_index(drop=True); d['dsc'] = days_since(d, cl)
post = (d.line=='L1')&(d.date>='2025-04-14'); d['mold_c'] = d.mold_temp - np.where(post, 9.0, 0.0)
base = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc'
f0 = G('defective_units + ok_units ~ '+base, data=d); phi=f0.pearson_chi2/f0.df_resid
print('phi', round(phi,2))
for L in ['L1','L2','L3','L4']:
    best=None
    for t in sorted(d[d.line==L].date.unique())[30:-30]:
        y = d.assign(step=((d.line==L)&(d.date>=t)).astype(int))
        m = G('defective_units + ok_units ~ '+base+' + step', data=y)
        dev=(f0.deviance-m.deviance)/phi
        if best is None or dev>best[0]: best=(dev,pd.Timestamp(t).date(),m.params['step'])
    print(L,'chi2 %.1f date %s coef %.3f p=%.3g'%(best[0],best[1],best[2],stats.chi2.sf(best[0],1)))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
from scipy import stats
d = d.reset_index(drop=True); d['dsc'] = days_since(d, cl)
post = (d.line=='L1')&(d.date>='2025-04-14'); d['mold_c'] = d.mold_temp - np.where(post, 9.0, 0.0)
base = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc'
f0 = G('defective_units + ok_units ~ '+base, data=d); phi=f0.pearson_chi2/f0.df_resid
for L, t0 in [('L2','2025-06-16'), ('L3','2025-07-21')]:
    tt = pd.Timestamp(t0)
    best_step=None; best_ramp=None
    for t in pd.date_range(pd.Timestamp(t0)-pd.Timedelta(days=45), pd.Timestamp(t0)+pd.Timedelta(days=45)):
        y = d.assign(step=((d.line==L)&(d.date>=t)).astype(int))
        m = G('defective_units + ok_units ~ '+base+' + step', data=y)
        if best_step is None or m.deviance<best_step[0]: best_step=(m.deviance,t.date())
    # ramp: linear in days after start t, zero before
    for t in pd.date_range(pd.Timestamp(t0)-pd.Timedelta(days=60), pd.Timestamp(t0)+pd.Timedelta(days=30)):
        y = d.assign(ramp=np.where((d.line==L)&(d.date>=t), (d.date-t).dt.days, 0)/30.0)
        m = G('defective_units + ok_units ~ '+base+' + ramp', data=y)
        if best_ramp is None or m.deviance<best_ramp[0]: best_ramp=(m.deviance,t.date(), m.params['ramp'])
    print(L,'step dev %.1f at %s | ramp dev %.1f from %s (coef per month %.3f)' % (best_step[0],best_step[1],best_ramp[0],best_ramp[1],best_ramp[2]))
    print('   deviance advantage of step over ramp (phi-scaled):', round((best_ramp[0]-best_step[0])/phi,1))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
from scipy import stats
d = d.reset_index(drop=True); d['dsc'] = days_since(d, cl)
post1 = (d.line=='L1')&(d.date>='2025-04-14'); d['mold_c'] = d.mold_temp - np.where(post1, 9.0, 0.0)
rest = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc'
for L, t0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    sel = (d.line==L)&(d.date>=t0)
    out=[]
    for delta in np.arange(-20,20.5,1.0):
        x = d.copy(); x['mold_x'] = x.mold_c - np.where(sel, delta, 0.0)
        m = G('defective_units + ok_units ~ C(shift) + C(supplier_code) + bs(mold_x, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc', data=x)
        out.append((delta, m.deviance))
    best=min(out,key=lambda t:t[1])
    f0 = G('defective_units + ok_units ~ '+rest); 
    print(L, 'best post-date mold offset', best[0], 'deviance', round(best[1],1), 'vs no-offset model', round(f0.deviance,1), ' (step dummy model deviance below)')
    y = d.assign(step=((d.line==L)&(d.date>=t0)).astype(int))
    ms = G('defective_units + ok_units ~ '+rest+' + step', data=y)
    print('   step-dummy model deviance', round(ms.deviance,1), ' step coef', round(ms.params['step'],3))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
from scipy import stats
d = d.reset_index(drop=True); d['dsc'] = days_since(d, cl)
post1 = (d.line=='L1')&(d.date>='2025-04-14'); d['mold_c'] = d.mold_temp - np.where(post1, 9.0, 0.0)
def fit(data, f): return smf.glm('defective_units + ok_units ~ ' + f, data=data, family=sm.families.Binomial()).fit()
rest = 'C(shift) + C(supplier_code) + bs(mold_x, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc'
for L, t0 in [('L2','2025-06-16'),('L3','2025-07-21')]:
    sel = ((d.line==L)&(d.date>=t0)).values
    out=[]
    for delta in np.arange(-20,20.5,1.0):
        x = d.copy(); x['mold_x'] = x.mold_c - np.where(sel, delta, 0.0)
        out.append((delta, fit(x, rest).deviance))
    best=min(out,key=lambda t:t[1])
    y = d.assign(mold_x=d.mold_c, step=sel.astype(int))
    nostep = fit(y, rest.replace('mold_x','mold_x'))
    ms = fit(y, rest+' + step')
    print(L,'best offset',best[0],'dev',round(best[1],1),'| no-offset dev',round(nostep.deviance,1),'| step-dummy dev',round(ms.deviance,1),'step coef',round(ms.params['step'],3))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
u['qc_per_def'] = u.qc_inspection_min
u['rw_per_def'] = u.rework_cost_eur / u.defective_units
u['per_unit'] = u.rework_cost_eur/u.units_produced
u['wk']=u.date.dt.to_period('M')
print(u.pivot_table(index='wk', columns='line', values='qc_inspection_min', aggfunc='mean').round(2).to_string())
print(u.pivot_table(index='wk', columns='line', values='rw_per_def', aggfunc='median').round(2).to_string())
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from common import *
u['rw_per_def'] = u.rework_cost_eur / u.defective_units
L3 = u[u.line=='L3'].sort_values('date')
L3['per'] = L3.defective_units/L3.units_produced
w = L3.groupby(L3.date.dt.to_period('W')).agg(qc=('qc_inspection_min','mean'), rw=('rw_per_def','median'), rate=('per','mean'), n=('batch_id','size'))
print(w.round(3).loc['2025-06-20':'2025-08-10'].to_string())
for name,x in [('before 07-21',L3[L3.date<'2025-07-21']),('after 07-21',L3[L3.date>='2025-07-21'])]:
    print(name, 'qc mean', round(x.qc_inspection_min.mean(),2), 'qc sd', round(x.qc_inspection_min.std(),2), 'rate', round(x.defective_units.sum()/x.units_produced.sum(),4), 'corr(qc,defects)', round(x.qc_inspection_min.corr(x.defective_units),3), 'corr(qc,units)', round(x.qc_inspection_min.corr(x.units_produced),3))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
import statsmodels.formula.api as smf
from common import *
u['post'] = (u.line=='L3') & (u.date>='2025-07-21')
u['L3post'] = u.post.astype(int)
u['rate'] = u.defective_units/u.units_produced
pre = u[~u.post]
print('qc ~ defects, all lines, pre-07-21 L3 excluded:')
m1 = smf.ols('qc_inspection_min ~ defective_units + units_produced + C(line)', data=pre).fit()
print(m1.params.round(4).to_string())
m1b = smf.ols('qc_inspection_min ~ defective_units + units_produced + C(line)', data=u).fit()
print('L3post effect on qc (conditional on defects):', round(smf.ols('qc_inspection_min ~ defective_units + units_produced + C(line) + L3post', data=u).fit().params['L3post'],3))
print('rework ~ defects, L3post effect:')
r = smf.ols('rework_cost_eur ~ defective_units + units_produced + C(line) + L3post', data=u).fit()
print(r.params.round(3).to_string(), r.rsquared.round(3))
print('L3 post rework residual per defect:', round((u[u.post].rework_cost_eur - u[u.post].defective_units*4.2).mean(),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
import statsmodels.formula.api as smf
from common import *
u['L2post'] = ((u.line=='L2') & (u.date>='2025-06-16')).astype(int)
u['L3post'] = ((u.line=='L3') & (u.date>='2025-07-21')).astype(int)
for y in ['qc_inspection_min','rework_cost_eur']:
    m = smf.ols(f'{y} ~ defective_units + units_produced + C(line) + L2post + L3post', data=u).fit()
    print(y, 'L2post', round(m.params['L2post'],3), 'p', round(m.pvalues['L2post'],3), '| L3post', round(m.params['L3post'],3), 'p', round(m.pvalues['L3post'],3))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
d = d.reset_index(drop=True); d['dsc'] = days_since(d, cl)
post1 = (d.line=='L1')&(d.date>='2025-04-14'); d['mold_c'] = d.mold_temp - np.where(post1, 9.0, 0.0)
rest = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc'
f0 = smf.glm('defective_units + ok_units ~ '+rest, data=d, family=sm.families.Binomial()).fit()
d['exp'] = f0.fittedvalues * d.units_produced
g = d[d.line=='L2'].groupby('date').agg(obs=('defective_units','sum'), exp=('exp','sum'), units=('units_produced','sum'))
g['ratio'] = (g.obs/g.exp).round(3)
print(g.loc['2025-06-01':'2025-06-30'].round(2).to_string())
# candidate steps: deviance by first date, near mid-June
res=[]
phi = f0.pearson_chi2/f0.df_resid
for t in pd.date_range('2025-06-05','2025-06-25'):
    y = d.assign(step=((d.line=='L2')&(d.date>=t)).astype(int))
    m = smf.glm('defective_units + ok_units ~ '+rest+' + step', data=y, family=sm.families.Binomial()).fit()
    res.append((t.date(), round((f0.deviance-m.deviance)/phi,1)))
print(res)
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from model import *
from cleaning import cl, days_since
from scipy import stats
d = d.reset_index(drop=True); d['dsc'] = days_since(d, cl)
post1 = (d.line=='L1')&(d.date>='2025-04-14'); d['mold_c'] = d.mold_temp - np.where(post1, 9.0, 0.0)
def fit(data, f): return smf.glm('defective_units + ok_units ~ '+f, data=data, family=sm.families.Binomial()).fit()
rest = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + dsc'
f0 = fit(d, rest); phi=f0.pearson_chi2/f0.df_resid
# nonlinearity in dsc
fn = fit(d, rest.replace('+ dsc','+ bs(dsc, df=4)'))
print('dsc nonlinearity chi2', round((f0.deviance-fn.deviance)/phi,1), 'df', fn.df_model-f0.df_model)
# L2 step with operator instead of line
y = d.assign(step=((d.line=='L2')&(d.date>='2025-06-16')).astype(int))
r2 = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(operator_id) + dsc'
a = fit(y, r2); b2 = fit(y, r2+' + step')
print('L2 step with operator controls: chi2', round((a.deviance-b2.deviance)/phi,1), 'coef', round(b2.params['step'],3))
EOF

cd $TMPDIR/work && cat > final_model.py <<'EOF'
import sys; sys.path.insert(0,'/tmp/claude-0/work')
import warnings; warnings.filterwarnings('ignore')
from common import *
import statsmodels.formula.api as smf, statsmodels.api as sm
from cleaning import cl, days_since
RECIPE = {'PP-H350': 30, 'PP-H420': 36}
sup = pd.read_csv('/tmp/edabench_claude_701mn25a/suppliers.csv', dtype=str)
sup['recipe'] = sup.resin_grade.map(RECIPE)
sup['recipe_cycle_time_s'] = sup.recipe_cycle_time_s.astype(float)
assert (sup.recipe == sup.recipe_cycle_time_s).all()
u = u.reset_index(drop=True)
u['dsc'] = days_since(u, cl)
u['mold_c'] = u.mold_temp - np.where((u.line=='L1')&(u.date>='2025-04-14'), 9.0, 0.0)  # L1 replacement offset
u['ok_units'] = u.units_produced - u.defective_units
FORM = 'C(shift) + C(supplier_code) + bs(mold_c, df=4) + bs(humidity_pct, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
data = u.dropna(subset=['mold_c','humidity_pct']).reset_index(drop=True)
model = smf.glm('defective_units + ok_units ~ ' + FORM, data=data, family=sm.families.Binomial()).fit()
def pred(df):
    return model.predict(df, which='mean')
EOF
python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
print('complete rows', len(data), 'phi', round(model.pearson_chi2/model.df_resid,2))
p_obs = pred(data)
# C1: each supplier for all batches, recipe cycle of its grade
rows=[]
for _,s in sup.iterrows():
    x = data.copy(); x['supplier_code']=s.supplier_code; x['cycle_time_s']=s.recipe
    p_cf = pred(x)
    cf_def = data.defective_units.sum() + (data.units_produced*(p_cf-p_obs)).sum()
    rate_cf = cf_def/data.units_produced.sum()
    rows.append((s.supplier_name, s.supplier_code, s.recipe, round(rate_cf,5)))
print(pd.DataFrame(rows, columns=['name','code','cycle','rate_cf']).to_string(index=False))
print('observed rate on complete rows', round(data.defective_units.sum()/data.units_produced.sum(),5))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
print('Alpha complete batches', len(alpha), 'humidity range', alpha.humidity_pct.min(), alpha.humidity_pct.max())
F2 = FORM.replace(' + C(supplier_code)','')
ma = smf.glm('defective_units + ok_units ~ ' + F2 + ' + bs(humidity_pct, df=6)', data=alpha, family=sm.families.Binomial()).fit()
phi = ma.pearson_chi2/ma.df_resid; print('phi', round(phi,2))
grid = np.arange(np.floor(alpha.humidity_pct.min()), np.ceil(alpha.humidity_pct.max())+0.01, 0.1)
ref = alpha.median(numeric_only=True)
rows=[]
for h in grid:
    x = alpha.copy(); x['humidity_pct']=h
    p = ma.predict(x, which='mean').mean()
    rows.append((round(h,1), p))
g = pd.DataFrame(rows, columns=['h','p'])
i = g.p.idxmin()
print('argmin humidity (spline df6, Alpha):', g.h[i], 'rate', round(g.p[i],5))
print(g.iloc[::25].round(5).to_string(index=False))
# robustness: quadratic and full-sample model with supplier-specific humidity
mq = smf.glm('defective_units + ok_units ~ C(shift) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=alpha, family=sm.families.Binomial()).fit()
b1, b2 = mq.params['humidity_pct'], mq.params['I(humidity_pct ** 2)']
print('quadratic argmin', round(-b1/(2*b2),2), 'coefs', round(b1,5), round(b2,6))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
print('Alpha complete batches', len(alpha), 'humidity range', alpha.humidity_pct.min(), alpha.humidity_pct.max())
F2 = 'C(shift) + bs(mold_c, df=4) + bs(humidity_pct, df=6) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
ma = smf.glm('defective_units + ok_units ~ ' + F2, data=alpha, family=sm.families.Binomial()).fit()
print('phi', round(ma.pearson_chi2/ma.df_resid,2))
grid = np.round(np.arange(alpha.humidity_pct.min(), alpha.humidity_pct.max()+1e-9, 0.1), 2)
rows=[]
for h in grid:
    x = alpha.copy(); x['humidity_pct']=h
    rows.append((h, ma.predict(x, which='mean').mean()))
g = pd.DataFrame(rows, columns=['h','p'])
i = g.p.idxmin()
print('argmin humidity (spline df6, Alpha):', g.h[i], 'rate', round(g.p[i],5))
print(g.iloc[::30].round(5).to_string(index=False))
mq = smf.glm('defective_units + ok_units ~ C(shift) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=alpha, family=sm.families.Binomial()).fit()
b1, b2 = mq.params['humidity_pct'], mq.params['I(humidity_pct ** 2)']
print('quadratic argmin', round(-b1/(2*b2),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
F0 = 'C(shift) + bs(mold_c, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
m0 = smf.glm('defective_units + ok_units ~ ' + F0, data=alpha, family=sm.families.Binomial()).fit()
# partial effect of humidity: fit spline-only vs base offset via logit offset
lin = m0.predict(alpha, which='linear')
# humidity-only binomial with offset
for df in [3,4,5,6,8]:
    mh = smf.glm(f'defective_units + ok_units ~ bs(humidity_pct, df={df})', data=alpha, family=sm.families.Binomial(), offset=lin).fit()
    grid = pd.DataFrame({'humidity_pct': np.round(np.arange(12.1,72.31,0.1),2)})
    grid['lin']=0.0
    p = mh.predict(grid, which='linear', offset=None) if False else None
    rows=[]
    for h in np.round(np.arange(alpha.humidity_pct.min(), alpha.humidity_pct.max()+1e-9, 0.1),2):
        x = alpha[['humidity_pct']].copy(); x['humidity_pct']=h
        rows.append(mh.predict(x, which='linear').iloc[0] if False else mh.predict(x, which='mean').iloc[0])
    grid2 = np.round(np.arange(alpha.humidity_pct.min(), alpha.humidity_pct.max()+1e-9, 0.1),2)
    i = int(np.argmin(rows))
    print('spline df', df, 'argmin', grid2[i])
# binned adjusted: mean of residual logit by humidity bin
alpha['adj'] = np.log(alpha.defective_units/alpha.ok_units) - lin
alpha['hbin'] = pd.cut(alpha.humidity_pct, np.arange(10,76,4))
print(alpha.groupby('hbin').apply(lambda x: pd.Series({'n':len(x),'adj_logit':round(np.average(x.adj, weights=x.units_produced),3)})).to_string())
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
from scipy import stats
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
Fq = 'C(shift) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
mq = smf.glm('defective_units + ok_units ~ '+Fq, data=alpha, family=sm.families.Binomial()).fit()
phi = mq.pearson_chi2/mq.df_resid
b1, b2 = mq.params['humidity_pct'], mq.params['I(humidity_pct ** 2)']
V = mq.cov_params().loc[['humidity_pct','I(humidity_pct ** 2)']].values
h0 = -b1/(2*b2)
g = np.array([-1/(2*b2), b1/(2*b2**2)])   # d h0 / d(b1,b2)
se = np.sqrt(g @ V @ g) * np.sqrt(phi)
print('quadratic argmin %.2f  se %.2f  95%% CI [%.1f, %.1f]' % (h0, se, h0-1.96*se, h0+1.96*se))
# spline vs quadratic deviance
ms = smf.glm('defective_units + ok_units ~ C(shift) + bs(mold_c, df=4) + bs(humidity_pct, df=6) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=alpha, family=sm.families.Binomial()).fit()
print('quad dev', round(mq.deviance,1), 'spline6 dev', round(ms.deviance,1), 'spline extra df', round(ms.df_model-mq.df_model,1))
# cubic check
mc = smf.glm('defective_units + ok_units ~ '+Fq+' + I(humidity_pct**3)', data=alpha, family=sm.families.Binomial()).fit()
print('cubic term p', round(mc.pvalues['I(humidity_pct ** 3)'],4))
# full-sample quadratic with supplier main effects
full = data.copy()
mf = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=full, family=sm.families.Binomial()).fit()
print('full-sample quadratic argmin', round(-mf.params['humidity_pct']/(2*mf.params['I(humidity_pct ** 2)']),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
Fq = 'C(shift) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
mq = smf.glm('defective_units + ok_units ~ '+Fq, data=alpha, family=sm.families.Binomial()).fit()
phi = mq.pearson_chi2/mq.df_resid
b1, b2 = mq.params['humidity_pct'], mq.params['I(humidity_pct ** 2)']
C = mq.cov_params()
V = C.loc[['humidity_pct','I(humidity_pct ** 2)'],['humidity_pct','I(humidity_pct ** 2)']].values
h0 = -b1/(2*b2)
g = np.array([-1/(2*b2), b1/(2*b2**2)])
se = np.sqrt(g @ V @ g) * np.sqrt(phi)
print('quadratic argmin %.2f  se %.2f  95%% CI [%.1f, %.1f]' % (h0, se, h0-1.96*se, h0+1.96*se))
ms = smf.glm('defective_units + ok_units ~ C(shift) + bs(mold_c, df=4) + bs(humidity_pct, df=6) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=alpha, family=sm.families.Binomial()).fit()
print('quad dev', round(mq.deviance,1), 'spline6 dev', round(ms.deviance,1))
mc = smf.glm('defective_units + ok_units ~ '+Fq+' + I(humidity_pct**3)', data=alpha, family=sm.families.Binomial()).fit()
print('cubic term p', round(mc.pvalues['I(humidity_pct ** 3)'],4))
mf = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=data, family=sm.families.Binomial()).fit()
print('full-sample quadratic argmin', round(-mf.params['humidity_pct']/(2*mf.params['I(humidity_pct ** 2)']),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
Fq = 'C(shift) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
mq = smf.glm('defective_units + ok_units ~ '+Fq, data=alpha, family=sm.families.Binomial()).fit()
ms = smf.glm('defective_units + ok_units ~ C(shift) + bs(mold_c, df=4) + bs(humidity_pct, df=6) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=alpha, family=sm.families.Binomial()).fit()
print('quad dev', round(mq.deviance,1), 'df', mq.df_resid, '| spline6 dev', round(ms.deviance,1), 'df', ms.df_resid)
mc = smf.glm('defective_units + ok_units ~ '+Fq+' + I(humidity_pct**3)', data=alpha, family=sm.families.Binomial()).fit()
print('cubic term p', round(mc.pvalues['I(humidity_pct ** 3)'],4))
mf = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + bs(mold_c, df=4) + humidity_pct + I(humidity_pct**2) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=data, family=sm.families.Binomial()).fit()
print('full-sample quadratic argmin', round(-mf.params['humidity_pct']/(2*mf.params['I(humidity_pct ** 2)']),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
grid = np.round(np.arange(alpha.humidity_pct.min(), alpha.humidity_pct.max()+1e-9, 0.1),2)
def argmin_of(formula):
    m = smf.glm('defective_units + ok_units ~ '+formula, data=alpha, family=sm.families.Binomial()).fit()
    x = pd.DataFrame({'humidity_pct': grid})
    base = alpha.iloc[[0]*len(grid)].reset_index(drop=True)
    # predict with other covariates at the Alpha sample mean-like values
    rows = []
    res = []
    for h in grid:
        xx = alpha.copy(); xx['humidity_pct'] = h
        res.append(m.predict(xx, which='linear').mean())
    res = np.array(res)
    return grid[np.argmin(res)], round(m.deviance,1)
others = 'C(shift) + bs(mold_c, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)'
for label, h in [
    ('poly3', 'humidity_pct + I(humidity_pct**2) + I(humidity_pct**3)'),
    ('poly4', 'humidity_pct + I(humidity_pct**2) + I(humidity_pct**3) + I(humidity_pct**4)'),
    ('cr df4', 'cr(humidity_pct, df=4)'),
    ('cr df5', 'cr(humidity_pct, df=5)'),
    ('cr df6', 'cr(humidity_pct, df=6)'),
    ('cr df7', 'cr(humidity_pct, df=7)'),
    ('bs df5', 'bs(humidity_pct, df=5)'),
    ('bs df7', 'bs(humidity_pct, df=7)'),
]:
    try:
        print(label, argmin_of(h + ' + ' + others))
    except Exception as e:
        print(label, 'err', str(e)[:80])
# local quadratic around the minimum (window 15-45)
w = alpha[(alpha.humidity_pct>=15)&(alpha.humidity_pct<=45)].copy()
mw = smf.glm('defective_units + ok_units ~ humidity_pct + I(humidity_pct**2) + C(shift) + bs(mold_c, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=w, family=sm.families.Binomial()).fit()
print('window 15-45 quadratic argmin', round(-mw.params['humidity_pct']/(2*mw.params['I(humidity_pct ** 2)']),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
alpha = data[data.supplier_code=='SP-01'].reset_index(drop=True)
for lo,hi in [(15,45),(18,42),(20,40),(15,40),(20,45),(12,50),(25,50),(10,60)]:
    w = alpha[(alpha.humidity_pct>=lo)&(alpha.humidity_pct<=hi)].copy()
    mw = smf.glm('defective_units + ok_units ~ humidity_pct + I(humidity_pct**2) + C(shift) + bs(mold_c, df=4) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=w, family=sm.families.Binomial()).fit()
    print(lo,hi,'n',len(w),'argmin', round(-mw.params['humidity_pct']/(2*mw.params['I(humidity_pct ** 2)']),2))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from final_model import *
from cleaning import cl
start, end = pd.Timestamp('2025-01-06'), pd.Timestamp('2025-09-30')
days = pd.date_range(start, end)
cf_dsc = {}
sim_added = {}
for L in ['L1','L2','L3','L4']:
    logged = set(cl[cl.line==L].date)
    last = max(x for x in logged if x <= start)   # last cleaning before the period
    cleans = set(x for x in logged)
    added = []
    cur_last = last
    for day in days:
        if day in logged:
            cur_last = day
        elif (day - cur_last).days >= 14:
            added.append(day); cur_last = day; cleans.add(day)
        # cleaning before first shift: a day with a cleaning resets the count
    sim_added[L] = added
    # counterfactual days since cleaning for each batch
    cl_sorted = sorted(cleans)
    for L_, dt, idx in [(L, None, None)]:
        pass
print({L: [str(x.date()) for x in v] for L,v in sim_added.items()})
print({L: len(v) for L,v in sim_added.items()})
# compute counterfactual dsc for every unique batch (all 3000), in the same way as days_since
def dsc_cf(df):
    out = pd.Series(np.nan, index=df.index)
    for L in ['L1','L2','L3','L4']:
        logged = cl[cl.line==L].date.tolist()
        extra = sim_added[L]
        c = np.array(sorted(set(logged)|set(extra)), dtype='datetime64[ns]')
        g = df[df.line==L]
        k = np.searchsorted(c, g.date.values, side='right') - 1
        out.loc[g.index] = (g.date.values - c[k]).astype('timedelta64[D]').astype(int)
    return out
u_all = u.copy()
u_all['dsc_cf'] = dsc_cf(u_all)
print('cf dsc max', u_all.dsc_cf.max(), 'actual dsc max', u_all.dsc.max())
print('mean actual dsc', round(u_all.dsc.mean(),2), 'cf', round(u_all.dsc_cf.mean(),2))
EOF

cd $TMPDIR/work && cat > c3.py <<'EOF'
import sys; sys.path.insert(0,'/tmp/claude-0/work')
from final_model import *
from cleaning import cl
sim_added = {}
start, end = pd.Timestamp('2025-01-06'), pd.Timestamp('2025-09-30')
days = pd.date_range(start, end)
for L in ['L1','L2','L3','L4']:
    logged = set(cl[cl.line==L].date)
    cur_last = max(x for x in logged if x <= start)
    added = []
    for day in days:
        if day in logged:
            cur_last = day
        elif (day - cur_last).days >= 14:
            added.append(day); cur_last = day
    sim_added[L] = added
def dsc_cf(df):
    out = pd.Series(np.nan, index=df.index)
    for L in ['L1','L2','L3','L4']:
        c = np.array(sorted(set(cl[cl.line==L].date) | set(sim_added[L])), dtype='datetime64[ns]')
        g = df[df.line==L]
        k = np.searchsorted(c, g.date.values, side='right') - 1
        out.loc[g.index] = (g.date.values - c[k]).astype('timedelta64[D]').astype(int)
    return out
u['dsc_cf'] = dsc_cf(u)
total_units = u.units_produced.sum(); total_def = u.defective_units.sum()
print('observed rate, all unique batches', round(total_def/total_units, 6))
# (a) full model on complete cases
cc = u.dropna(subset=['mold_c','humidity_pct']).copy()
p_obs = model.predict(data)  # data == complete cases from final_model (same rows, same order)
x = data.copy(); x['dsc'] = u.loc[data.index, 'dsc_cf'].values if False else None
EOF
python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from c3 import *
ccidx = data.index
cc = u.loc[u.dropna(subset=['mold_c','humidity_pct']).index].copy()
print(len(cc))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from c3 import *
u_idx = u.set_index('row')
data_cf = data.copy()
data_cf['dsc'] = data.row.map(u_idx['dsc_cf']).values
assert data_cf.dsc.notna().all()
p_obs = model.predict(data)
p_cf = model.predict(data_cf)
delta = (data.units_produced*(p_cf - p_obs)).sum()
print('(a) full model, complete cases: delta defects', round(delta,1))
rate_a = (total_def + delta)/total_units
print('(a) C3 rate', round(rate_a,6))
# (b) reduced model (no mold/humidity) on all unique batches
red = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=u.assign(ok_units=u.units_produced-u.defective_units), family=sm.families.Binomial()).fit()
uu = u.assign(ok_units=u.units_produced-u.defective_units)
uc = uu.copy(); uc['dsc'] = uu.dsc_cf
pr_obs = red.predict(uu); pr_cf = red.predict(uc)
delta_b = (uu.units_produced*(pr_cf - pr_obs)).sum()
print('(b) reduced model, all batches: delta defects', round(delta_b,1), ' rate', round((total_def+delta_b)/total_units,6))
# sanity: observed-vs-fitted calibration
print('calibration (sum fitted defects / observed) full:', round((model.predict(data)*data.units_produced).sum()/data.defective_units.sum(),4))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from c3 import *
m = smf.ols('mold_c ~ dsc + ambient_temp_c + C(line) + C(shift) + C(supplier_code) + cycle_time_s', data=data).fit()
print('mold ~ dsc: coef', round(m.params['dsc'],3), 'p', round(m.pvalues['dsc'],4), 'R2', round(m.rsquared,3))
m2 = smf.ols('humidity_pct ~ dsc + ambient_temp_c + C(line) + C(shift) + C(supplier_code)', data=data).fit()
print('humidity ~ dsc: coef', round(m2.params['dsc'],3), 'p', round(m2.pvalues['dsc'],4))
u_idx = u.set_index('row')
data_cf = data.copy(); data_cf['dsc'] = data.row.map(u_idx['dsc_cf']).values
p_obs = model.predict(data); p_cf = model.predict(data_cf)
delta_full = (data.units_produced*(p_cf-p_obs)).sum()
uu = u.assign(ok_units=u.units_produced-u.defective_units); uc = uu.copy(); uc['dsc']=uu.dsc_cf
red = smf.glm('defective_units + ok_units ~ C(shift) + C(supplier_code) + cycle_time_s + ambient_temp_c + machine_age_years + C(line) + bs(dsc, df=4)', data=uu, family=sm.families.Binomial()).fit()
inc = uu[~uu.row.isin(data.row)]
d_inc = (inc.units_produced*(red.predict(uc.loc[inc.index]) - red.predict(uu.loc[inc.index]))).sum()
print('delta complete (full model)', round(delta_full,1), ' delta incomplete (reduced model)', round(d_inc,1))
print('(c) hybrid C3 rate', round((total_def + delta_full + d_inc)/total_units, 6))
print('incomplete rows', len(inc), 'units share', round(inc.units_produced.sum()/total_units,3))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn
import sys; sys.path.insert(0,'.')
from c3 import *
from scipy import stats
# A2 breakdown on unique batches (raw humidity text before cleaning)
raw = pd.read_csv('/tmp/edabench_claude_701mn25a/batches.csv', dtype=str, keep_default_na=False)
rb = b.copy()
rb_raw = pd.read_pickle('clean_rows.pkl')
ub = u.copy()
rawh = raw.humidity_pct.str.strip()
print('A2 unique invalid humidity:', int(ub.humidity_pct.isna().sum()))
# A4 median
print('A4 raw-converted median', round(ub.mold_temp.median(),3), 'n', ub.mold_temp.notna().sum())
corr = ub.mold_c
print('A4 with L1 replacement offset median', round(corr.median(),3))
# B1 drop-one on final model (complete cases)
terms = {'shift':'C(shift)','mold':'bs(mold_c, df=4)','humidity':'bs(humidity_pct, df=4)','cycle':'cycle_time_s','ambient':'ambient_temp_c','age':'machine_age_years','operator':'C(operator_id)','supplier':'C(supplier_code)','line':'C(line)','dsc':'bs(dsc, df=4)'}
dd = data.copy()
full = smf.glm('defective_units + ok_units ~ ' + ' + '.join(terms.values()), data=dd, family=sm.families.Binomial()).fit()
phi = full.pearson_chi2/full.df_resid
print('rank', np.linalg.matrix_rank(full.model.exog), full.model.exog.shape[1], 'phi', round(phi,2))
for k in ['shift','mold','humidity','cycle','ambient','age','operator']:
    rest = [v for kk,v in terms.items() if kk!=k]
    if k == 'operator': rest = rest  # line stays in rest via operator nesting check below
    red = smf.glm('defective_units + ok_units ~ ' + ' + '.join(rest), data=dd, family=sm.families.Binomial()).fit()
    dev = (red.deviance-full.deviance)/phi; df = red.df_resid-full.df_resid
    print(f'{k:9s} chi2={dev:9.2f} df={df:4.0f} p={stats.chi2.sf(dev,df):.3g}')
EOF
