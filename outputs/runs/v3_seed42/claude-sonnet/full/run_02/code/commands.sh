cd /tmp/edabench_claude_b66gxkkv; ls; head -5 *.csv; wc -l *.csv

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv');print(b.dtypes);print(b.describe(include='all').T.to_string())
print(b.batch_id.duplicated().sum())
for c in ['line','shift','operator_id','supplier_code']:print(b[c].value_counts(dropna=False))
print(b.humidity_pct.astype(str).str.extract(r'([^\d.])')[0].value_counts())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id');print(d.head(8).to_string())
print(pd.read_csv('maintenance.csv').event.value_counts())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.nunique())
print(b.humidity_pct.isna().sum(),(b.humidity_pct<0).sum(),(b.humidity_pct>100).sum(), b.humidity_pct.lt(0).sum())
print(b.humidity_pct[b.humidity_pct<5].value_counts())
print(np.histogram(b.mold_temp,bins=[-1,1,50,100,150,190,205,220,250,300,350,400,500]))
print(b.groupby('line').mold_temp.describe())
b['d']=pd.to_datetime(b.production_date)
b['m']=b.d.dt.month
print(b[b.mold_temp>300].groupby(['line','m']).size().unstack())
print(b[b.mold_temp<1].groupby(['line','m']).size().unstack())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np
import statsmodels.formula.api as smf
b=pd.read_csv('batches.csv').drop_duplicates()
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp)
b.loc[b.mold_temp==0,'mt']=np.nan
print(b.mt.median(), b.mt.describe())
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sup']=b.supplier_code.str.strip().str.upper()
b['d']=pd.to_datetime(b.production_date)
b['rate']=b.defective_units/b.units_produced
print(b.defective_units.sum()/b.units_produced.sum())
m=pd.read_csv('maintenance.csv',parse_dates=['date']);print(m[m.event!='mold_cleaning'])
cl=m[m.event=='mold_cleaning']
def since(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.d)].date
    return (r.d-c.max()).days if len(c) else np.nan
b['ds']=b.apply(since,axis=1)
print(b.ds.describe())
b.to_pickle(__import__('os').environ['TMPDIR']+'/b.pkl')
print(b.groupby('line').rate.mean())
b['wk']=b.d.dt.to_period('W')
print(b.groupby(['wk','line']).rate.mean().unstack().round(3).to_string())
print(b.groupby(pd.cut(b.ds,[-1,2,5,8,11,14,18,25,40,100])).rate.agg(['mean','size']))
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_b66gxkkv; grep -v mold_cleaning maintenance.csv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['hum2']=b.hum**2
b['dsx']=np.maximum(b.ds-14,0)
b['bad']=b.defective_units
f='bad ~ mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)+ds+dsx'
r=smf.glm(f,b.dropna(subset=['mt','hum']),family=sm.families.Binomial(),freq_weights=None).fit() if False else None
d=b.dropna(subset=['mt','hum']).copy()
d['good']=d.units_produced-d.bad
r=smf.glm(f.replace('bad','I(bad)').replace('I(bad)','bad'),d,family=sm.families.Binomial(),var_weights=d.units_produced) if False else None
y=np.column_stack([d.bad,d.good])
import patsy
X=patsy.dmatrix(f.split('~')[1],d)
r=sm.GLM(y,X,family=sm.families.Binomial()).fit(scale='X2')
print(pd.DataFrame({'c':r.params,'p':r.pvalues},index=X.design_info.column_names).round(4).to_string())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
print(b.groupby('line').machine_age_years.describe())
b['m']=b.d.dt.to_period('M')
print(b.groupby(['m','line']).mt.mean().unstack().round(1))
print(b.groupby(['m','line']).machine_age_years.mean().unstack().round(1))
print(b[['mt','hum','cycle_time_s','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur','rate']].corr().round(2).to_string())
print(b.groupby('shift').rate.mean(), b.groupby('sup').rate.mean())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
l1=b[b.line=='L1'].sort_values('d')
print(l1[(l1.d>='2025-04-08')&(l1.d<='2025-04-20')].groupby('d').mt.mean().round(1))
# L1 residual of mt on ambient
o=b[b.line!='L1'].dropna(subset=['mt'])
import statsmodels.api as sm
k=sm.OLS(o.mt,sm.add_constant(o[['ambient_temp_c']])).fit();print(k.params,k.resid.std())
a=l1.dropna(subset=['mt']);a['res']=a.mt-k.predict(sm.add_constant(a[['ambient_temp_c']]))
print(a.groupby('d').res.mean().loc['2025-04-09':'2025-04-18'].round(1))
# L2 changepoint on residual of simple model
import statsmodels.formula.api as smf
for ln in ['L2','L3','L1','L4']:
    x=b[b.line==ln].dropna(subset=['mt','hum']).sort_values('d')
    best=None
    for dt in sorted(x.d.unique())[20:-20]:
        s=(x.d>=dt)
        r=smf.ols('rate~mt+hum+cycle_time_s+ambient_temp_c+machine_age_years+ds',x.assign(s=s.astype(int)).eval('rate=rate') if False else x).fit()
    x['res']=r.resid
    ds=sorted(x.d.unique());sc=[]
    for dt in ds[20:-20]:
        s=x.d>=dt;sc.append((x.res[s].mean()-x.res[~s].mean())*np.sqrt(s.sum()*(~s).sum()/len(x)))
    i=int(np.argmax(np.abs(sc)));print(ln,ds[20+i],sc[i])
E
python3 -I $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
import statsmodels.api as sm
o=b[b.line!='L1'].dropna(subset=['mt'])
k=sm.OLS(o.mt,sm.add_constant(o[['ambient_temp_c']])).fit()
a=b[b.line=='L1'].dropna(subset=['mt']).copy();a['res']=a.mt-k.predict(sm.add_constant(a[['ambient_temp_c']]))
for dt in ['2025-04-10','2025-04-12','2025-04-13','2025-04-14','2025-04-15','2025-04-16']:
    s=a.d>=dt; print(dt,a.res[s].mean().round(2),a.res[~s].mean().round(2))
print(a[(a.d>='2025-04-10')&(a.d<='2025-04-18')][['d','res']].sort_values('d').to_string())
E
python3 -I $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,patsy
import statsmodels.api as sm
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['mtc']=np.where((b.line=='L1')&(b.d>='2025-04-15'),b.mt-8,b.mt)
print('median',b.mtc.median())
d=b.dropna(subset=['mtc','hum']).copy()
d['dsx']=np.maximum(d.ds-14,0)
d['ds14']=(d.ds>14).astype(int)
d['hc']=d.hum-30
def fit(f,d=d):
    y=np.column_stack([d.defective_units,d.units_produced-d.defective_units])
    X=patsy.dmatrix(f,d);r=sm.GLM(y,X,family=sm.families.Binomial()).fit(scale='X2')
    return r,X.design_info.column_names
base='mtc+hc+I(hc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+ds+dsx'
r,n=fit(base+'+C(line)')
print(r.params.shape)
print(pd.DataFrame({'c':r.params,'se':r.bse,'p':r.pvalues},index=n).round(4).to_string())
print(r.scale,r.deviance)
r2,n2=fit(base);print('noline',r2.deviance,r2.scale)
E
python3 -I $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_b66gxkkv; cat > $TMPDIR/a.py <<'E'
import pandas as pd,numpy as np,os,patsy
import statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle(os.environ['TMPDIR']+'/b.pkl')
b['mtc']=np.where((b.line=='L1')&(b.d>='2025-04-15'),b.mt-8,b.mt)
d=b.dropna(subset=['mtc','hum']).copy().reset_index(drop=True)
d['dsx']=np.maximum(d.ds-14,0); d['hc']=d.hum-30
d['l2post']=((d.line=='L2')&(d.d>='2025-06-15')).astype(int)
print(pd.crosstab(d.operator_id,d.line))
def fit(f):
    return smf.glm('rate~'+f,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mtc+hc+I(hc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+ds+dsx+C(line)'
r=fit(base);print(r.scale,np.linalg.matrix_rank(r.model.exog),r.model.exog.shape)
print(r.summary().tables[1])
E
python3 -I $TMPDIR/a.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_b66gxkkv; cat >> $TMPDIR/a.py <<'E'
print('=====')
d['A']=(d.sup=='SP-01').astype(int)
d['reg']=d.l2post
base='mtc+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(sup)+ds+dsx+C(line)+reg+hc:C(sup)+I(hc**2):C(sup)'
r=fit(base);print(r.summary().tables[1])
# regime scan L2 via adding step
best=[]
for dt in pd.date_range('2025-05-15','2025-07-31'):
    d['reg']=((d.line=='L2')&(d.d>=dt)).astype(int)
    rr=smf.glm('rate~'+base,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
    best.append((rr.deviance,dt))
print(sorted(best)[:4])
E
python3 -I $TMPDIR/a.py 2>&1|sed -n '/=====/,$p'

cd /tmp/edabench_claude_b66gxkkv; cat >> $TMPDIR/a.py <<'E'
print('#####')
d['reg']=((d.line=='L2')&(d.d>='2025-06-16')).astype(int)
f2='mtc+cycle_time_s+machine_age_years+C(shift)+C(sup)+ds+C(line)+reg+hc:C(sup)+I(hc**2):C(sup)'
r=fit(f2);print(r.params.round(4).to_string(),r.pvalues.round(3).to_string())
for s in ['SP-01','SP-02','SP-03']:
    x=d.copy();x['sup']=s
    p=r.predict(x);print(s,(p*x.units_produced).sum()/x.units_produced.sum())
c=r.params
for s in ['SP-01','SP-02','SP-03']:
    a=c[f'hc:C(sup)[{s}]'];q=c[f'I(hc ** 2):C(sup)[{s}]'];print(s,30-a/(2*q))
# C3
bb=b.copy();k=0.0203
r1=smf.glm('rate~ds+mtc+cycle_time_s+C(shift)+C(sup)+C(line)',d,family=sm.families.Binomial(),var_weights=d.units_produced).fit();print(r1.params['ds'])
k=r.params['ds']
bb['ds2']=bb.ds%14
lg=np.log(bb.rate/(1-bb.rate))-k*(bb.ds-bb.ds2)
bb['r2']=1/(1+np.exp(-lg))
print((bb.r2*bb.units_produced).sum()/bb.units_produced.sum())
bb['ds3']=np.minimum(bb.ds,14);lg=np.log(bb.rate/(1-bb.rate))-k*(bb.ds-bb.ds3)
print((1/(1+np.exp(-lg))*bb.units_produced).sum()/bb.units_produced.sum())
E
python3 -I $TMPDIR/a.py 2>&1|sed -n '/#####/,$p'
