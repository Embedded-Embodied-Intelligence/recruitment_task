ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

cat > $TMPDIR/profile.py <<'EOF'
import pandas as pd
pd.set_option('display.width', 250); pd.set_option('display.max_columns', 50)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape)
for c in b.columns:
    vc = b[c].value_counts()
    print(f"\n## {c}: nunique={b[c].nunique()}, blanks={(b[c].str.strip()=='').sum()}")
    print(vc.head(12).to_string())
print("\nduplicate batch_id rows:", b.batch_id.duplicated().sum())
print("fully duplicated rows:", b.duplicated().sum())
print(b[b.batch_id.duplicated(keep=False)].sort_values('batch_id').head(20).to_string())
EOF
python3 $TMPDIR/profile.py

cat > $TMPDIR/num.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
print(len(b), b.batch_id.nunique())
num = ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x = pd.to_numeric(b[c].str.strip(), errors='coerce')
    bad = b[c][x.isna()].unique()
    print(f"\n{c}: non-numeric={list(bad)[:10]} count={x.isna().sum()}")
    print(x.describe(percentiles=[.01,.05,.5,.95,.99]).round(2).to_dict())
    print("  value counts of extreme low/high:", x.sort_values().head(5).tolist(), x.sort_values().tail(5).tolist())
b2 = b.copy()
for c in num: b2[c]=pd.to_numeric(b2[c].str.strip(), errors='coerce')
print("\ndefective>units:", (b2.defective_units>b2.units_produced).sum())
print("zero units:", (b2.units_produced<=0).sum())
print("mold_temp histogram:")
print(np.histogram(b2.mold_temp.dropna(), bins=[0,1,100,150,180,200,230,250,300,350,400,500])[0])
print(b2[b2.mold_temp>250][['batch_id','production_date','line','mold_temp']].head(30).to_string())
print("count mold_temp>250:", (b2.mold_temp>250).sum())
print("mold_temp in 0<x<100:", b2.mold_temp[(b2.mold_temp>0)&(b2.mold_temp<100)].tolist()[:20])
EOF
python3 $TMPDIR/num.py

cat > $TMPDIR/mt.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False).drop_duplicates()
for c in ['mold_temp','humidity_pct','units_produced','defective_units','cycle_time_s','ambient_temp_c','machine_age_years']:
    b[c]=pd.to_numeric(b[c].str.strip(), errors='coerce')
b['date']=pd.to_datetime(b.production_date, errors='coerce')
print("bad dates:", b.date.isna().sum(), b.production_date[b.date.isna()].unique()[:10])
print("date range", b.date.min(), b.date.max())
b['F']=b.mold_temp>250
print(b.groupby('line').F.agg(['sum','count']))
l3=b[b.line=='L3'].sort_values('date')
print(l3.groupby(l3.date.dt.to_period('M')).F.agg(['sum','count']))
print(b[b.mold_temp>250].groupby('line').date.agg(['min','max']))
# per line, monthly mean mold temp of non-F rows
print(b[b.mold_temp>0].groupby(['line', b.date.dt.to_period('M')]).mold_temp.median().unstack(0).round(1))
print("zero mold temp by line:", b[b.mold_temp==0].line.value_counts().to_dict())
print("humidity blank by line:", b[b.humidity_pct.isna()].line.value_counts().to_dict(), " -1 by line:", b[b.humidity_pct==-1].line.value_counts().to_dict())
EOF
python3 $TMPDIR/mt.py

cat suppliers.csv && echo && cat maintenance.csv

cat > $TMPDIR/clean.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
D = '/tmp/edabench_claude_78gzd0yp/'
raw = pd.read_csv(D+'batches.csv', dtype=str, keep_default_na=False)
print("raw shift values:", sorted(raw['shift'].unique().tolist()))
print("raw supplier values:", sorted(raw['supplier_code'].unique().tolist()))
b = raw.drop_duplicates().copy()
print("after dedupe:", len(b), b.batch_id.nunique())
shift_map = {'day':'Day','d':'Day','night':'Night','n':'Night'}
b['shift'] = b['shift'].str.strip().str.lower().map(shift_map)
b['supplier_code'] = b['supplier_code'].str.strip().str.upper()
sup = pd.read_csv(D+'suppliers.csv', dtype=str)
b = b.merge(sup, on='supplier_code', how='left', validate='m:1')
print("unmatched supplier:", b.supplier_name.isna().sum())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    b[c] = pd.to_numeric(b[c].str.strip().replace('', np.nan), errors='coerce')
b['date'] = pd.to_datetime(b.production_date)
b['humidity_pct'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['mold_raw'] = b.mold_temp
b['mold_temp'] = b.mold_temp.where(b.mold_temp > 0)
b['is_F'] = b.line.eq('L3') & b.mold_temp.gt(250)
b.loc[b.is_F, 'mold_temp'] = (b.loc[b.is_F,'mold_temp'] - 32) * 5/9
b['defect_rate'] = b.defective_units / b.units_produced
b.to_pickle(TMP:=None) if False else None
EOF
cat > $TMPDIR/check.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
print(b.supplier_name.value_counts())
print(b.shift.value_counts(dropna=False))
print("humidity missing:", b.humidity_pct.isna().sum(), " mold missing:", b.mold_temp.isna().sum())
print(b.groupby('supplier_name').defect_rate.agg(['mean','count']))
EOF
python3 $TMPDIR/check.py

sed -i '/to_pickle/d' $TMPDIR/clean.py && sed -i "s/b.shift.value_counts/b['shift'].value_counts/" $TMPDIR/check.py && python3 $TMPDIR/check.py

cat > $TMPDIR/time.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
b['month']=b.date.dt.to_period('M')
g = b.groupby(['line','month']).apply(lambda d: d.defective_units.sum()/d.units_produced.sum()).unstack(0)
print("monthly pooled defect rate by line"); print(g.round(4))
print("\nmonthly mean mold temp (C) by line"); print(b.groupby(['line','month']).mold_temp.mean().unstack(0).round(2))
l1=b[b.line=='L1'].copy()
l1['wk']=l1.date.dt.to_period('W')
print("\nL1 weekly mold temp mean/median, Mar-May:")
x=l1[(l1.date>='2025-03-01')&(l1.date<='2025-05-31')]
print(x.groupby(x.date.dt.to_period('W')).mold_temp.agg(['mean','median','count']).round(2))
print("\nL1 mold_temp by day around 04-14:")
print(x[(x.date>='2025-04-07')&(x.date<='2025-04-21')].groupby('date').mold_temp.agg(['mean','count']).round(2).to_string())
EOF
python3 $TMPDIR/time.py 2>&1 | grep -v Warning

cat > $TMPDIR/feat.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
m = pd.read_csv(D+'maintenance.csv', parse_dates=['date'])
cl = m[m.event=='mold_cleaning']
def days_since(row):
    c = cl[(cl.line==row.line)&(cl.date<=row.date)].date
    return (row.date - c.max()).days if len(c) else np.nan
b['days_since_clean'] = b.apply(days_since, axis=1)
EOF
cat > $TMPDIR/glm.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
print("days_since NaN:", b.days_since_clean.isna().sum(), b.days_since_clean.describe().round(2).to_dict())
print(b.days_since_clean.value_counts().sort_index().to_string())
EOF
python3 $TMPDIR/glm.py 2>&1 | grep -v -E "raw|after|unmatched"

cat > $TMPDIR/glm2.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf
import statsmodels.api as sm
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
d['ok'] = d.units_produced - d.defective_units
d['supplier']=d.supplier_name
print("n used:", len(d))
f = 'defective_units + ok ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier) + days_since_clean'
mod = smf.glm(f, data=d, family=sm.families.Binomial()).fit()
print(mod.summary2().tables[1].round(4).to_string())
print("dispersion (pearson chi2/df):", round(mod.pearson_chi2/mod.df_resid,3))
EOF
python3 $TMPDIR/glm2.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/diag.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
d['ok']=d.units_produced-d.defective_units
import patsy
y, X = patsy.dmatrices('defective_units + ok ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + C(supplier_name) + days_since_clean', d, return_type='dataframe')
print("X shape", X.shape, "rank", np.linalg.matrix_rank(X.values))
print(X.columns[np.linalg.svd(X.values, compute_uv=False).argsort()[:0]] if False else '')
# find near-collinear columns
u,s,vt = np.linalg.svd(X.values, full_matrices=False)
print("smallest singular values:", np.round(s[-5:],6))
print("cols in smallest null vector:", [X.columns[i] for i in np.argsort(-np.abs(vt[-1]))[:5]])
print(pd.crosstab(d.line, d.shift))
print(pd.crosstab(d.operator_id, d.line).to_string())
EOF
python3 $TMPDIR/diag.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/clean.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width', 250); pd.set_option('display.max_rows', 300)
D = '/tmp/edabench_claude_78gzd0yp/'
raw = pd.read_csv(D+'batches.csv', dtype=str, keep_default_na=False)
b = raw.drop_duplicates().copy()
shift_map = {'day':'Day','d':'Day','night':'Night','n':'Night'}
b['shift'] = b['shift'].str.strip().str.lower().map(shift_map)
b['supplier_code'] = b['supplier_code'].str.strip().str.upper()
sup = pd.read_csv(D+'suppliers.csv', dtype=str)
b = b.merge(sup, on='supplier_code', how='left', validate='m:1')
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    b[c] = pd.to_numeric(b[c].str.strip().replace('', np.nan), errors='coerce')
b['date'] = pd.to_datetime(b.production_date)
b['humidity_pct'] = b.humidity_pct.where(b.humidity_pct >= 0)
b['mold_temp'] = b.mold_temp.where(b.mold_temp > 0)
b['is_F'] = b.line.eq('L3') & b.mold_temp.gt(250)
b.loc[b.is_F, 'mold_temp'] = (b.loc[b.is_F,'mold_temp'] - 32) * 5/9
b['l1_post'] = b.line.eq('L1') & b.date.ge('2025-04-14')
b['mold_temp_meas'] = b.mold_temp
b.loc[b.l1_post, 'mold_temp'] = b.loc[b.l1_post,'mold_temp'] - 8.0
b['defect_rate'] = b.defective_units / b.units_produced
b['ok_units'] = b.units_produced - b.defective_units
EOF
cat > $TMPDIR/feat.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
m = pd.read_csv(D+'maintenance.csv', parse_dates=['date'])
cl = m[m.event=='mold_cleaning']
def days_since(row):
    c = cl[(cl.line==row.line)&(cl.date<=row.date)].date
    return (row.date - c.max()).days if len(c) else np.nan
b['days_since_clean'] = b.apply(days_since, axis=1)
EOF
cat > $TMPDIR/lr.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
print("n", len(d))
def fit(f):
    return smf.glm(f, data=d, family=sm.families.Binomial()).fit()
base = 'defective_units + ok_units ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean'
M_line = fit(base + ' + C(line)')
M_op = fit(base + ' + C(operator_id)')
print("line:", round(M_line.aic,1), " operator(nested):", round(M_op.aic,1))
print("LR operator-within-line:", round(2*(M_op.llf-M_line.llf),2), "df", M_op.df_model-M_line.df_model, "p", stats.chi2.sf(2*(M_op.llf-M_line.llf), M_op.df_model-M_line.df_model))
print(M_op.summary2().tables[1].round(4).to_string())
print("pearson disp:", round(M_op.pearson_chi2/M_op.df_resid,3))
EOF
python3 $TMPDIR/lr.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/resid.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.max_rows', 400)
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
f = 'defective_units + ok_units ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days_since_clean + C(operator_id)'
M = smf.glm(f, data=d, family=sm.families.Binomial()).fit()
d['pres'] = M.resid_pearson
d['mu'] = M.fittedvalues
d['month'] = d.date.dt.to_period('M')
print(d.groupby(['line','month']).pres.mean().unstack(0).round(2))
# residual by line x 2-week block
d['blk'] = ((d.date - pd.Timestamp('2025-01-06')).dt.days // 14)
print(d.groupby(['blk','line']).pres.mean().unstack(1).round(2).to_string())
print("residual var by line:", d.groupby('line').pres.var().round(2).to_dict())
d.to_pickle(__import__('os').environ['TMPDIR']+'/d_resid.pkl')
EOF
python3 $TMPDIR/resid.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/step.py <<'EOF'
import pandas as pd, numpy as np, os
d = pd.read_pickle(os.environ['TMPDIR']+'/d_resid.pkl')
res = []
for L in ['L1','L2','L3','L4']:
    s = d[d.line==L].sort_values('date')
    best=None
    for t in pd.date_range('2025-02-01','2025-09-15'):
        pre = s[s.date<t].pres; post = s[s.date>=t].pres
        if len(pre)<20 or len(post)<20: continue
        tstat = (post.mean()-pre.mean())/np.sqrt(pre.var()/len(pre)+post.var()/len(post))
        if best is None or abs(tstat)>abs(best[1]): best=(t.date(), tstat, pre.mean(), post.mean(), len(post))
    print(L, "best step:", best[0], "t=%.2f"%best[1], "pre mean %.2f post mean %.2f n_post %d"%(best[2],best[3],best[4]))
EOF
python3 $TMPDIR/step.py

cat > $TMPDIR/binres.py <<'EOF'
import pandas as pd, numpy as np, os
d = pd.read_pickle(os.environ['TMPDIR']+'/d_resid.pkl')
for c,q in [('days_since_clean',None),('mold_temp',8),('humidity_pct',8),('cycle_time_s',8),('ambient_temp_c',8),('machine_age_years',8)]:
    x = d[c]
    if q is None:
        g = d.groupby(x.clip(upper=20)).pres.agg(['mean','count'])
    else:
        g = d.groupby(pd.qcut(x, q, duplicates='drop')).pres.agg(['mean','count'])
    print(f"\n{c}\n", g.round(2).to_string())
print("\nby shift", d.groupby('shift').pres.mean().round(2).to_dict())
print("by supplier", d.groupby('supplier_name').pres.mean().round(2).to_dict())
EOF
python3 $TMPDIR/binres.py

cat > $TMPDIR/m2.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
d['hum_c'] = d.humidity_pct - 30
def fit(f): return smf.glm(f, data=d, family=sm.families.Binomial()).fit()
core = 'defective_units + ok_units ~ mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + C(operator_id)'
M1 = fit(core + ' + C(supplier_name) + hum_c + I(hum_c**2)')
M2 = fit(core + ' + C(supplier_name) * (hum_c + I(hum_c**2))')
print("pearson disp M1:", round(M1.pearson_chi2/M1.df_resid,3), " M2:", round(M2.pearson_chi2/M2.df_resid,3))
print("AIC M1", round(M1.aic,1), "M2", round(M2.aic,1))
print(M2.summary2().tables[1].round(4).to_string())
EOF
python3 $TMPDIR/m2.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/m3.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
d['hum_c'] = d.humidity_pct - 30
core = 'defective_units + ok_units ~ mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + C(operator_id) + C(supplier_name) * (hum_c + I(hum_c**2))'
M2 = smf.glm(core, data=d, family=sm.families.Binomial()).fit()
d['pres'] = M2.resid_pearson
import pickle
# scan step in L2 by likelihood
out=[]
for t in pd.date_range('2025-05-15','2025-07-15'):
    dd = d.copy(); dd['step'] = ((dd.line=='L2')&(dd.date>=t)).astype(int)
    m = smf.glm(core+' + step', data=dd, family=sm.families.Binomial()).fit()
    out.append((t.date(), m.llf))
out = sorted(out, key=lambda x:-x[1])[:5]
print("top L2 step dates (llf):", out)
best = out[0][0]
dd = d.copy(); dd['step'] = ((dd.line=='L2')&(dd.date>=pd.Timestamp(best))).astype(int)
Ms = smf.glm(core+' + step', data=dd, family=sm.families.Binomial()).fit()
print("step coef", Ms.params['step'].round(3), "se", Ms.bse['step'].round(3), "disp", round(Ms.pearson_chi2/Ms.df_resid,3))
print("M2 disp", round(M2.pearson_chi2/M2.df_resid,3))
# step scan on residuals of M2 for all lines
res=[]
for L in ['L1','L2','L3','L4']:
    s=d[d.line==L].sort_values('date')
    bb=None
    for t in pd.date_range('2025-02-01','2025-09-15'):
        pre=s[s.date<t].pres; post=s[s.date>=t].pres
        if len(pre)<20 or len(post)<20: continue
        ts=(post.mean()-pre.mean())/np.sqrt(pre.var()/len(pre)+post.var()/len(post))
        if bb is None or abs(ts)>abs(bb[1]): bb=(t.date(),ts)
    print(L, bb[0], round(bb[1],2))
d.to_pickle(os.environ['TMPDIR']+'/d_m2.pkl') if False else None
EOF
python3 $TMPDIR/m3.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/m4.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/m3.py').read().split("# scan step")[0])
d['blk'] = ((d.date - pd.Timestamp('2025-01-06')).dt.days // 14)
print(d.groupby(['blk','line']).pres.mean().unstack(1).round(2).to_string())
print(d.groupby(d.date.dt.to_period('M')).pres.mean().round(2).to_string())
print("\nL2 daily residual mean, Jun 1-25:")
x=d[(d.line=='L2')&(d.date>='2025-06-01')&(d.date<='2025-06-25')]
print(x.groupby('date').pres.agg(['mean','count']).round(2).to_string())
EOF
python3 $TMPDIR/m4.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/l1test.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d = b.dropna(subset=['humidity_pct','mold_temp_meas']).copy()
d['hum_c']=d.humidity_pct-30
d['step']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
# uncorrected measured mold temp, L3 F->C already converted; L1 post indicator free
d['l1p']=d.l1_post.astype(int)
core = 'defective_units + ok_units ~ mold_temp_meas + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + C(operator_id) + C(supplier_name) * (hum_c + I(hum_c**2)) + step'
for label, f in [('L1 post indicator (uncorrected temp)', core+' + l1p'), ('corrected (no indicator)', core.replace('mold_temp_meas','mold_temp'))]:
    m = smf.glm(f, data=d, family=sm.families.Binomial()).fit()
    print(label, "disp", round(m.pearson_chi2/m.df_resid,3))
    if 'l1p' in f: print("  l1p coef", round(m.params['l1p'],3), "se", round(m.bse['l1p'],3), "ci", m.conf_int().loc['l1p'].round(3).tolist())
    print("  mold coef", round(m.params[[k for k in m.params.index if k.startswith('mold')][0]],4), "llf", round(m.llf,2))
EOF
python3 $TMPDIR/l1test.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/gee.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
d['hum_c']=d.humidity_pct-30
d['step']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
d['cl']=d.date.dt.dayofyear
# GEE binomial via proportions with weights
f = 'defect_rate ~ mold_temp + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + days_since_clean + C(operator_id) + C(supplier_name) * (hum_c + I(hum_c**2)) + step + C(line)'
d['w']=d.units_produced
g = smf.gee(f, groups='cl', data=d, family=sm.families.Binomial(), weights=d.w, cov_struct=sm.cov_struct.Exchangeable()).fit()
t = g.summary().tables[1]
print(t.to_string()[:6000] if False else '')
res = pd.DataFrame({'coef':g.params,'se':g.bse,'z':g.tvalues,'p':g.pvalues}).round(4)
print(res.loc[[i for i in res.index if not i.startswith('C(operator')]].to_string())
EOF
python3 $TMPDIR/gee.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn"

cat > $TMPDIR/gee2.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
import patsy
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
d['hum_c']=d.humidity_pct-30
d['step']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
d['cl']=d.date.dt.dayofyear
d['w']=d.units_produced
f = 'defect_rate ~ mold_temp + cycle_time_s + C(shift) + days_since_clean + C(operator_id) + C(supplier_name) * (hum_c + I(hum_c**2)) + step'
g = smf.gee(f, groups='cl', data=d, family=sm.families.Binomial(), weights=d.w, cov_struct=sm.cov_struct.Exchangeable()).fit()
names = list(g.params.index)
# within-line operator equality tests
ops = {'L1':['OP-01','OP-02','OP-03','OP-04','OP-05','OP-06'],'L2':['OP-07','OP-08','OP-09','OP-10','OP-11','OP-12'],
       'L3':['OP-13','OP-14','OP-15','OP-16','OP-17','OP-18'],'L4':['OP-19','OP-20','OP-21','OP-22','OP-23','OP-24']}
def idx(op):
    return None if op=='OP-01' else names.index(f'C(operator_id)[T.{op}]')
import numpy as np
for L, lst in ops.items():
    rows=[]
    base=lst[0]
    for op in lst[1:]:
        r=np.zeros(len(names))
        if idx(op) is not None: r[idx(op)]=1
        if idx(base) is not None: r[idx(base)]-=1
        rows.append(r)
    # the first operator of L1 is reference (no column) so the constraints are relative to it
    R=np.array(rows)
    w=g.wald_test(R, scalar=True)
    print(L, "Wald within-line operator equality:", float(w.statistic), "df", R.shape[0], "p", float(w.pvalue))
print("operator coefficients (relative to OP-01):")
print(pd.Series(g.params[[n for n in names if 'operator' in n]]).round(3).to_string())
EOF
python3 $TMPDIR/gee2.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn|wls_results|cov_robust"

cat >> $TMPDIR/gee2.py <<'EOF'
rows=[]
for L,lst in ops.items():
    base=lst[0]
    for op in lst[1:]:
        r=np.zeros(len(names))
        if idx(op) is not None: r[idx(op)]=1
        if idx(base) is not None: r[idx(base)]-=1
        rows.append(r)
R=np.array(rows)
w=g.wald_test(R, scalar=True)
print("JOINT within-line operator Wald:", round(float(w.statistic),2), "df", R.shape[0], "p", float(w.pvalue))
EOF
python3 $TMPDIR/gee2.py 2>&1 | grep JOINT

cat > $TMPDIR/opchk.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
pd.set_option('display.width',250)
d = b.dropna(subset=['humidity_pct','mold_temp']).copy()
print(pd.crosstab(d.operator_id, d['shift']).T.to_string())
print(pd.crosstab(d.operator_id, d.date.dt.month).to_string())
print(d.groupby('operator_id').agg(n=('batch_id','size'), cyc=('cycle_time_s','mean'), mold=('mold_temp','mean'), hum=('humidity_pct','mean'), amb=('ambient_temp_c','mean'), age=('machine_age_years','mean'), dsc=('days_since_clean','mean')).round(2).to_string())
EOF
python3 $TMPDIR/opchk.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/perm.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
import patsy
rng = np.random.default_rng(42)
d = b.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
d['hum_c']=d.humidity_pct-30
d['step']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
base = 'defective_units + ok_units ~ mold_temp + cycle_time_s + C(shift) + days_since_clean + C(supplier_name) * (hum_c + I(hum_c**2)) + step + C(line)'
full = base.replace('C(line)','C(operator_id)')
def llf(f, dd):
    return smf.glm(f, data=dd, family=sm.families.Binomial()).fit()
M0 = llf(base, d); M1 = llf(full, d)
disp = M1.pearson_chi2/M1.df_resid
obs = 2*(M1.llf-M0.llf)/disp
print("observed scaled LR:", round(obs,2), "df", M1.df_model-M0.df_model, "disp", round(disp,3))
from scipy import stats
print("chi2 p:", stats.chi2.sf(obs, M1.df_model-M0.df_model))
groups = d.groupby(['line','date']).indices
stats_null=[]
for it in range(200):
    dd = d.copy()
    newop = dd.operator_id.values.copy()
    for k, idx in groups.items():
        newop[idx] = rng.permutation(newop[idx])
    dd['operator_id'] = newop
    M1p = llf(full, dd)
    M0p = M0
    stats_null.append(2*(M1p.llf-M0p.llf)/disp)
stats_null=np.array(stats_null)
print("permutation p:", (np.sum(stats_null>=obs)+1)/(len(stats_null)+1), " null mean", stats_null.mean().round(2))
EOF
timeout 900 python3 $TMPDIR/perm.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn"

cat > $TMPDIR/leak.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d = b.copy()
d['per_def'] = d.rework_cost_eur / d.defective_units
print("rework per defect: ", d.per_def.describe().round(3).to_dict())
print("corr rework vs defective:", round(d[['rework_cost_eur','defective_units']].corr().iloc[0,1],4))
print("corr rework vs defect rate:", round(d[['rework_cost_eur','defect_rate']].corr().iloc[0,1],4))
print("qc vs defect rate corr:", round(d[['qc_inspection_min','defect_rate']].corr().iloc[0,1],4), " qc vs defective:", round(d[['qc_inspection_min','defective_units']].corr().iloc[0,1],4))
dd = d.dropna(subset=['humidity_pct','mold_temp']).copy(); dd['hum_c']=dd.humidity_pct-30
m = smf.ols('qc_inspection_min ~ defect_rate + mold_temp + cycle_time_s + C(shift) + C(supplier_name)*hum_c + ambient_temp_c + machine_age_years + C(line)', data=dd).fit()
print("qc ~ defect_rate (controls) coef", round(m.params['defect_rate'],2), "p", round(m.pvalues['defect_rate'],4), "R2", round(m.rsquared,3))
m2 = smf.ols('qc_inspection_min ~ mold_temp + cycle_time_s + C(shift) + C(supplier_name)*hum_c + ambient_temp_c + machine_age_years + C(line)', data=dd).fit()
print("qc without defect_rate R2", round(m2.rsquared,3))
EOF
python3 $TMPDIR/leak.py 2>&1 | grep -v -E "^raw|^after|^unmatched"

cat > $TMPDIR/final.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',200)
# ---- A-level answers
A1 = b.batch_id.nunique()
A2 = int(b.humidity_pct.isna().sum())
A3 = b.defective_units.sum() / b.units_produced.sum()
A4 = b.mold_temp.dropna().median()
print("A1", A1, "A2", A2, "A3 %.6f" % A3, "A4 %.4f" % A4, " valid mold n", b.mold_temp.notna().sum())
print("  raw uncorrected median mold (valid, L3 F converted, no L1 corr):", round(b.mold_temp_meas.dropna().median(),4))
print("  raw defective total", b.defective_units.sum(), "units total", b.units_produced.sum())
# ---- fit final model on complete cases
d = b.dropna(subset=['humidity_pct','mold_temp']).copy().reset_index(drop=True)
d['hum_c']=d.humidity_pct-30
d['step']=((d.line=='L2')&(d.date>=pd.Timestamp('2025-06-16'))).astype(int)
d['ok_units']=d.units_produced-d.defective_units
f = 'defective_units + ok_units ~ mold_temp + cycle_time_s + C(shift) + days_since_clean + C(line) + step + C(supplier_name)*(hum_c + I(hum_c**2))'
M = smf.glm(f, data=d, family=sm.families.Binomial()).fit()
print(M.params.round(5).to_string())
print("fit: pearson disp", round(M.pearson_chi2/M.df_resid,3))
d['p_hat']=M.predict(d)
print("calibration: observed", round(d.defective_units.sum()/d.units_produced.sum(),5), " predicted", round((d.p_hat*d.units_produced).sum()/d.units_produced.sum(),5))
M.save(__import__('os').environ['TMPDIR']+'/final_model.pkl')
d.to_pickle(__import__('os').environ['TMPDIR']+'/final_d.pkl')
# ---- C1
rows=[]
for s in ['Alpha','Beta','Gamma']:
    x=d.copy(); x['supplier_name']=s
    p=M.predict(x)
    rows.append((s, (p*x.units_produced).sum()/x.units_produced.sum()))
print("C1 counterfactual pooled defect rate by supplier:"); [print("  ",r[0], round(r[1],6)) for r in rows]
# ---- C2
grid=np.arange(12.0,72.31,0.01)
al=pd.DataFrame({'hum_c':grid-30,'humidity_pct':grid,'supplier_name':'Alpha','mold_temp':d.mold_temp.mean(),'cycle_time_s':d.cycle_time_s.mean(),'shift':'Day','days_since_clean':0,'line':'L1','step':0})
pa=M.predict(al)
print("C2 Alpha argmin humidity:", round(grid[np.argmin(pa)],3), "min p", round(pa.min(),6))
# also check at range edges
print("  min over observed range edges: ", round(pa.iloc[0],5), round(pa.iloc[-1],5))
EOF
python3 $TMPDIR/final.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn"

cat > $TMPDIR/c23.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d = pd.read_pickle(__import__('os').environ['TMPDIR']+'/final_d.pkl')
M = sm.load(__import__('os').environ['TMPDIR']+'/final_model.pkl')
# ---- C2 robustness: Alpha-only, flexible humidity (bins) with same other covariates
a = d[d.supplier_name=='Alpha'].copy()
a['hbin']=pd.cut(a.humidity_pct,[0,15,20,25,30,35,40,45,50,60,80])
f2='defective_units + ok_units ~ mold_temp + cycle_time_s + C(shift) + days_since_clean + C(line) + step + C(hbin)'
Mb=smf.glm(f2,data=a,family=sm.families.Binomial()).fit()
bins=a.hbin.cat.categories
rates=[]
for bi in bins:
    x=a[a.hbin==bi]
    rates.append((str(bi), round(x.defective_units.sum()/x.units_produced.sum(),4), len(x)))
print("Alpha observed pooled rate by humidity bin (adjusted by model coefficients later):")
for r in rates: print("  ", r)
# model-implied humidity effect via bin coefficients relative to first bin
coefs = Mb.params
hb = [0]+[coefs[k] for k in coefs.index if k.startswith('C(hbin)')]
print("bin-implied log-odds:", [round(v,3) for v in hb])
print("argmin bin:", str(bins[int(np.argmin(hb))]))
# ---- C3: simulate cleaning every <=14 days
clog = pd.read_csv(D+'maintenance.csv', parse_dates=['date'])
clog = clog[clog.event=='mold_cleaning']
days = pd.date_range('2024-12-01','2025-09-30')
newlast = {}
newsince = {}
for L in ['L1','L2','L3','L4']:
    actual = set(clog[clog.line==L].date)
    last = max([x for x in actual if x<=pd.Timestamp('2025-01-06')])
    rec={}
    for day in days:
        if day in actual: last=day
        elif (day-last).days>=14: last=day
        rec[day]=last
    newlast[L]=rec
d['last_new']=[newlast[l][t] for l,t in zip(d.line,d.date)]
d['days_new']=(d.date-d.last_new).dt.days
print("days_since old vs new (mean):", round(d.days_since_clean.mean(),3), round(d.days_new.mean(),3), " max new:", d.days_new.max(), " count>=14 new:", (d.days_new>=14).sum(), " old:", (d.days_since_clean>=14).sum())
x=d.copy(); x['days_since_clean']=x.days_new
p_old=M.predict(d); p_new=M.predict(x)
print("C3 model-based overall rate: baseline", round((p_old*d.units_produced).sum()/d.units_produced.sum(),6), " new", round((p_new*d.units_produced).sum()/d.units_produced.sum(),6))
print("observed overall on same rows", round(d.defective_units.sum()/d.units_produced.sum(),6))
# delta approach on observed defects
delta = ((p_new-p_old)*d.units_produced).sum()
print("delta expected defective units:", round(delta,1), " observed defects", d.defective_units.sum(), " observed-based new rate:", round((d.defective_units.sum()+delta)/d.units_produced.sum(),6))
EOF
python3 $TMPDIR/c23.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn"

cat > $TMPDIR/c3full.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
M = sm.load(__import__('os').environ['TMPDIR']+'/final_model.pkl')
f = b.copy()
f['mold_temp'] = f.groupby('line').mold_temp.transform(lambda s: s.fillna(s.median()))
f['humidity_pct'] = f.groupby('supplier_name').humidity_pct.transform(lambda s: s.fillna(s.median()))
f['hum_c']=f.humidity_pct-30
f['step']=((f.line=='L2')&(f.date>=pd.Timestamp('2025-06-16'))).astype(int)
print("missing after impute:", f[['mold_temp','humidity_pct']].isna().sum().to_dict())
clog = pd.read_csv(D+'maintenance.csv', parse_dates=['date']); clog=clog[clog.event=='mold_cleaning']
days = pd.date_range('2024-12-01','2025-09-30'); newlast={}
for L in ['L1','L2','L3','L4']:
    actual=set(clog[clog.line==L].date)
    last=max([x for x in actual if x<=pd.Timestamp('2025-01-06')]); rec={}
    for day in days:
        if day in actual: last=day
        elif (day-last).days>=14: last=day
        rec[day]=last
    newlast[L]=rec
f['days_new']=[(t-newlast[l][t]).days for l,t in zip(f.line,f.date)]
x=f.copy(); x['days_since_clean']=x.days_new
p_old=M.predict(f); p_new=M.predict(x)
U=f.units_produced.sum()
base=(p_old*f.units_produced).sum()/U; new=(p_new*f.units_produced).sum()/U
obs=f.defective_units.sum()/U
print("full-data: observed %.6f  model baseline %.6f  model new %.6f" % (obs, base, new))
print("observed + model delta: %.6f" % (obs + (p_new-p_old).mul(f.units_produced).sum()/U))
print("batches with days_since>=14 before:", (f.days_since_clean>=14).sum())
EOF
python3 $TMPDIR/c3full.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn"

cat > $TMPDIR/c1full.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/feat.py').read())
import statsmodels.api as sm
M = sm.load(__import__('os').environ['TMPDIR']+'/final_model.pkl')
f = b.copy()
f['mold_temp'] = f.groupby('line').mold_temp.transform(lambda s: s.fillna(s.median()))
f['humidity_pct'] = f.groupby('supplier_name').humidity_pct.transform(lambda s: s.fillna(s.median()))
f['hum_c']=f.humidity_pct-30
f['step']=((f.line=='L2')&(f.date>=pd.Timestamp('2025-06-16'))).astype(int)
for s in ['Alpha','Beta','Gamma']:
    x=f.copy(); x['supplier_name']=s
    print(s, round((M.predict(x)*x.units_produced).sum()/x.units_produced.sum(),6))
print("observed by supplier:", f.groupby('supplier_name').apply(lambda g: round(g.defective_units.sum()/g.units_produced.sum(),5)).to_dict())
EOF
python3 $TMPDIR/c1full.py 2>&1 | grep -v -E "^raw|^after|^unmatched|Warning|warn"
