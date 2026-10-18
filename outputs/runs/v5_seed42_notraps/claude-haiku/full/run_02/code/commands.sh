pwd && ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l "$f"; head -5 "$f"; done

cat > $TMPDIR/explore.py <<'EOF'
import pandas as pd
pd.set_option('display.width',250); pd.set_option('display.max_columns',50)
b = pd.read_csv('batches.csv', dtype=str, keep_default_na=False)
print(b.shape); print(b.dtypes)
for c in b.columns:
    vals = b[c]
    print(c, 'nunique', vals.nunique(), 'empty', (vals.str.strip()=='').sum())
print(b.batch_id.value_counts().head(10))
print('line', b.line.value_counts(dropna=False).to_dict())
print('shift', b.shift.value_counts().to_dict() if 'shift' in b else '')
print('shift', b['shift'].value_counts().to_dict())
print('operator', b.operator_id.value_counts().to_dict())
print('supplier', b.supplier_code.value_counts().to_dict())
print('date formats', b.production_date.str.len().value_counts().to_dict())
print(b.production_date.sample(15, random_state=1).tolist())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units']:
    bad = b[c][pd.to_numeric(b[c], errors='coerce').isna()]
    print(c, 'non-numeric:', bad.value_counts().head(15).to_dict())
s = pd.read_csv('suppliers.csv', dtype=str)
print(s)
m = pd.read_csv('maintenance.csv', dtype=str, keep_default_na=False)
print(m.event.value_counts().to_dict()); print(m.line.value_counts().to_dict())
print(m[m.note!=''].to_string())
print(m.date.str.len().value_counts().to_dict())
EOF
python3 $TMPDIR/explore.py

cd "$PWD" && sed -i "/b.shift.value_counts/d" $TMPDIR/explore.py && python3 $TMPDIR/explore.py 2>&1 | tail -n +30

python3 - <<'EOF'
import os,re
p=os.path.join(os.environ['TMPDIR'],'explore.py')
src=open(p).read().splitlines()
src=[l for l in src if 'b.shift.value_counts' not in l]
open(p,'w').write('\n'.join(src)+'\n')
EOF
python3 $TMPDIR/explore.py 2>&1 | tail -n +30

cat > $TMPDIR/q.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_columns',50)
b = pd.read_csv('batches.csv')
print(b.dtypes)
print(b.describe().T)
cols=[c for c in b.columns if c!='batch_id']
print('full-row dups excl batch_id:', b.duplicated(subset=cols).sum())
print('dups on batch_id:', b.batch_id.duplicated().sum())
print('dups excl batch_id & humidity:', b.duplicated(subset=[c for c in cols if c not in('humidity_pct',)]).sum())
print(b.isna().sum())
print('defective>units', (b.defective_units>b.units_produced).sum(), 'units<=0', (b.units_produced<=0).sum(), 'neg def', (b.defective_units<0).sum())
print(b.groupby('line').mold_temp.describe())
print(b.groupby('line').humidity_pct.describe())
print(b.groupby('line').ambient_temp_c.describe())
print(b.groupby('supplier_code').cycle_time_s.describe())
print(b.groupby('supplier_code').humidity_pct.describe())
print(b.production_date.min(), b.production_date.max())
print(pd.to_datetime(b.production_date, errors='coerce').isna().sum())
print(b.production_date.str.slice(0,4).value_counts())
print((b.humidity_pct<0).sum(), (b.humidity_pct>100).sum())
print(b.humidity_pct.sort_values().head(10).tolist(), b.humidity_pct.sort_values().dropna().tail(10).tolist())
print(b.mold_temp.sort_values().head(10).tolist(), b.mold_temp.sort_values().dropna().tail(10).tolist())
EOF
python3 $TMPDIR/q.py

cat > $TMPDIR/q2.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_columns',50)
b = pd.read_csv('batches.csv')
print(b.humidity_pct.value_counts().head(8))
print('rows humidity==12.1:', (b.humidity_pct==12.1).sum(), 'by line', b[b.humidity_pct==12.1].line.value_counts().to_dict())
print('humidity<=12.1 count', (b.humidity_pct<=12.1).sum())
print(np.sort(b.humidity_pct.dropna().unique())[:25])
print(b.humidity_pct.dropna().round(0).value_counts().sort_index().head(10))
print(b.mold_temp.value_counts().head(5))
b['d']=pd.to_datetime(b.production_date)
l1=b[b.line=='L1'].copy()
l1['after']=l1.d>=pd.Timestamp('2025-04-14')
print(l1.groupby('after').mold_temp.describe())
print(b.mold_temp.round(0).value_counts().sort_index().to_string()[:0])
print(b.groupby(b.d.dt.month).agg(n=('batch_id','size'),dr=('defective_units','sum'),u=('units_produced','sum')).assign(rate=lambda x:x.dr/x.u))
print(b.groupby(b.d.dt.month).mold_temp.mean())
EOF
python3 $TMPDIR/q2.py

cat > $TMPDIR/q3.py <<'EOF'
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_columns',50)
b = pd.read_csv('batches.csv')
b['d']=pd.to_datetime(b.production_date)
b['rate']=b.defective_units/b.units_produced
# mold temp by line by month
print(b.pivot_table(index=b.d.dt.month,columns='line',values='mold_temp',aggfunc='mean').round(2))
# L1 around sensor replacement, 2 week windows
l1=b[b.line=='L1']
print(l1[(l1.d>='2025-03-01')&(l1.d<='2025-05-31')].groupby(pd.Grouper(key='d',freq='7D')).agg(mt=('mold_temp','mean'),n=('mold_temp','size'),rate=('rate','mean')).round(3))
# defect rate by line by month (pooled)
g=b.groupby(['line',b.d.dt.month]).apply(lambda x: x.defective_units.sum()/x.units_produced.sum()).unstack(0).round(4)
print(g)
print(b.groupby('line').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()))
print(b.groupby('supplier_code').apply(lambda x: x.defective_units.sum()/x.units_produced.sum()))
print(b[['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','rate']].corr().round(3))
EOF
python3 $TMPDIR/q3.py

python3 -c "import statsmodels, sklearn, scipy; print(statsmodels.__version__, sklearn.__version__, scipy.__version__)" 2>&1; python3 -c "import pandas, numpy; print(pandas.__version__, numpy.__version__)"

python3 -c "import statsmodels; print(statsmodels.__version__)"; python3 -c "import scipy; print(scipy.__version__)" ; python3 -c "import numpy; print('np ok')"

cat > $TMPDIR/m1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
pd.set_option('display.width',250)
b = pd.read_csv('batches.csv').dropna(subset=['mold_temp','humidity_pct']).copy()
b['d']=pd.to_datetime(b.production_date)
b['bad']=b.units_produced-b.defective_units
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
f_lin='defective_units + bad ~ mt_c + h_c + ct_c + age_c + amb_c + C(operator_id) + C(shift) + C(supplier_code) + C(line)'
def fit(f,d=b):
    return smf.glm(f, data=d, family=sm.families.Binomial(), freq_weights=None).__class__
# use proportion form with var weights
m=smf.glm('defective_units/units_produced ~ mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)', data=b, family=sm.families.Binomial(), var_weights=b.units_produced).fit()
print(m.summary())
m2=smf.glm('defective_units/units_produced ~ mt_c + I(mt_c**2) + h_c + I(h_c**2) + ct_c + I(ct_c**2) + age_c + amb_c + C(shift) + C(supplier_code) + C(line)', data=b, family=sm.families.Binomial(), var_weights=b.units_produced).fit()
print(m2.summary())
print('dev lin', m.deviance, 'dev quad', m2.deviance, 'AIC', m.aic, m2.aic)
EOF
python3 $TMPDIR/m1.py

cat > $TMPDIR/m1.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm
import patsy
pd.set_option('display.width',250)
b = pd.read_csv('batches.csv').dropna(subset=['mold_temp','humidity_pct']).copy()
b['d']=pd.to_datetime(b.production_date)
b['good']=b.units_produced-b.defective_units
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
def glm(rhs):
    X=patsy.dmatrix(rhs, b, return_type='dataframe')
    y=np.column_stack([b.defective_units,b.good])
    return sm.GLM(y,X,family=sm.families.Binomial()).fit()
lin='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line) + C(operator_id)'
quad=lin+' + I(mt_c**2) + I(h_c**2) + I(ct_c**2)'
m=glm(lin); print(m.summary()); 
m2=glm(quad); print(m2.summary())
print('AIC lin',m.aic,'quad',m2.aic, 'dev', m.deviance, m2.deviance, 'pearson disp', m2.pearson_chi2/m2.df_resid)
EOF
python3 $TMPDIR/m1.py

cat > $TMPDIR/m2.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
pd.set_option('display.width',250); pd.set_option('display.max_columns',60)
b = pd.read_csv('batches.csv').dropna(subset=['mold_temp','humidity_pct']).copy()
b['good']=b.units_produced-b.defective_units
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
print(pd.crosstab(b.operator_id,b.line))
X=patsy.dmatrix('mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line) + C(operator_id)', b, return_type='dataframe')
print('cols',X.shape[1],'rank',np.linalg.matrix_rank(X.values))
print(X.columns[np.linalg.svd(X.values,full_matrices=False)[2][-1].argsort()[-3:]] if False else '')
# find collinear groups
u,s,vt=np.linalg.svd(X.values,full_matrices=False)
print('small sv', s[-4:])
idx=np.where(np.abs(vt[-1])>0.1)[0]; print([X.columns[i] for i in idx])
print(pd.crosstab(b.supplier_code,b.line))
print(pd.crosstab(b.shift,b.line))
EOF
python3 $TMPDIR/m2.py

cat > $TMPDIR/m3.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
pd.set_option('display.width',250); pd.set_option('display.max_columns',60); pd.set_option('display.max_rows',200)
mt=pd.read_csv('maintenance.csv'); mt['date']=pd.to_datetime(mt.date)
print(mt[mt.event=='mold_cleaning'].groupby('line').date.agg(['min','max','count']))
for l,g in mt[mt.event=='mold_cleaning'].groupby('line'):
    d=g.date.sort_values().diff().dt.days
    print(l, 'gaps>14:', d[d>14].tolist(), 'dates', g.date.sort_values().dt.strftime('%m-%d').tolist())
EOF
python3 $TMPDIR/m3.py

cat > $TMPDIR/common.py <<'EOF'
import pandas as pd, numpy as np, statsmodels.api as sm, patsy
pd.set_option('display.width',250); pd.set_option('display.max_columns',60); pd.set_option('display.max_rows',300)
b0 = pd.read_csv('batches.csv')
b0['d']=pd.to_datetime(b0.production_date)
b0['good']=b0.units_produced-b0.defective_units
b0['rate']=b0.defective_units/b0.units_produced
mt=pd.read_csv('maintenance.csv'); mt['date']=pd.to_datetime(mt.date)
cl=mt[mt.event=='mold_cleaning']
def days_since(row_d, line, cl_dates):
    prev=cl_dates[cl_dates<=row_d]
    return (row_d-prev.max()).days if len(prev) else np.nan
cl_by={l:g.date.sort_values().reset_index(drop=True) for l,g in cl.groupby('line')}
b0['days_since']=[days_since(r.d, r.line, cl_by[r.line]) for r in b0.itertuples()]
EOF
cat > $TMPDIR/m4.py <<'EOF'
import sys; sys.path.insert(0,'.')
exec(open(sys.argv[1] if False else __import__('os').environ['TMPDIR']+'/common.py').read())
print(b0.days_since.describe()); print(b0.days_since.isna().sum())
print(b0.groupby(pd.cut(b0.days_since,[-1,0,3,7,10,14,18,22,30,60,200])).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()})))
EOF
python3 $TMPDIR/m4.py

cat > $TMPDIR/m5.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=b0.dropna(subset=['mold_temp','humidity_pct']).copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
b['post_l1']=((b.line=='L1')&(b.d>='2025-04-14')).astype(int)
b['L1pre']=((b.line=='L1')&(b.d<'2025-04-14')).astype(int)
def fit(rhs, d=b):
    X=patsy.dmatrix(rhs, d, return_type='dataframe')
    y=np.column_stack([d.defective_units,d.good])
    r=sm.GLM(y,X,family=sm.families.Binomial()).fit(scale='X2')
    return r
base='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
r0=fit(base); print('base', r0.aic, r0.llf)
for name,add in [('days_since','days_since'),('operator','C(operator_id)'),('L1 mt pre-post','mt_c:L1pre + mt_c:post_l1'),
                 ('sup x h','h_c:C(supplier_code)'),('sup x mt','mt_c:C(supplier_code)'),('sup x ct','ct_c:C(supplier_code)'),
                 ('h quad','I(h_c**2)'),('mt quad','I(mt_c**2)'),('ct quad','I(ct_c**2)'),('line x h','h_c:C(line)'),('line x mt','mt_c:C(line)')]:
    r=fit(base+' + '+add)
    from scipy.stats import chi2
    dfd=r.df_model-r0.df_model; lr=2*(r.llf-r0.llf)
    print(f'{name:18s} dfdiff={dfd:.0f} LR={lr:8.2f} p={chi2.sf(lr,dfd):.4g}')
r=fit(base); print(r.summary())
print('dispersion X2', r.scale)
EOF
python3 $TMPDIR/m5.py 2>&1 | grep -v Warning

cat > $TMPDIR/m6.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=b0.dropna(subset=['mold_temp','humidity_pct']).copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X=patsy.dmatrix(rhs,b,return_type='dataframe'); y=np.column_stack([b.defective_units,b.good])
r=sm.GLM(y,X,family=sm.families.Binomial()).fit()
p=r.predict(X)
b['p']=p
b['pres']=(b.defective_units-b.units_produced*p)/np.sqrt(b.units_produced*p*(1-p))
print('overall pearson disp', (b.pres**2).mean())
print(b.groupby('line').pres.apply(lambda x:(x**2).mean()).round(2))
print(b.groupby('operator_id').pres.agg(['mean','size']).round(2).T)
# monthly residual by line
b['m']=b.d.dt.month
print(b.pivot_table(index='m',columns='line',values='pres',aggfunc='mean').round(2))
print(b.pivot_table(index='m',columns='line',values='pres',aggfunc=lambda x:(x**2).mean()).round(2))
# weekly residual sums for each line
for l,g in b.groupby('line'):
    w=g.set_index('d').pres.resample('14D').agg(['mean','size'])
    print(l, w['mean'].round(2).tolist())
b.to_pickle(os.environ['TMPDIR']+'/b.pkl')
EOF
python3 $TMPDIR/m6.py 2>&1 | grep -v Warn

cat > $TMPDIR/m7.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X0=patsy.dmatrix(rhs,b,return_type='dataframe'); y=np.column_stack([b.defective_units,b.good])
r0=sm.GLM(y,X0,family=sm.families.Binomial()).fit()
phi=r0.pearson_chi2/r0.df_resid
res=[]
for l in ['L1','L2','L3','L4']:
    g=b[b.line==l].sort_values('d')
    dates=sorted(g.d.unique())
    best=None
    for t in dates[15:-15]:
        ind=((b.line==l)&(b.d>=t)).astype(float)
        X=X0.copy(); X['post']=ind.values
        r=sm.GLM(y,X,family=sm.families.Binomial()).fit()
        lr=(r.deviance_llf if False else 2*(r.llf-r0.llf))/phi
        if best is None or lr>best[1]: best=(t,lr,r.params['post'])
    res.append((l,pd.Timestamp(best[0]).date(),round(best[1],2),round(best[2],3)))
    print(res[-1])
EOF
python3 $TMPDIR/m7.py 2>&1 | grep -v Warn

cat > $TMPDIR/m8.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
for l,g in b.groupby('line'):
    g=g.sort_values('d')
    print(l)
    print(g.set_index('d').resample('MS')[['units_produced','defective_units','cycle_time_s','mold_temp','humidity_pct','ambient_temp_c']].mean().round(2).assign(n=g.set_index('d').resample('MS').size()).T.to_string())
# batches per day per line and gaps
print(b.groupby('line').d.agg(['min','max','nunique']))
# time trend of residual per line (linear)
for l,g in b.groupby('line'):
    t=(g.d-g.d.min()).dt.days/30
    X=sm.add_constant(t.values); yy=g.pres.values
    print(l, 'slope per month', np.polyfit(t,yy,1)[0].round(4))
EOF
python3 $TMPDIR/m8.py 2>&1 | grep -v Warn

cat > $TMPDIR/m9.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X=patsy.dmatrix(rhs,b,return_type='dataframe').values
n=b.units_produced.values.astype(float)
y=np.column_stack([b.defective_units,b.good])
r0=sm.GLM(y,X,family=sm.families.Binomial()).fit()
phi=r0.pearson_chi2/r0.df_resid
p=r0.predict(X)
W=n*p*(1-p)
XtWX_inv=np.linalg.inv(X.T@(X*W[:,None]))
lines=b.line.values; dts=b.d.values
cands=[]
for l in ['L1','L2','L3','L4']:
    ds=np.sort(np.unique(b.d[b.line==l].values))
    for t in ds[15:-15]:
        cands.append((l,t))
masks=[(lines==l)&(dts>=t) for l,t in cands]
Z=np.array(masks,dtype=float).T  # N x K
def stats(ydef, p_):
    mu=n*p_
    s=Z.T@(ydef-mu)
    WZ=Z*W[:,None]
    I=(Z.T@WZ) - (WZ.T@X)@XtWX_inv@(X.T@WZ)
    return s**2/np.diag(I)/phi
obs=stats(b.defective_units.values.astype(float),p)
print('observed max', obs.max(), cands[int(obs.argmax())], 'by line max', [round(obs[[i for i,c in enumerate(cands) if c[0]==l]].max(),2) for l in ['L1','L2','L3','L4']])
rng=np.random.default_rng(0)
mx=[]
for _ in range(2000):
    yd=rng.binomial(n.astype(int), p)
    mx.append(stats(yd.astype(float),p).max())
mx=np.array(mx)
print('null 95% max', np.quantile(mx,0.95), 'p-value', (mx>=obs.max()).mean())
EOF
python3 $TMPDIR/m9.py 2>&1 | grep -v Warn

cat >> $TMPDIR/m9.py <<'EOF'
rng=np.random.default_rng(1)
yd=rng.binomial(n.astype(int), p).astype(float)
s_=stats(yd,p)
k=int(s_.argmax()); print('sim max', s_.max(), cands[k], 'nbatches', masks[k].sum())
print('median per-cand', np.median(s_), 'mean', s_.mean())
print(np.sort(s_)[-10:])
EOF
python3 $TMPDIR/m9.py 2>&1 | grep -v Warn | tail -5

cat > $TMPDIR/m10.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X=patsy.dmatrix(rhs,b,return_type='dataframe').values
n=b.units_produced.values.astype(float)
y=np.column_stack([b.defective_units,b.good])
r0=sm.GLM(y,X,family=sm.families.Binomial()).fit()
p=r0.predict(X)
print('check p vs obs rate', np.corrcoef(p, b.rate)[0,1], p[:3], b.rate.values[:3])
print('pearson chi2', r0.pearson_chi2, 'df', r0.df_resid, 'phi', r0.pearson_chi2/r0.df_resid)
obs_pearson=((b.defective_units-n*p)**2/(n*p*(1-p))).sum(); print('manual phi', obs_pearson/r0.df_resid)
rng=np.random.default_rng(0)
yd=rng.binomial(n.astype(int),p)
print('sim pearson/N', (((yd-n*p)**2)/(n*p*(1-p))).mean())
EOF
python3 $TMPDIR/m10.py 2>&1 | grep -v Warn

cat > $TMPDIR/m11.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X=patsy.dmatrix(rhs,b,return_type='dataframe').values
n=b.units_produced.values.astype(float)
y=np.column_stack([b.defective_units,b.good])
r0=sm.GLM(y,X,family=sm.families.Binomial()).fit()
phi=r0.pearson_chi2/r0.df_resid
p=r0.predict(X)
W=n*p*(1-p)
XtWX_inv=np.linalg.inv(X.T@(X*W[:,None]))
lines=b.line.values; dts=b.d.values
cands=[]
for l in ['L1','L2','L3','L4']:
    g=b[b.line==l]
    ds=np.sort(g.d.values); k0=int(0.15*len(ds)); k1=int(0.85*len(ds))
    for t in np.unique(ds[k0:k1]):
        cands.append((l,t))
Z=np.array([(lines==l)&(dts>=t) for l,t in cands],dtype=float).T
def stats(ydef,p_,phi_):
    s=Z.T@(ydef-n*p_)
    WZ=Z*W[:,None]
    I=(Z.T@WZ)-(WZ.T@X)@XtWX_inv@(X.T@WZ)
    return s**2/np.diag(I)/phi_
obs=stats(b.defective_units.values.astype(float),p,phi)
k=int(obs.argmax()); print('observed max', round(obs[k],2), cands[k][0], pd.Timestamp(cands[k][1]).date(), 'by line', {l:round(obs[[i for i,c in enumerate(cands) if c[0]==l]].max(),2) for l in ['L1','L2','L3','L4']})
rng=np.random.default_rng(0)
mx=np.array([stats(rng.binomial(n.astype(int),p).astype(float),p,1.0).max() for _ in range(2000)])
print('null q95', np.quantile(mx,0.95), 'q99', np.quantile(mx,0.99), 'p', (mx>=obs.max()).mean())
EOF
python3 $TMPDIR/m11.py 2>&1 | grep -v Warn

cat >> $TMPDIR/m11.py <<'EOF'
rng=np.random.default_rng(5)
yd=rng.binomial(n.astype(int),p).astype(float)
s=Z.T@(yd-n*p); WZ=Z*W[:,None]; I=(Z.T@WZ)-(WZ.T@X)@XtWX_inv@(X.T@WZ)
st=s**2/np.diag(I)
o=np.argsort(st)[-5:]
for i in o: print(cands[i][0], pd.Timestamp(cands[i][1]).date(), round(st[i],2), 'I',round(np.diag(I)[i],2), 'Zsum', Z[:,i].sum(), 's', round(s[i],2))
print('mean st', st.mean(), 'median', np.median(st))
print('min eig of I', np.linalg.eigvalsh(I).min())
EOF
python3 $TMPDIR/m11.py 2>&1 | grep -v Warn | tail -9

cat > $TMPDIR/m12.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X=patsy.dmatrix(rhs,b,return_type='dataframe').values
n=b.units_produced.values.astype(float)
y=np.column_stack([b.defective_units,b.good])
r0=sm.GLM(y,X,family=sm.families.Binomial()).fit()
phi=r0.pearson_chi2/r0.df_resid
p=r0.predict(X)
W=n*p*(1-p)
A=X.T@(X*W[:,None]); Ainv=np.linalg.inv(A)
lines=b.line.values; dts=b.d.values
cands=[]
for l in ['L1','L2','L3','L4']:
    ds=np.sort(b.d[b.line==l].values); k0=int(0.15*len(ds)); k1=int(0.85*len(ds))
    for t in np.unique(ds[k0:k1]): cands.append((l,t))
Z=np.array([(lines==l)&(dts>=t) for l,t in cands],dtype=float).T
ZWX=(Z*W[:,None]).T@X
def stats(ydef,p_,phi_):
    u=X.T@(ydef-n*p_)
    s=Z.T@(ydef-n*p_)-ZWX@Ainv@u
    WZ=Z*W[:,None]
    I=(Z.T@WZ)-ZWX@Ainv@ZWX.T
    return s**2/np.diag(I)/phi_
obs=stats(b.defective_units.values.astype(float),p,phi)
k=int(obs.argmax()); print('observed max', round(obs[k],2), cands[k][0], pd.Timestamp(cands[k][1]).date(), 'by line', {l:round(float(obs[[i for i,c in enumerate(cands) if c[0]==l]].max()),2) for l in ['L1','L2','L3','L4']})
rng=np.random.default_rng(0)
mx=np.array([stats(rng.binomial(n.astype(int),p).astype(float),p,1.0).max() for _ in range(3000)])
print('null q90', np.quantile(mx,0.90).round(2),'q95', np.quantile(mx,0.95).round(2), 'q99', np.quantile(mx,0.99).round(2), 'p', (mx>=obs.max()).mean())
EOF
python3 $TMPDIR/m12.py 2>&1 | grep -v Warn

cat > $TMPDIR/m13.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
from scipy.stats import chi2
b=b0.dropna(subset=['mold_temp','humidity_pct']).copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
phi=2.268
def fit(rhs,d=b):
    X=patsy.dmatrix(rhs,d,return_type='dataframe'); y=np.column_stack([d.defective_units,d.good])
    return sm.GLM(y,X,family=sm.families.Binomial()).fit()
base='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
r0=fit(base)
def lrt(add,name):
    r=fit(base+' + '+add); dfd=r.df_model-r0.df_model; lr=2*(r.llf-r0.llf)/phi
    print(f'{name:28s} df={dfd:.0f} scaledLR={lr:7.2f} p={chi2.sf(lr,dfd):.4f}')
    return r
r=lrt('h_c:C(supplier_code)','humidity x supplier')
print(r.params.filter(like='h_c').round(4))
lrt('ct_c:C(supplier_code)','cycle x supplier')
lrt('I(h_c**2)','humidity quad')
lrt('I(h_c**2):C(supplier_code)','humidity quad x supplier')
b['old14']=(b.days_since>14).astype(int)
b['ds_over']=np.maximum(b.days_since-14,0)
lrt('old14','days>14 indicator')
lrt('days_since','days linear')
lrt('ds_over','days over 14 slope')
lrt('C(operator_id)','operator (within line)')
# humidity nonparametric by supplier (residual to base w/o humidity)
rb=fit('mt_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)')
bins=pd.cut(b.humidity_pct,[12,20,30,40,50,60,73])
t=b.assign(bin=bins).groupby(['supplier_code','bin']).apply(lambda x: pd.Series({'n':len(x),'rate':x.defective_units.sum()/x.units_produced.sum()}))
print(t.unstack(0).round(4))
EOF
python3 $TMPDIR/m13.py 2>&1 | grep -v Warn

cat > $TMPDIR/m14.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=b0.dropna(subset=['mold_temp','humidity_pct']).copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
b['pre']=((b.line=='L1')&(b.d<'2025-04-14')).astype(int)
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X0=patsy.dmatrix(rhs,b,return_type='dataframe'); y=np.column_stack([b.defective_units,b.good])
ll={}
for delta in np.arange(-4,4.01,0.5):
    mt=b.mold_temp.values - delta*b.pre.values
    X=X0.copy(); X['mt_c']=mt-210
    r=sm.GLM(y,X.values,family=sm.families.Binomial()).fit()
    ll[delta]=round(r.llf,2)
print(ll)
# L1 pre-replacement mold temp vs other lines same period
pre=b0[(b0.d<'2025-04-14')]
print(pre.groupby('line').mold_temp.agg(['mean','median','count']).round(2))
post=b0[(b0.d>='2025-04-14')]
print(post.groupby('line').mold_temp.agg(['mean','median','count']).round(2))
# stuck humidity: same value repeated same line & date
h=b0.dropna(subset=['humidity_pct'])
dup=h[h.duplicated(['line','production_date','humidity_pct'],keep=False)]
print('same line-day humidity dups', len(dup))
print(h.groupby(['line','production_date']).humidity_pct.agg(lambda x: x.duplicated().sum()).sum())
# normalized batch id
print('normalized dup ids', b0.batch_id.str.strip().str.upper().duplicated().sum())
print(b0.batch_id.str.match(r'^B-\d{6}$').value_counts())
print('A1 unique', b0.batch_id.nunique(), 'rows', len(b0))
print('A2 missing humidity', b0.humidity_pct.isna().sum())
print('A3', b0.defective_units.sum()/b0.units_produced.sum(), b0.defective_units.sum(), b0.units_produced.sum())
print('A4 median mold', b0.mold_temp.median(), b0.mold_temp.count())
EOF
python3 $TMPDIR/m14.py 2>&1 | grep -v Warn

cat > $TMPDIR/c1.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=b0.copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
cc=b.dropna(subset=['mold_temp','humidity_pct']).copy()
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
Xc=patsy.dmatrix(rhs,cc,return_type='dataframe')
yc=np.column_stack([cc.defective_units,cc.good])
r=sm.GLM(yc,Xc,family=sm.families.Binomial()).fit()
names=Xc.columns
beta=pd.Series(r.params,index=names)
print(beta.round(4).to_string())
# design for all rows with mt/h imputed by MC over complete-case empirical distribution
rng=np.random.default_rng(42); K=400
def eta_rows(df, mtv, hv):
    d=df.copy(); d['mt_c']=mtv-210; d['h_c']=hv-33
    return d
out={}
sup_codes=['SP-01','SP-02','SP-03']
mt_draw=cc.mold_temp.values; h_draw=cc.humidity_pct.values
rows=b.copy()
miss=rows.mold_temp.isna()|rows.humidity_pct.isna()
# expanded array for each batch: K realizations
idx=np.arange(len(rows))
rep=np.repeat(idx,K)
E=rows.iloc[rep].reset_index(drop=True)
mt_vals=E.mold_temp.values.copy(); h_vals=E.humidity_pct.values.copy()
m_mt=np.isnan(mt_vals); m_h=np.isnan(h_vals)
mt_vals[m_mt]=rng.choice(mt_draw,m_mt.sum()); h_vals[m_h]=rng.choice(h_draw,m_h.sum())
E['mt_c']=mt_vals-210; E['h_c']=h_vals-33
# gather linear predictor pieces
def lin(D, sup):
    Dx=D.copy(); Dx['supplier_code']=sup
    X=patsy.build_design_matrices([Xc.design_info],Dx,return_type='dataframe')[0]
    return X.values@beta.values
res={}
for s in sup_codes:
    # counterfactual: supplier s, cycle time = recipe 30
    Dx=E.copy(); Dx['ct_c']=0.0
    eta=lin(Dx,s)
    p=1/(1+np.exp(-eta))
    exp_def=(p*E.units_produced.values).reshape(-1,K).mean(axis=1)
    res[s]=exp_def.sum()/rows.units_produced.sum()
print('counterfactual overall rate (supplier, 30 s recipe):')
for k,v in res.items(): print(k, round(v,6))
# observed-cycle version for reference
EOF
python3 $TMPDIR/c1.py 2>&1 | grep -v Warn

cat > $TMPDIR/c3.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=b0.dropna(subset=['mold_temp','humidity_pct']).copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line) + days_since'
X=patsy.dmatrix(rhs,b,return_type='dataframe'); y=np.column_stack([b.defective_units,b.good])
r=sm.GLM(y,X,family=sm.families.Binomial()).fit()
print('days_since coef', r.params['days_since'], 'SE scaled', r.bse['days_since']*np.sqrt(2.268))
# new schedule: add cleanings so no gap exceeds 14 days, per line
new_cl={}
end=pd.Timestamp('2025-09-30')
for l,g in cl.groupby('line'):
    dates=sorted(g.date); allc=list(dates)
    cur=dates[0]; out=[]
    rec=sorted(dates)
    # walk forward: if next recorded cleaning is more than 14 days ahead, insert at +14
    times=sorted(rec)+[pd.Timestamp('2100-01-01')]
    last=pd.Timestamp('2024-12-29') if l=='L3' else rec[0]
    add=[]
    i=0; t=last
    while True:
        nxt=times[i]
        if nxt-t>pd.Timedelta(days=14):
            t=t+pd.Timedelta(days=14); add.append(t); continue
        t=nxt; i+=1
        if t>end: break
    new_cl[l]=sorted(set(allc+add))
    print(l,'added',len(add))
b2=b.copy()
b2['ds_new']=[ (r_.d-max([c for c in new_cl[r_.line] if c<=r_.d])).days for r_ in b2.itertuples()]
X2=X.copy(); X2['days_since']=b2.ds_new.values
p0=r.predict(X); p1=r.predict(X2)
n=b.units_produced.values
exp0=(p0*n).sum(); exp1=(p1*n).sum()
obs=b.defective_units.sum()
print('expected defects old/new', exp0, exp1, 'obs', obs)
print('counterfactual rate (obs + model delta):', (obs + (exp1-exp0))/b.units_produced.sum())
print('observed rate on subset', obs/n.sum(), 'all-batch A3', b0.defective_units.sum()/b0.units_produced.sum())
EOF
python3 $TMPDIR/c3.py 2>&1 | grep -v Warn

cd "$PWD" && python3 - <<'EOF'
import os
p=os.path.join(os.environ['TMPDIR'],'c3.py')
s=open(p).read()
s=s.replace("        nxt=times[i]\n        if nxt-t>pd.Timedelta(days=14):\n            t=t+pd.Timedelta(days=14); add.append(t); continue",
"        nxt=times[i]\n        if t>end: break\n        if nxt-t>pd.Timedelta(days=14):\n            t=t+pd.Timedelta(days=14); add.append(t); continue")
s=s.replace("    new_cl[l]=sorted(set(allc+add))","    new_cl[l]=sorted(set(allc+[a for a in add if a<=end]))")
open(p,'w').write(s)
EOF
python3 "$TMPDIR/c3.py" 2>&1 | grep -v Warn

cat > $TMPDIR/c4.py <<'EOF'
import os
exec(open(os.environ['TMPDIR']+'/common.py').read())
b=b0.dropna(subset=['mold_temp','humidity_pct']).copy()
b['mt_c']=b.mold_temp-210; b['h_c']=b.humidity_pct-33; b['ct_c']=b.cycle_time_s-30
b['amb_c']=b.ambient_temp_c-22; b['age_c']=b.machine_age_years-8
rhs='mt_c + h_c + ct_c + age_c + amb_c + C(shift) + C(supplier_code) + C(line)'
X=patsy.dmatrix(rhs,b,return_type='dataframe'); y=np.column_stack([b.defective_units,b.good])
r=sm.GLM(y,X,family=sm.families.Binomial()).fit()
b['pred']=r.predict(X)*b.units_produced
b['bin']=pd.cut(b.days_since,[-1,3,7,10,14,18,22,40])
g=b.groupby('bin').agg(n=('pred','size'),obs=('defective_units','sum'),exp=('pred','sum'),units=('units_produced','sum'))
g['obs/exp']=g.obs/g.exp
print(g.round(3))
g2=b[b.days_since>=18].groupby(['line','days_since']).size()
print(b[b.days_since>14].groupby('line').size())
print(b[(b.days_since>=18)&(b.days_since<=22)][['batch_id','production_date','line','days_since','units_produced','defective_units']].sort_values('production_date').head(40).to_string())
EOF
python3 $TMPDIR/c4.py 2>&1 | grep -v Warn
